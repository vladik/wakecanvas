@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\initialize-wakecanvas.ps1" %*
if errorlevel 1 pause
