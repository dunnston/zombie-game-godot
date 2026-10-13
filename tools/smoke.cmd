@echo off
rem Runs the real game windowed in smoke mode. Output lands in .smoke\.
rem Two runs: the ninety-odd checkpoints on the 2D stage they were written
rem for, then the 3D stage's own leg into .smoke\3d\. Either failing fails.
set GODOT=C:\Users\ryans\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe
pushd "%~dp0.."
if exist .smoke rmdir /s /q .smoke
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --path . --resolution 1280x720 -- --smoke "--smoke-out=%CD%\.smoke" --stage=2d %*
set RC=%ERRORLEVEL%
if not "%RC%"=="0" goto done
"%GODOT%" --path . --resolution 1280x720 -- --smoke "--smoke-out=%CD%\.smoke\3d" --stage=3d %*
set RC=%ERRORLEVEL%
:done
popd
exit /b %RC%
