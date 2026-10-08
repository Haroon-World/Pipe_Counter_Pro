@echo off
title Pipe Counter Pro - Flutter Web
cd /d "%~dp0"
echo ===================================================
echo   Pipe Counter Pro v2.0 - Starting Web Version...
echo ===================================================
flutter.bat run -d chrome
if errorlevel 1 (
    echo.
    echo Exited with error level %errorlevel%.
    pause
)
