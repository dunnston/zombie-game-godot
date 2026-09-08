@echo off
rem Headless unit tests. Optional arg filters test files by substring.
rem The import pass rebuilds the class_name cache (about two seconds).
set GODOT=C:\Users\ryans\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe
pushd "%~dp0.."
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --headless --path . -s tests/run.gd -- %*
set RC=%ERRORLEVEL%
popd
exit /b %RC%
