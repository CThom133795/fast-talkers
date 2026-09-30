@echo off
rem Two-process network test. Usage: tests\run_net_pair.cmd [port] [steps]   (defaults 24651, lobby)
set PORT=%1
if "%PORT%"=="" set PORT=24651
set STEPS=%2
if "%STEPS%"=="" set STEPS=lobby
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_net_pair.ps1" -Port %PORT% -Steps %STEPS%
exit /b %ERRORLEVEL%
