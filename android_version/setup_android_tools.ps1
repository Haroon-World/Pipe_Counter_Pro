# setup_android_tools.ps1
# Automates lightweight setup of Java 17 and Android Command-Line Tools on Windows

$ErrorActionPreference = "Stop"

$baseDir = "D:\Android"
$downloadDir = "$baseDir\downloads"
$jdkDir = "$baseDir\jdk-17"
$sdkDir = "$baseDir\sdk"

New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
New-Item -ItemType Directory -Force -Path $jdkDir | Out-Null
New-Item -ItemType Directory -Force -Path "$sdkDir\cmdline-tools" | Out-Null

# ----------------- 1. Download & Extract Java 17 -----------------
$jdkZip = "$downloadDir\openjdk17.zip"
$jdkUrl = "https://aka.ms/download-jdk/microsoft-jdk-17.0.12-windows-x64.zip"

if (-not (Test-Path "$jdkDir\bin\java.exe")) {
    if (-not (Test-Path $jdkZip)) {
        Write-Host ">>> [1/4] Downloading Lightweight Java 17 (~180MB)..." -ForegroundColor Cyan
        curl.exe -L -o $jdkZip $jdkUrl --progress-bar
    }

    Write-Host ">>> Extracting Java 17..." -ForegroundColor Cyan
    Expand-Archive -Path $jdkZip -DestinationPath "$downloadDir\jdk_temp" -Force
    $innerDir = Get-ChildItem -Path "$downloadDir\jdk_temp" -Directory | Select-Object -First 1
    Copy-Item -Path "$($innerDir.FullName)\*" -Destination $jdkDir -Recurse -Force
    Remove-Item -Path "$downloadDir\jdk_temp" -Recurse -Force
}
Write-Host "[OK] Java 17 ready at: $jdkDir" -ForegroundColor Green

# ----------------- 2. Download & Extract Android Command-Line Tools -----------------
$cmdToolsZip = "$downloadDir\cmdline-tools.zip"
$cmdToolsUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
$latestDir = "$sdkDir\cmdline-tools\latest"

if (-not (Test-Path "$latestDir\bin\sdkmanager.bat")) {
    if (-not (Test-Path $cmdToolsZip)) {
        Write-Host ">>> [2/4] Downloading Android Command-Line Tools (~145MB)..." -ForegroundColor Cyan
        curl.exe -L -o $cmdToolsZip $cmdToolsUrl --progress-bar
    }

    Write-Host ">>> Extracting Android Command-Line Tools into cmdline-tools\latest..." -ForegroundColor Cyan
    Expand-Archive -Path $cmdToolsZip -DestinationPath "$downloadDir\cmd_temp" -Force
    New-Item -ItemType Directory -Force -Path $latestDir | Out-Null
    Copy-Item -Path "$downloadDir\cmd_temp\cmdline-tools\*" -Destination $latestDir -Recurse -Force
    Remove-Item -Path "$downloadDir\cmd_temp" -Recurse -Force
}
Write-Host "[OK] Android Command-Line Tools ready at: $latestDir" -ForegroundColor Green

# ----------------- 3. Set Environment Variables -----------------
$env:JAVA_HOME = $jdkDir
$env:ANDROID_HOME = $sdkDir
$env:ANDROID_SDK_ROOT = $sdkDir
$env:PATH = "$jdkDir\bin;$latestDir\bin;$sdkDir\platform-tools;$env:PATH"

[Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkDir, "User")
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdkDir, "User")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $sdkDir, "User")

Write-Host ">>> [3/4] Accepting Android SDK Licenses..." -ForegroundColor Cyan
cmd.exe /c "echo y | `"$latestDir\bin\sdkmanager.bat`" --licenses"

Write-Host ">>> [4/4] Installing minimal Android platform-tools and android-34..." -ForegroundColor Cyan
cmd.exe /c "`"$latestDir\bin\sdkmanager.bat`" `"platform-tools`" `"platforms;android-34`" `"build-tools;34.0.0`""

# ----------------- 4. Configure Flutter -----------------
Write-Host ">>> Configuring Flutter with Android SDK..." -ForegroundColor Cyan
& "D:\flutter\bin\flutter.bat" config --android-sdk $sdkDir

Write-Host ">>> Checking Flutter Doctor status..." -ForegroundColor Cyan
& "D:\flutter\bin\flutter.bat" doctor

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "[SUCCESS] Lightweight Android SDK and Java 17 are configured!" -ForegroundColor Green
Write-Host "You can now run: flutter build apk --release" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
