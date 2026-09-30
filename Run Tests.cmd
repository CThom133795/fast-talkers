@echo off
setlocal
set "FAST_TALKERS_EDITOR=%~dp0..\..\work\tools\godot\Godot_v4.4.1-stable_win64_console.exe"
if not exist "%FAST_TALKERS_EDITOR%" (
  echo Portable editor not found. Use Godot 4.4.1 to run tests/integration.gd and tests/free_roam.gd.
  pause
  exit /b 1
)
echo [1/7] Contract loop integration checks...
"%FAST_TALKERS_EDITOR%" --headless --path "%~dp0." --log-file "%~dp0..\..\work\integration-test.log" --script res://tests/integration.gd
set "FAST_TALKERS_CONTRACT=%errorlevel%"
echo [2/7] Free roam, arsenal, security and car checks...
"%FAST_TALKERS_EDITOR%" --headless --path "%~dp0." --log-file "%~dp0..\..\work\free-roam-test.log" --script res://tests/free_roam.gd
set "FAST_TALKERS_FREE=%errorlevel%"
echo [3/7] Chaos soak (6000 frames)...
"%FAST_TALKERS_EDITOR%" --headless --fixed-fps 60 --path "%~dp0." --log-file "%~dp0..\..\work\soak-test.log" --script res://tests/soak.gd
set "FAST_TALKERS_SOAK=%errorlevel%"
echo [4/7] Map, interiors and railings...
"%FAST_TALKERS_EDITOR%" --headless --path "%~dp0." --log-file "%~dp0..\..\work\map-test.log" --script res://tests/map_interiors.gd
set "FAST_TALKERS_MAP=%errorlevel%"
echo [5/7] Vehicle art...
"%FAST_TALKERS_EDITOR%" --headless --path "%~dp0." --log-file "%~dp0..\..\work\vehicle-test.log" --script res://tests/vehicle_art.gd
set "FAST_TALKERS_VEHICLES=%errorlevel%"
echo [6/7] Doors, GPS and wheelman wiring...
"%FAST_TALKERS_EDITOR%" --headless --path "%~dp0." --log-file "%~dp0..\..\work\wiring-test.log" --script res://tests/wiring_05.gd
set "FAST_TALKERS_WIRING=%errorlevel%"
echo [7/7] Vehicle glass, handling and camera...
"%FAST_TALKERS_EDITOR%" --headless --path "%~dp0." --log-file "%~dp0..\..\work\vehicles06-test.log" --script res://tests/vehicles_06.gd
set "FAST_TALKERS_VEH06=%errorlevel%"
echo.
echo Contract: %FAST_TALKERS_CONTRACT%   Free roam: %FAST_TALKERS_FREE%   Soak: %FAST_TALKERS_SOAK%   Map: %FAST_TALKERS_MAP%   Vehicles: %FAST_TALKERS_VEHICLES%   Wiring: %FAST_TALKERS_WIRING%   Veh06: %FAST_TALKERS_VEH06%
echo 0 means every check passed. Logs are in the work folder.
pause
if not "%FAST_TALKERS_CONTRACT%"=="0" exit /b %FAST_TALKERS_CONTRACT%
if not "%FAST_TALKERS_FREE%"=="0" exit /b %FAST_TALKERS_FREE%
if not "%FAST_TALKERS_SOAK%"=="0" exit /b %FAST_TALKERS_SOAK%
if not "%FAST_TALKERS_MAP%"=="0" exit /b %FAST_TALKERS_MAP%
if not "%FAST_TALKERS_VEHICLES%"=="0" exit /b %FAST_TALKERS_VEHICLES%
if not "%FAST_TALKERS_WIRING%"=="0" exit /b %FAST_TALKERS_WIRING%
exit /b %FAST_TALKERS_VEH06%
