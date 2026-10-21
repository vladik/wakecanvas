@echo off
setlocal
call "%~dp0admin-tools\stop-wakecanvas.cmd" %*
if errorlevel 1 pause
