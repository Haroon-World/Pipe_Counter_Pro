$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\Pipe Counter Pro v2.0.lnk")
$sc.TargetPath = "D:\TRS\Pipe Counter\run_desktop_app.bat"
$sc.WorkingDirectory = "D:\TRS\Pipe Counter"
$sc.IconLocation = "D:\TRS\Pipe Counter\assets\app_icon.ico, 0"
$sc.Description = "Pipe Counter Pro v2.0 - AI Pipe Detection & Size Differentiation"
$sc.Save()
Write-Output "Desktop shortcut created successfully!"
