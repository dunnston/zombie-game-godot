@echo off
rem The layout lab: the real game on a lawn with one hand-laid building on
rem it, peaceful, so a layout can be walked through and confirmed before
rem the town gets it (PROJECT.md section 10, "House layouts").
rem
rem   .\tools\lab.cmd <layout>          walk it
rem   .\tools\lab.cmd <layout> --shot   photograph it into .lab\<layout>.png and quit
rem
rem <layout> is a row id in data\layouts.json (`.\tools\import_layout.cmd`
rem makes one from a plan in metres).
set GODOT=C:\Users\ryans\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe
if "%~1"=="" (
	echo usage: tools\lab.cmd ^<layout^> [--shot]
	exit /b 2
)
pushd "%~dp0.."
set SHOT=
if "%~2"=="--shot" (
	if not exist .lab mkdir .lab
	set SHOT=--shot=%CD%\.lab\%~1.png
)
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --path . --resolution 1280x720 -- --lab=%~1 --stage=3d %SHOT%
set RC=%ERRORLEVEL%
popd
exit /b %RC%
