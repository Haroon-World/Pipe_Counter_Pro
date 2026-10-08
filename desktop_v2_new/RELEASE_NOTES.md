# 🚀 Pipe Counter Pro v2.0.0 — Intelligent Multi-Scale Vision Suite

> **Next-Generation Industrial Pipe Detection, Sub-Pixel Arc Reconstruction & Multi-Tier Analytics**  
> Built for fabrication yards, shipping ports, warehouse inventories, and automated quality control.

---

## 🌟 What's New in Version 2.0.0

Pipe Counter Pro v2.0.0 represents a generational leap over classical Hough-circle and simple bounding-box detectors. By fusing a **pre-trained YOLOv8 deep learning backbone** with **analytical geometry (Taubin circle fitting & RANSAC curvature estimation)** and **Jenks-Fisher dynamic size clustering**, v2.0 solves the hardest real-world pipe yard challenges: stacked pipes, occluded back-row pipes, and concentric nested bundles.

---

## ⚡ Key Highlights & Core Capabilities

### 1. 🔬 Partial Arc Reconstruction for Stacked & Occluded Pipes (RANSAC + Taubin)
* **The Challenge:** In real-world bundles, back-row pipes are often $50\% - 70\%$ covered by front-row pipes, leaving only a partial crescent or arc visible.
* **The Breakthrough:** Integrates the algebraic **Taubin circle fitting algorithm** combined with **RANSAC outlier rejection** (`refine_pipe_rims` & `find_occluded_background_pipes`).
* **The Result:** Even when only $30\%$ of a pipe's rim is exposed, the algorithm recovers the full circular geometry with sub-pixel precision ($\le 0.5\text{ px}$ residual error).
* **Visual Indicator:** Occluded pipes are automatically highlighted with an elegant **violet/lavender outer halo** (`#c084fc`) so inspectors immediately see background items.

### 2. 🧠 Adaptive Auto-Calibration & Noise Filtering
* **Otsu Bimodal & Score Distribution Analysis:** Eliminates manual threshold guesswork. The engine scans the model confidence histogram, calculates optimal Otsu separations and inter-cluster gaps, and calibrates sensitivity dynamically.
* **Dual-Threshold Detection:** Retains full manual slider controls while offering one-click AI Auto-Sensitivity.

### 3. 🎯 Concentric & Nested Pipe Resolution
* **Nested Architecture:** Reliably identifies and counts multi-layer nested pipe assemblies (e.g. smaller pipes inserted inside larger outer casing pipes).
* **Scale-Aware Non-Maximum Suppression:** Prevents outer casings from masking inner conduits while keeping false positives suppressed.

### 4. 📏 1D Jenks-Fisher Size Partitioning & Live Dynamic Ruler
* Automatically clusters detected diameters into 3 standardized tiers:
  - 🟢 **Small / Standard Pipes** (Emerald Green `#22c55e`)
  - 🟡 **Medium Pipes** (Amber Gold `#eab308`)
  - 🔴 **Large / Heavy Pipes** (Crimson Coral `#ef4444`)
* **Interactive Threshold Ruler:** Desktop GUI and mobile canvas feature interactive drag sliders allowing inspectors to re-tier pipe classifications in real time without re-running inference.

### 5. ✂️ Interactive Region-of-Interest (ROI) Cropping
* Inspectors can draw an arbitrary rectangular crop around a specific rack, trailer bed, or bundle pallet.
* Detection immediately isolates the targeted area; crop coordinates and bundle surface area are captured directly into audit documentation.

### 6. 📊 Executive Multi-Tier Excel (.xlsx) Reports
* Generates audit-ready inspection reports with professional formatting:
  - Summary metrics: total count, estimated bundle diameter, density index, and processing latency.
  - Per-tier breakdown tables (counts, diameter statistics, mean variance).
  - Itemized coordinate manifests with individual confidence ratings and occlusion flags.

### 7. 🎨 Modern Glassmorphic & Obsidian Dark Mode
* Desktop interface built with **PyQt6** in a deep obsidian palette (`#0b0f19`) engineered for high contrast under harsh industrial lighting and field conditions.
* Real-time canvas with buttery smooth pan/zoom, manual addition, deletion, and tag toggle controls.

---

## 📦 Downloads & Installation

| Platform | Package | Description | Direct Download |
| :--- | :--- | :--- | :--- |
| 💻 **Windows** | `PipeCounterPro_v2.0.0_Setup.exe` | Complete Inno Setup installer. Bundles Python 3.12, PyTorch CPU/CUDA, PyQt6, and YOLOv8 weights. No external dependencies required. | [**Download Setup.exe**](https://github.com/Haroon-World/Pipe_Counter_Pro/releases/download/v2.0.0/PipeCounterPro_v2.0.0_Setup.exe) |
| 📱 **Android** | `PipeCounterPro_Android_v2.0.0.apk` | Standalone release APK compiled with Flutter & Android SDK 36. Supports Android 7.0 (API 24) through Android 15 (API 36). | [**Download Android APK**](https://github.com/Haroon-World/Pipe_Counter_Pro/releases/download/v2.0.0/PipeCounterPro_Android_v2.0.0.apk) |

---

### Windows Installation Steps
1. Download **`PipeCounterPro_v2.0.0_Setup.exe`**.
2. Run the installer wizard (requires no administrator rights; installs directly into your user app folder).
3. Check **"Create a desktop shortcut"** and click **Install**.
4. Launch **Pipe Counter Pro** from your Desktop or Start Menu.

### Android Installation Steps
1. Download **`PipeCounterPro_Android_v2.0.0.apk`** on your mobile device.
2. Tap the downloaded file to install (allow *"Install from unknown sources"* if prompted).
3. Open the app, grant camera/storage permissions, and start scanning pipe bundles instantly.

---

## 🛠️ Verification & Checksums

| File | Type | SHA-256 Checksum |
| :--- | :--- | :--- |
| `PipeCounterPro_Android_v2.0.0.apk` | Android APK | `4b1d7208bac84760bf5b07a1bdbb95dbd44605c03f61797149e63c2fb203c085` |
| `PipeCounterPro_v2.0.0_Setup.exe` | Windows Installer | *(Generated by CI runner)* |

---

## 📄 License & Compliance
Distributed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See [`LICENSE`](LICENSE) for complete legal details.
