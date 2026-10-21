@echo off
setlocal
call "%~dp0admin-tools\run-wakecanvas.cmd" --profile kiosk %*
if errorlevel 1 pause
