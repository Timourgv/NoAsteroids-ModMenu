@echo off
title No Asteroids - Mod Menu installer
echo.
echo  No Asteroids - Mod Menu installer (menu patch v2.2.0)
echo  - Close the game before continuing.
echo  - Needs about 2 GB free disk space and a few minutes:
echo    it rebuilds resources\app.asar (about 500 MB).
echo.
echo  Running PowerShell script... (a console pause follows)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch-ModMenu.ps1"
echo.
pause
