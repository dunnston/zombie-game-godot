@echo off
rem Puts the native WebRTC implementation into the project (see fetch-webrtc.sh).
rem   tools\fetch-webrtc.cmd [zip-url]
setlocal
cd /d "%~dp0\.."
set "URL=%~1"
if "%URL%"=="" set "URL=https://github.com/godotengine/webrtc-native/releases/latest/download/godot-extension-webrtc-native.zip"
set "TMP_ZIP=%TEMP%\deadline-webrtc.zip"
set "TMP_DIR=%TEMP%\deadline-webrtc"
echo fetching %URL%
curl -fSL -o "%TMP_ZIP%" "%URL%" || exit /b 1
if exist "%TMP_DIR%" rmdir /s /q "%TMP_DIR%"
if exist addons\webrtc rmdir /s /q addons\webrtc
if not exist addons mkdir addons
tar -xf "%TMP_ZIP%" -C "%TEMP%" || exit /b 1
rem The zip holds one top-level folder with the .gdextension in it.
for /d %%D in ("%TEMP%\webrtc*") do move "%%D" addons\webrtc >nul
del "%TMP_ZIP%"
echo installed addons\webrtc - restart the editor once so it registers, then set Config.NET.broker
dir addons\webrtc
