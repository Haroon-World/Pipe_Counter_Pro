# Pipe Counter Pro - Desktop v2.0.0 (Newer Version)

Industrial-grade AI Pipe Detection, Color-Coded Size Differentiation & Interactive Annotation desktop application.

### Features in v2.0.0:
* **Interactive Crop Tool (Crop ROI):** Select region-of-interest with handles and crop before or after scanning.
* **Intelligent Auto-Confidence:** Otsu and score gap distribution estimation for optimal pipe proposal extraction.
* **Dynamic 3-Tier Sizing:** Real-time clustering (Green Small, Yellow Medium, Red Large) with interactive split sliders.
* **Occlusion & Concentric Resolution:** Handles stacked, partially covered, and nested concentric pipes.
* **Obsidian Dark Theme:** High-contrast professional glass dark UI.

### Scripts:
* `run_desktop_app.bat` - Launch directly with Python without compiling.
* `build_desktop_installer.bat` - Compile with PyInstaller and generate the Windows Setup Installer (.exe) with Inno Setup.
* Output installer: `dist_installer\PipeCounterPro_v2.0.0_Setup.exe`
