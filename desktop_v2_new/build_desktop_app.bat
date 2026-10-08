@echo off
echo ========================================================
echo Building Standalone Desktop Application (PipeCounterPro)
echo ========================================================
echo Running PyInstaller with PipeCounterPro.spec...
pyinstaller --noconfirm PipeCounterPro.spec

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Build failed! Please check the log messages above.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ========================================================
echo [SUCCESS] Desktop application built successfully!
echo Executable location: dist\PipeCounterPro\PipeCounterPro.exe
echo ========================================================
pause
