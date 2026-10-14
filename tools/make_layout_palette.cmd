@echo off
rem Makes what the layout editor needs in scenes\layouts\: the tile library
rem the GridMap paints with, one palette scene per piece the game can stand
rem (drag them into a layout scene), the empty template, and a scene per
rem layout already in data\layouts.json. Run it again after a new kind of
rem prop joins PropModels. PROJECT.md section 10, "House layouts".
set GODOT=C:\Users\ryans\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe
pushd "%~dp0.."
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --headless --path . -s tools/make_layout_palette.gd
set RC=%ERRORLEVEL%
popd
exit /b %RC%
