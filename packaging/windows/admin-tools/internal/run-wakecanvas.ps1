$ErrorActionPreference = 'Stop'
$Port = 4000
$StartupDelaySeconds = 3
$Profile = 'manual'
$NoBrowser = $false
$Once = $false

for ($index = 0; $index -lt $args.Count; $index++) {
    switch ($args[$index]) {
        '--port' {
            if ($index + 1 -ge $args.Count) { throw '--port requires a value.' }
            $index++
            $Port = [int]$args[$index]
        }
        '--startup-delay' {
            if ($index + 1 -ge $args.Count) { throw '--startup-delay requires a value.' }
            $index++
            $StartupDelaySeconds = [int]$args[$index]
        }
        '--profile' {
            if ($index + 1 -ge $args.Count) { throw '--profile requires a value.' }
            $index++
            $Profile = $args[$index].ToLowerInvariant()
        }
        '--no-browser' { $NoBrowser = $true }
        '--once' { $Once = $true }
        '--help' {
            Write-Host 'Usage: run-wakecanvas.cmd [--profile manual|kiosk|hosted] [--port PORT] [--no-browser] [--once]'
            exit 0
        }
        default { throw "Unknown option: $($args[$index])" }
    }
}

if ($Profile -notin @('manual', 'kiosk', 'hosted')) { throw "Invalid profile: $Profile" }
if ($Port -lt 1 -or $Port -gt 65535) { throw '--port must be between 1 and 65535.' }
if ($StartupDelaySeconds -lt 0) { throw '--startup-delay cannot be negative.' }

$installRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$release = Join-Path $installRoot 'bin\wake_canvas.bat'
$initializer = Join-Path $PSScriptRoot 'initialize-wakecanvas.ps1'
$dataRoot = Join-Path $installRoot 'data'
$healthUrl = "http://127.0.0.1:$Port/health"
$displayUrl = "http://127.0.0.1:$Port/display"

if (-not (Test-Path -LiteralPath $release)) {
    throw "WakeCanvas release executable not found: $release"
}

if (-not (Test-Path -LiteralPath (Join-Path $dataRoot 'config\management_code'))) {
    if ($Profile -eq 'manual') {
        & $initializer
    } else {
        & $initializer --non-interactive
    }
}

$env:PHX_SERVER = 'true'
$env:WAKECANVAS_PROFILE = $Profile
$env:PORT = $Port.ToString()
$env:PHX_HOST = 'localhost'
$env:PHX_SCHEME = 'http'
$env:PHX_URL_PORT = $Port.ToString()
$env:WAKECANVAS_BIND_IP = if ($Profile -eq 'manual') { '127.0.0.1' } else { '0.0.0.0' }
$env:WAKECANVAS_DATA_ROOT = $dataRoot

$seedRoot = Join-Path $installRoot 'seeds'
if (Test-Path -LiteralPath $seedRoot) {
    $seed = Get-ChildItem -LiteralPath $seedRoot -Filter '*.wakecanvas-instance' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($seed) {
        $env:WAKECANVAS_BUNDLED_INSTANCES = $seedRoot
        $env:WAKECANVAS_AUTO_ACTIVATE_SEED = 'true'
    }
}

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
    $launcherExitCode = $null

    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        if (Test-WakeCanvasReady) { return }
        if ($script:serverProcess.HasExited -and $null -eq $launcherExitCode) {
            # The Windows release command can exit after handing startup to the
            # detached Erlang VM. Continue probing the endpoint rather than
            # treating that handoff as an application failure.
            $launcherExitCode = $script:serverProcess.ExitCode
        }
        Start-Sleep -Seconds 1
    }
    if ($null -ne $launcherExitCode) {
        throw "WakeCanvas did not become ready at $healthUrl (launcher exit code $launcherExitCode)"
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

function Open-ManualBrowser {
    if (-not $NoBrowser) {
        Start-Process -FilePath $displayUrl
    }
}

$browserProcess = $null
$serverProcess = $null
$healthFailures = 0
Start-WakeCanvasServer
Start-Sleep -Seconds $StartupDelaySeconds

if ($Profile -eq 'manual') {
    Open-ManualBrowser
    Write-Host "WakeCanvas is running at $displayUrl"
    Write-Host "Management: http://127.0.0.1:$Port/manage"
    Write-Host 'Use stop-wakecanvas.cmd when you are finished.'
    exit 0
}

if ($Profile -eq 'hosted' -or $Once) {
    Write-Host "WakeCanvas is ready at $displayUrl"
    exit 0
}

try {
    $browserProcess = Start-KioskBrowser
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
} finally {
    Stop-WakeCanvasServer
}
