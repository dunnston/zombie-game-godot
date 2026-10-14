@echo off
rem Zips the static props (assets\models\props, not in git: too big for the
rem LFS quota) into props.zip in the project folder, to send to a teammate.
rem They unzip it into assets\models\ so the files land in assets\models\props\.
rem Run from anywhere.
pushd "%~dp0.."
del props.zip 2>nul
C:\Windows\System32\tar.exe -a -cf props.zip -C assets\models props
set RC=%ERRORLEVEL%
popd
exit /b %RC%
