@echo off
set "JAVA_HOME=D:\Android\jdk-17"
set "ANDROID_HOME=D:\Android\sdk"
set "ANDROID_SDK_ROOT=D:\Android\sdk"
set "PATH=%JAVA_HOME%\bin;%ANDROID_HOME%\cmdline-tools\latest\bin;%ANDROID_HOME%\platform-tools;%PATH%"

echo ========================================================
echo Building Lightweight Android APK (PipeCounterPro)
echo ========================================================

call D:\flutter\bin\flutter.bat build apk --release

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] APK Build failed! Please check the output above.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ========================================================
echo [SUCCESS] APK compiled successfully!
echo Location: build\app\outputs\flutter-apk\app-release.apk
echo ========================================================
pause
