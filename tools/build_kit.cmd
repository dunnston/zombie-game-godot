@echo off
rem Rebuilds the building kit (assets\models\buildings\kit.glb) from
rem tools\build_kit.py with the owner's Blender. Run from anywhere.
set BLENDER=C:\Program Files\Blender Foundation\Blender 4.3\blender.exe
pushd "%~dp0.."
"%BLENDER%" --background --python tools\build_kit.py
set RC=%ERRORLEVEL%
popd
exit /b %RC%
