@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\run-wakecanvas.ps1" %*
if errorlevel 1 pause
