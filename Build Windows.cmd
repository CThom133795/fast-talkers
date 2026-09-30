@echo off
setlocal
set "FAST_TALKERS_EDITOR=%~dp0..\..\work\tools\godot\Godot_v4.4.1-stable_win64_console.exe"
if not exist "%FAST_TALKERS_EDITOR%" (
  echo Portable editor not found. Open the project in Godot and configure the Windows export template.
  pause
  exit /b 1
)
"%FAST_TALKERS_EDITOR%" --headless --path "%~dp0." --log-file "%~dp0..\..\work\export.log" --export-release "Windows Desktop"
set "FAST_TALKERS_RESULT=%errorlevel%"
pause
exit /b %FAST_TALKERS_RESULT%
