$ErrorActionPreference = 'Stop'
$Port = 4000
for ($index = 0; $index -lt $args.Count; $index++) {
    switch ($args[$index]) {
        '--port' {
            if ($index + 1 -ge $args.Count) { throw '--port requires a value.' }
            $index++
            $Port = [int]$args[$index]
        }
        '--help' {
            Write-Host 'Usage: install-autostart.cmd [--port PORT]'
            exit 0
        }
        default { throw "Unknown option: $($args[$index])" }
    }
}
if ($Port -lt 1 -or $Port -gt 65535) { throw '--port must be between 1 and 65535.' }

$launcher = Join-Path $PSScriptRoot 'run-wakecanvas.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "WakeCanvas launcher not found: $launcher"
}

$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" --profile kiosk --port $Port"
$action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -RestartCount 20 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable

Register-ScheduledTask `
    -TaskName 'WakeCanvas Kiosk' `
    -Description 'Starts WakeCanvas and its fullscreen display when this kiosk user signs in.' `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User $env:USERNAME `
    -Force | Out-Null

Write-Host 'WakeCanvas autostart installed for the current Windows user.'
Write-Host 'The kiosk will start at the next sign-in, or run start-kiosk-mode.cmd now.'
