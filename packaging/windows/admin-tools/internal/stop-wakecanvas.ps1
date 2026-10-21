[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$release = Join-Path $installRoot 'bin\wake_canvas.bat'
if (-not (Test-Path -LiteralPath $release)) {
    throw "WakeCanvas release executable not found: $release"
}

# Stop a kiosk supervisor before stopping the VM; otherwise its health monitor
# would interpret an operator-requested stop as a failure and restart WakeCanvas.
Get-CimInstance Win32_Process | Where-Object {
    $_.ProcessId -ne $PID -and
    $_.Name -in @('powershell.exe', 'pwsh.exe') -and
    $_.CommandLine -and
    $_.CommandLine.IndexOf($installRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
    $_.CommandLine.IndexOf('run-wakecanvas.ps1', [StringComparison]::OrdinalIgnoreCase) -ge 0
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

& $release stop 2>$null
$stopExitCode = $LASTEXITCODE

# A release-local EPMD process can survive a clean VM shutdown and keep the
# extracted directory locked. Kiosk browser processes can also hold their
# profile below data/. Only processes tied to this exact installation path are
# eligible; development VMs and unrelated browser windows are never selected.
$deadline = (Get-Date).AddSeconds(10)
do {
    $remaining = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -and
        $_.CommandLine.IndexOf($installRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $_.Name -in @(
            'erl.exe',
            'epmd.exe',
            'beam.smp.exe',
            'msedge.exe',
            'chrome.exe',
            'chromium.exe'
        )
    })

    if ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
} while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline)

$remaining | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

if ($remaining.Count -gt 0) {
    Start-Sleep -Milliseconds 500
}

if ($stopExitCode -ne 0 -and $remaining.Count -eq 0) {
    Write-Host 'WakeCanvas was already stopped. Release-local helper processes were cleaned up.'
} else {
    Write-Host 'WakeCanvas and its release-local helper processes have stopped.'
}
