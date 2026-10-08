@echo off
title Pipe Counter Pro v2.0
cd /d "%~dp0"

set "PYTHON_EXE="

:: 1. Check Python 3.12 in user AppData
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
    set "PYTHON_EXE=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    goto :RUN
)

:: 2. Check virtual environments if present
if exist "venv\Scripts\python.exe" (
    set "PYTHON_EXE=venv\Scripts\python.exe"
    goto :RUN
)

:: 3. Fallback to system python
set "PYTHON_EXE=python"

:RUN
echo ===================================================
echo   Pipe Counter Pro v2.0 - Starting Application...
echo   Python: %PYTHON_EXE%
echo ===================================================
"%PYTHON_EXE%" desktop_gui.py
if errorlevel 1 (
    echo.
    echo ===================================================
    echo [ERROR] Pipe Counter Pro exited with code %errorlevel%.
    echo Please make sure PyQt6, opencv-python, ultralytics,
    echo and pandas are installed in your Python environment.
    echo ===================================================
    pause
)

