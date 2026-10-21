[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Archive,
    [int]$Port = 4410,
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$ExpectedInstanceId
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$archivePath = [IO.Path]::GetFullPath($Archive)
$testRoot = Join-Path $repoRoot ('.tmp\windows-smoke-' + [Guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $testRoot 'WakeCanvas'
$release = Join-Path $installRoot 'bin\wake_canvas.bat'

if (-not (Test-Path -LiteralPath $archivePath)) {
    throw "Release archive not found: $archivePath"
}

function Assert-SeedInstance {
    if (-not $ExpectedInstanceId) { return }

    $instanceRoot = Join-Path $installRoot "data\instances\$ExpectedInstanceId"
    if (-not (Test-Path -LiteralPath $instanceRoot -PathType Container)) {
        throw "Expected seeded instance was not imported: $ExpectedInstanceId"
    }

    $displayUrl = "http://127.0.0.1:$Port/i/$ExpectedInstanceId/display"
    $response = Invoke-WebRequest -UseBasicParsing -Uri $displayUrl -TimeoutSec 10
    if ($response.StatusCode -ne 200) {
        throw "Seeded display returned HTTP $($response.StatusCode)."
    }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $testRoot

    foreach ($command in @('start-wakecanvas.cmd', 'stop-wakecanvas.cmd', 'start-kiosk-mode.cmd', 'open-management.cmd')) {
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot $command) -PathType Leaf)) {
            throw "Missing public Windows command: $command"
        }
    }
    foreach ($legacyPath in @('Start WakeCanvas.cmd', 'Stop WakeCanvas.cmd', 'Start Kiosk Mode.cmd', 'Open Management.cmd', 'Admin Tools')) {
        if (Test-Path -LiteralPath (Join-Path $installRoot $legacyPath)) {
            throw "Legacy Windows packaging name remains in the release root: $legacyPath"
        }
    }
    foreach ($command in @('initialize-wakecanvas.cmd', 'install-autostart.cmd', 'uninstall-autostart.cmd', 'run-wakecanvas.cmd', 'stop-wakecanvas.cmd')) {
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot "admin-tools\$command") -PathType Leaf)) {
            throw "Missing Windows admin command: $command"
        }
    }

    $adminTools = Join-Path $installRoot 'admin-tools'
    & (Join-Path $adminTools 'initialize-wakecanvas.cmd') --management-code '123456'
    & (Join-Path $installRoot 'start-wakecanvas.cmd') --port $Port --no-browser --once --startup-delay 0

    $healthUrl = "http://127.0.0.1:$Port/health"
    try {
        $firstStatus = (Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 5).StatusCode
    } catch {
        if (-not $_.Exception.Response) { throw }
        $firstStatus = [int]$_.Exception.Response.StatusCode
    }

    $database = Join-Path $installRoot 'data\wake_canvas.sqlite3'
    $secret = Join-Path $installRoot 'data\config\secret_key_base'
    if (-not (Test-Path -LiteralPath $database)) { throw 'Platform database was not created.' }
    if (-not (Test-Path -LiteralPath $secret)) { throw 'Persistent cookie secret was not created.' }
    Assert-SeedInstance

    & (Join-Path $installRoot 'stop-wakecanvas.cmd')
    Start-Sleep -Seconds 2

    & (Join-Path $installRoot 'start-wakecanvas.cmd') --port $Port --no-browser --once --startup-delay 0
    try {
        $secondStatus = (Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 5).StatusCode
    } catch {
        if (-not $_.Exception.Response) { throw }
        $secondStatus = [int]$_.Exception.Response.StatusCode
    }
    Assert-SeedInstance

    Write-Host "Windows release smoke test passed (health HTTP $secondStatus; initial HTTP $firstStatus)."
} finally {
    if (Test-Path -LiteralPath $release) {
        $env:WAKECANVAS_DATA_ROOT = Join-Path $installRoot 'data'
        $env:PORT = $Port.ToString()
        & $release stop 2>$null
    }

    $expectedParent = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp'))
    $resolvedTest = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($expectedParent + [IO.Path]::DirectorySeparatorChar) -and (Test-Path -LiteralPath $resolvedTest)) {
        # The release-local EPMD daemon outlives the stopped VM on Windows and
        # keeps its executable directory locked. Stop only processes whose
        # command line points inside this uniquely generated smoke directory.
        Get-CimInstance Win32_Process | Where-Object {
            $_.Name -in @('erl.exe', 'epmd.exe', 'beam.smp.exe') -and
            $_.CommandLine -and
            $_.CommandLine.Contains($resolvedTest)
        } | ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 500
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
