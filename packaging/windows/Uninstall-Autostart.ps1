[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$task = Get-ScheduledTask -TaskName 'WakeCanvas Kiosk' -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName 'WakeCanvas Kiosk' -Confirm:$false
    Write-Host 'WakeCanvas autostart removed. Installation data was not deleted.'
} else {
    Write-Host 'WakeCanvas autostart is not installed.'
}
