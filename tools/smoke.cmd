@echo off
rem Runs the real game windowed in smoke mode. Output lands in .smoke\.
set GODOT=C:\Users\ryans\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe
pushd "%~dp0.."
if exist .smoke rmdir /s /q .smoke
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --path . --resolution 1280x720 -- --smoke "--smoke-out=%CD%\.smoke" %*
set RC=%ERRORLEVEL%
popd
exit /b %RC%
