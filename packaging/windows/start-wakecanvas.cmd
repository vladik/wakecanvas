@echo off
setlocal
call "%~dp0admin-tools\run-wakecanvas.cmd" --profile manual %*
if errorlevel 1 pause
