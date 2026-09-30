@echo off
rem Two-process network test. Usage: tests\run_net_pair.cmd [port] [steps]   (defaults 24651, lobby; e.g. 24651 lobby,round)
set PORT=%1
if "%PORT%"=="" set PORT=24651
set STEPS=%2
if not "%3"=="" set STEPS=%2,%3
if "%STEPS%"=="" set STEPS=lobby
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_net_pair.ps1" -Port %PORT% -Steps %STEPS%
exit /b %ERRORLEVEL%
