@echo off
title Build Pipe Counter Pro v2.0 Desktop Installer
cd /d "%~dp0"

echo ========================================================
echo   Building Pipe Counter Pro v2.0.0 Desktop Installer
echo ========================================================
echo.

set "PYTHON_EXE="
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
    set "PYTHON_EXE=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
) else (
    set "PYTHON_EXE=python"
)

set "ISCC_EXE=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

if not exist "%ISCC_EXE%" (
    if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
        set "ISCC_EXE=C:\Program Files\Inno Setup 6\ISCC.exe"
    ) else (
        echo [ERROR] Inno Setup compiler (ISCC.exe) not found!
        echo Please ensure Inno Setup 6 is installed.
        pause
        exit /b 1
    )
)

echo [1/2] Compiling standalone desktop binaries with PyInstaller...
echo Using Python: %PYTHON_EXE%
"%PYTHON_EXE%" -m PyInstaller --noconfirm PipeCounterPro.spec
if errorlevel 1 (
    echo [ERROR] PyInstaller compilation failed!
    pause
    exit /b %errorlevel%
)

echo.
echo [2/2] Generating Windows Setup Installer (.exe) with Inno Setup...
echo Using Inno Setup: %ISCC_EXE%
"%ISCC_EXE%" installer_setup.iss
if errorlevel 1 (
    echo [ERROR] Inno Setup compilation failed!
    pause
    exit /b %errorlevel%
)

echo.
echo ========================================================
echo   [SUCCESS] Desktop Installer Created!
echo   Location: dist_installer\PipeCounterPro_v2.0.0_Setup.exe
echo ========================================================
pause
