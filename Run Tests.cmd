@echo off
setlocal EnableDelayedExpansion
set "FAST_TALKERS_EDITOR=%~dp0..\..\work\tools\godot\Godot_v4.4.1-stable_win64_console.exe"
if not exist "%FAST_TALKERS_EDITOR%" (
  echo Portable editor not found. Use Godot 4.4.1 to run the suites in tests\.
  pause
  exit /b 1
)
set "FAST_TALKERS_FAILED="
set "FAST_TALKERS_SUMMARY="
set /a FAST_TALKERS_N=0
for %%S in (integration free_roam soak map_interiors vehicle_art wiring_05 vehicles_06 map_06 city_detail city_audit building_landmarks sfx_audio social_features net_security voice remote_player chat_ui net_lobby_ui week_flow stair_walk prefabs city_fill) do (
  set /a FAST_TALKERS_N+=1
  echo [!FAST_TALKERS_N!/22] %%S...
  set "FAST_TALKERS_EXTRA="
  if "%%S"=="soak" set "FAST_TALKERS_EXTRA=--fixed-fps 60"
  if "%%S"=="city_detail" set "FAST_TALKERS_EXTRA=--fixed-fps 60"
  "%FAST_TALKERS_EDITOR%" --headless !FAST_TALKERS_EXTRA! --path "%~dp0." --log-file "%~dp0..\..\work\%%S-test.log" --script res://tests/%%S.gd
  set "FAST_TALKERS_RC=!errorlevel!"
  set "FAST_TALKERS_SUMMARY=!FAST_TALKERS_SUMMARY! %%S=!FAST_TALKERS_RC!"
  if not "!FAST_TALKERS_RC!"=="0" set "FAST_TALKERS_FAILED=!FAST_TALKERS_FAILED! %%S"
)
echo.
echo Results:!FAST_TALKERS_SUMMARY!
echo 0 means every check passed. Logs are in the work folder (^<suite^>-test.log).
echo Two-PC-style network round: powershell -File tests\run_net_pair.ps1 -Steps lobby,round
if defined FAST_TALKERS_FAILED (
  echo FAILED:!FAST_TALKERS_FAILED!
  pause
  exit /b 1
)
echo ALL SUITES PASSED
pause
exit /b 0
