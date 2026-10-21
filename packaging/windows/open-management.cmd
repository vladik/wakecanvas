@echo off
setlocal
set "PORT=4000"
if /I "%~1"=="--port" set "PORT=%~2"
start "" "http://localhost:%PORT%/manage"
