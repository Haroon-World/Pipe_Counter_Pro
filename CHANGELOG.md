# Changelog

All notable changes to the Pipe Counter Pro project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.0.0] - In Progress (Upcoming)

### Added
- **Concentric & Nested Pipe Detection**: Ability to detect and differentiate smaller pipes inserted inside larger outer pipes/sleeves.
- **Auto Pipe Radius Calibration**: Adaptive scale-space/distance transform analysis to automatically detect pipe radius bounds from the image, preserving full manual slider adjustments.
- **Auto Edge Sensitivity**: Image contrast and gradient SNR noise floor analysis for automated edge sensitivity tuning, with manual slider override.
- **Auto Multi-Size Discovery & Live Split Ruler Snapping**: Automatic bimodal/trimodal clustering of pipe diameters that automatically snaps the Size Split Ruler to the optimal mathematical valley.
- **Interactive Image Cropping & ROI Tool**: 8-point interactive cropping viewport to cut out unwanted warehouse/yard background before or during pipe counting.

---

## [1.0.0] - 2026-09-04

### Added
- Dual-engine architecture:
  - Desktop: PyQt6 GUI with pre-trained YOLOv8 deep learning model (`best.pt`).
  - Multiplatform: Flutter mobile & desktop app with 100% offline Classical CV pipeline (Sobel gradients, Hough Circle Transform, radial ray profiler, ellipse fitting).
- Interactive Canvas tools: Pan & Zoom, Add Pipe, Delete Pipe, Toggle Selection.
- 3-tier color coding: 🟢 Small (Green), 🟡 Medium (Yellow), 🔴 Large (Red).
- Manual Size Split Slider for live recoloring.
- Excel (.xlsx) and CSV export with full pipe geometry and inventory summary.
- Background isolate processing with real-time percentage animation.
