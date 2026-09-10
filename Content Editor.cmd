@echo off
title DEADLINE content editor
rem Double-click to open the content editor in your browser.
rem Keep this window open while you edit; close it to stop the editor.
rem The same thing as tools\edit.cmd, which takes --lan and --port=N.
call "%~dp0tools\edit.cmd" %*
if errorlevel 1 (
  echo.
  echo The editor stopped with an error. If it says "could not listen",
  echo one is already running: use that window, or close it and try again.
  pause
)
