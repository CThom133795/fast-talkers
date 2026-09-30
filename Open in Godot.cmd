@echo off
setlocal
set "FAST_TALKERS_EDITOR=%~dp0..\..\work\tools\godot\Godot_v4.4.1-stable_win64.exe"
if not exist "%FAST_TALKERS_EDITOR%" (
  echo Portable editor not found. Import project.godot in Godot 4.4.1.
  pause
  exit /b 1
)
start "" "%FAST_TALKERS_EDITOR%" --editor --path "%~dp0."
