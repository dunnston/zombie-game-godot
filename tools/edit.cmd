@echo off
rem Local content editor for data/*.json. Opens a browser on
rem http://127.0.0.1:8765 and runs until Ctrl+C. Nothing is hosted anywhere.
rem   tools\edit               this machine only
rem   tools\edit --lan         also a phone on the same wifi (never public)
rem   tools\edit --port=9000 --no-open
rem Set GODOT first if the engine lives somewhere else on your machine.
if "%GODOT%"=="" set GODOT=C:\Users\ryans\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe
pushd "%~dp0.."
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --headless --path . -s tools/edit_server.gd -- %*
set RC=%ERRORLEVEL%
popd
exit /b %RC%
