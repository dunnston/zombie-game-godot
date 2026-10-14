@echo off
rem Turns a house plan in metres into a layout row in data\layouts.json
rem (PROJECT.md section 10, "House layouts"). The plan is a
rem house_layout.json as the owner's drafts come, or the .zip it came in.
rem
rem   .\tools\import_layout.cmd <plan.json or .zip> <layout-id> [--floor=N]
rem
rem Prints what every object became and what the checks found. Then
rem `.\tools\lab.cmd <layout-id>` to walk it.
set GODOT=C:\Users\ryans\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe
if "%~2"=="" (
	echo usage: tools\import_layout.cmd ^<plan.json or .zip^> ^<layout-id^> [--floor=N]
	exit /b 2
)
pushd "%~dp0.."
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --headless --path . -s tools/import_layout.gd -- "%~f1" %2 %3
set RC=%ERRORLEVEL%
popd
exit /b %RC%
