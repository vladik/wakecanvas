[CmdletBinding()]
param([int]$Port = 4000)

$ErrorActionPreference = 'Stop'
$installRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Start-WakeCanvas.ps1')) {
    $installRoot = $PSScriptRoot
}

$launcher = Join-Path $installRoot 'Start-WakeCanvas.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "WakeCanvas launcher not found: $launcher"
}

$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -Port $Port"
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
Write-Host 'The kiosk will start at the next sign-in, or run Start-WakeCanvas.ps1 now.'
