[CmdletBinding()]
param(
    [int]$Port = 4000,
    [int]$StartupDelaySeconds = 3,
    [switch]$NoBrowser,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$installRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'bin\wake_canvas.bat')) {
    $installRoot = $PSScriptRoot
}

$release = Join-Path $installRoot 'bin\wake_canvas.bat'
$initializer = Join-Path $installRoot 'Initialize-WakeCanvas.ps1'
$dataRoot = Join-Path $installRoot 'data'
$healthUrl = "http://127.0.0.1:$Port/health"
$displayUrl = "http://127.0.0.1:$Port/display"

if (-not (Test-Path -LiteralPath $release)) {
    throw "WakeCanvas release executable not found: $release"
}

if (-not (Test-Path -LiteralPath (Join-Path $dataRoot 'config\management_code'))) {
    & $initializer -NonInteractive
}

$env:PHX_SERVER = 'true'
$env:PORT = $Port.ToString()
$env:PHX_HOST = 'localhost'
$env:PHX_SCHEME = 'http'
$env:PHX_URL_PORT = $Port.ToString()
$env:WAKECANVAS_BIND_IP = '0.0.0.0'
$env:WAKECANVAS_DATA_ROOT = $dataRoot

function Test-WakeCanvasReady {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 3 | Out-Null
        return $true
    } catch {
        # A 503 diagnostic response still proves that Phoenix is reachable. The
        # management screen explains the unhealthy subsystem to the operator.
        return $null -ne $_.Exception.Response
    }
}

function Start-WakeCanvasServer {
    if (Test-WakeCanvasReady) { return }
    $script:serverProcess = Start-Process -FilePath $release -ArgumentList @('start') -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        if (Test-WakeCanvasReady) { return }
        if ($script:serverProcess.HasExited) {
            throw "WakeCanvas exited during startup with code $($script:serverProcess.ExitCode)"
        }
        Start-Sleep -Seconds 1
    }
    throw "WakeCanvas did not become ready at $healthUrl"
}

function Stop-WakeCanvasServer {
    & $release stop | Out-Null
    if ($serverProcess -and -not $serverProcess.HasExited) {
        if (-not $serverProcess.WaitForExit(10000)) {
            Stop-Process -Id $serverProcess.Id -Force
        }
    }
    $script:serverProcess = $null
}

function Start-KioskBrowser {
    if ($NoBrowser) { return $null }

    $candidates = @(
        "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    if ($candidates.Count -gt 0) {
        $browser = $candidates[0]
        $profile = Join-Path $dataRoot 'browser-profile'
        New-Item -ItemType Directory -Force -Path $profile | Out-Null
        $arguments = @(
            '--kiosk', $displayUrl,
            '--no-first-run',
            '--disable-session-crashed-bubble',
            '--autoplay-policy=no-user-gesture-required',
            "--user-data-dir=$profile"
        )
        return Start-Process -FilePath $browser -ArgumentList $arguments -PassThru
    }

    Write-Warning 'Edge or Chrome was not found; opening the display in the default browser.'
    Start-Process $displayUrl
    return $null
}

$browserProcess = $null
$serverProcess = $null
$healthFailures = 0
try {
    Start-WakeCanvasServer
    Start-Sleep -Seconds $StartupDelaySeconds
    $browserProcess = Start-KioskBrowser

    if ($Once) {
        Write-Host "WakeCanvas is ready at $displayUrl"
    } else {
        Write-Host "WakeCanvas kiosk is running. Management: http://127.0.0.1:$Port/manage"
        Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -ne '127.0.0.1' } |
            Select-Object -ExpandProperty IPAddress -Unique |
            ForEach-Object { Write-Host "LAN management: http://$($_):$Port/manage" }
        while ($true) {
            Start-Sleep -Seconds 5

            if (Test-WakeCanvasReady) {
                $healthFailures = 0
            } else {
                $healthFailures++
                if ($healthFailures -ge 3) {
                    Write-Warning 'WakeCanvas stopped responding; restarting the release.'
                    Stop-WakeCanvasServer
                    Start-WakeCanvasServer
                    $healthFailures = 0
                }
            }

            if (-not $NoBrowser -and $browserProcess -and $browserProcess.HasExited) {
                Write-Warning 'The kiosk browser closed; reopening it.'
                $browserProcess = Start-KioskBrowser
            }
        }
    }
} finally {
    if (-not $Once) {
        Stop-WakeCanvasServer
    }
}
