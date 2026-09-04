@echo off
title Pipe Counter Pro - Android APK Builder
cls
echo ================================================================
echo    PIPE COUNTER PRO - LOCAL ANDROID APK BUILDER
echo ================================================================
echo.
echo [1/3] Setting up local Java 17 and Android SDK environment...
set "JAVA_HOME=D:\Android\jdk-17"
set "ANDROID_HOME=D:\Android\sdk"
set "ANDROID_SDK_ROOT=D:\Android\sdk"
set "PATH=%JAVA_HOME%\bin;%ANDROID_HOME%\cmdline-tools\latest\bin;%ANDROID_HOME%\platform-tools;%PATH%"

echo JAVA_HOME: %JAVA_HOME%
echo ANDROID_HOME: %ANDROID_HOME%
echo.

cd /d "D:\TRS\Pipe Counter"
echo [2/3] Compiling Release APK with live output...
echo.

call D:\flutter\bin\flutter.bat build apk --release

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ================================================================
    echo [ERROR] Build encountered an issue. See details above.
    echo ================================================================
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ================================================================
echo [SUCCESS] Your lightweight APK has been generated!
echo Location: build\app\outputs\flutter-apk\app-release.apk
echo ================================================================
copy "build\app\outputs\flutter-apk\app-release.apk" "PipeCounterPro_Android.apk"
echo.
echo Saved copy as: D:\TRS\Pipe Counter\PipeCounterPro_Android.apk
echo.
pause
