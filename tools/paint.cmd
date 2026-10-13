@echo off
rem Paints Blender's cel renders (art\render\<char>) into the bible's style with
rem ComfyUI, writing game-ready sheets to assets\sprites\<char>. Starts ComfyUI
rem headless if it is not already running. Render first with tools\sprites.
rem   tools\paint player walk
rem   tools\paint player walk --dirs S,SE --denoise 0.5 --weight 0.8 --seed 7
rem Runs in the deadline-art conda env (Pillow, numpy). See tools\sprites\paint.py.
set PY=C:\Users\ryans\miniconda3\envs\deadline-art\python.exe
pushd "%~dp0.."
"%PY%" tools\sprites\paint.py %*
set RC=%ERRORLEVEL%
popd
exit /b %RC%
