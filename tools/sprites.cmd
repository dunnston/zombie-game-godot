@echo off
rem Renders sprite sheets from a scripted Blender character, headless.
rem   tools\sprites mannequin turnaround    the camera test
rem   tools\sprites player walk             -> assets\sprites\player\player_walk_<dir>_8f.png
rem Options after the two names: --size 128  --dirs S,SE,E,NE,N  --out <dir>  --save-blend
rem Characters are tools\sprites\characters\*.py, animations tools\sprites\animations\*.py.
rem Set BLENDER first if Blender lives somewhere else on your machine.
if "%BLENDER%"=="" set BLENDER=C:\Program Files\Blender Foundation\Blender 4.3\blender.exe
pushd "%~dp0.."
"%BLENDER%" -b --python tools\sprites\run.py -- %*
set RC=%ERRORLEVEL%
popd
exit /b %RC%
