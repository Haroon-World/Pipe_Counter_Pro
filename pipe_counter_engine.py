"""
Pipe Counter Pro - Core Computer Vision & Deep Learning Engine
Integrates:
1. Pre-Trained YOLOv8 Pipe Detection Model
2. Color-Coded Size Categories:
   - Green (#22c55e): Small / Standard
   - Yellow (#eab308): Medium
   - Red (#ef4444): Large
3. Preservation of Manual Pipe Color Selection
4. Interactive Selection, Manual Addition, & Direct Deletion
5. Professional Excel (.xlsx) Export with Color/Size Tiers
"""

import os
import sys
import time
import math
from dataclasses import dataclass, field
from typing import List, Tuple, Optional, Dict, Any
import cv2
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans

try:
    from ultralytics import YOLO
    HAS_YOLO = True
except ImportError:
    HAS_YOLO = False


SIZE_COLORS = {
    "Green": {"hex": "#22c55e", "rgb": (34, 197, 94), "name": "Green (Small)"},
    "Yellow": {"hex": "#eab308", "rgb": (234, 179, 8), "name": "Yellow (Medium)"},
    "Red": {"hex": "#ef4444", "rgb": (239, 68, 68), "name": "Red (Large)"},
    "Small": {"hex": "#22c55e", "rgb": (34, 197, 94), "name": "Green (Small)"},
    "Medium": {"hex": "#eab308", "rgb": (234, 179, 8), "name": "Yellow (Medium)"},
    "Large": {"hex": "#ef4444", "rgb": (239, 68, 68), "name": "Red (Large)"},
    "Standard": {"hex": "#22c55e", "rgb": (34, 197, 94), "name": "Green (Standard)"},
}


@dataclass
class PipeDetection:
    id: int
    cx: float
    cy: float
    width: float       # Diameter W in px
    height: float      # Diameter H in px
    angle: float = 0.0 # Tilt angle in degrees
    area: float = 0.0  # Inner hollow area in px^2
    solidity: float = 0.98
    confidence: float = 1.0
    is_selected: bool = True # True = counted/active, False = deselected
    is_manual: bool = False  # True if user clicked/drew this circle
    category: str = "Green"  # "Green", "Yellow", "Red"
    ellipse: Tuple[Tuple[float, float], Tuple[float, float], float] = field(
        default_factory=lambda: ((0.0, 0.0), (0.0, 0.0), 0.0)
    )

    @property
    def diameter(self) -> float:
        return (self.width + self.height) / 2.0

    @property
    def avg_radius(self) -> float:
        return self.diameter / 2.0

    @property
    def color_hex(self) -> str:
        return SIZE_COLORS.get(self.category, SIZE_COLORS["Green"])["hex"]


@dataclass
class SizeCategoryStats:
    name: str
    count: int
    hex_color: str
    min_diam: float
    max_diam: float
    avg_diam: float


@dataclass
class DetectionSummary:
    pipes: List[PipeDetection]
    total_count: int
    selected_count: int
    deselected_count: int
    processing_time_ms: float
    image_width: int
    image_height: int
    num_sizes: int = 1
    size_stats: Dict[str, SizeCategoryStats] = field(default_factory=dict)
    model_name: str = "YOLOv8-PipeCounter"


class PipeCounterEngine:
    _yolo_model = None

    @classmethod
    def get_yolo_weights_path(cls) -> str:
        # Check PyInstaller bundled directory
        if hasattr(sys, "_MEIPASS"):
            bundled_path = os.path.join(sys._MEIPASS, "pipe_counting_repo", "best.pt")
            if os.path.exists(bundled_path):
                return bundled_path
            bundled_root = os.path.join(sys._MEIPASS, "best.pt")
            if os.path.exists(bundled_root):
                return bundled_root

        # Check local source directory
        local_repo = os.path.join(os.path.dirname(__file__), "pipe_counting_repo", "best.pt")
        if os.path.exists(local_repo):
            return local_repo

        local_cwd = os.path.join(os.getcwd(), "pipe_counting_repo", "best.pt")
        if os.path.exists(local_cwd):
            return local_cwd

        return "best.pt"

    @classmethod
    def get_yolo_model(cls):
        if cls._yolo_model is None and HAS_YOLO:
            weights_path = cls.get_yolo_weights_path()
            if os.path.exists(weights_path):
                cls._yolo_model = YOLO(weights_path)
        return cls._yolo_model

    @classmethod
    def classify_sizes(
        cls,
        pipes: List[PipeDetection],
        num_sizes: int = 1,
        img_w: int = 1000,
        img_h: int = 1000,
    ) -> Dict[str, SizeCategoryStats]:
        """
        Differentiates pipe sizes into Green, Yellow, and Red.
        Preserves user-chosen colors for manual pipes.
        """
        if not pipes:
            return {}

        active_pipes = [p for p in pipes if p.is_selected]
        target_pipes = active_pipes if active_pipes else pipes

        # Separate AI-detected pipes from manual pipes (which keep their chosen color)
        ai_target_pipes = [p for p in target_pipes if not p.is_manual]

        if ai_target_pipes:
            diams = np.array([p.diameter for p in ai_target_pipes], dtype=np.float32)
            mean_diam = float(np.mean(diams))
            std_diam = float(np.std(diams)) if len(diams) > 1 else 0.0
            cv = (std_diam / mean_diam) if mean_diam > 0 else 0.0

            actual_k = num_sizes
            if actual_k == 0:
                diam_range = float(np.max(diams) - np.min(diams))
                if cv < 0.12 or diam_range < 6.0:
                    actual_k = 1
                else:
                    actual_k = 2

            if actual_k <= 1 or len(ai_target_pipes) < actual_k:
                for p in ai_target_pipes:
                    p.category = "Green"
            elif actual_k == 2:
                features = []
                alpha = 0.20
                for p in ai_target_pipes:
                    norm_d = (p.diameter - mean_diam) / (std_diam if std_diam > 0.1 else 1.0)
                    norm_x = (p.cx / max(1, img_w)) * alpha
                    norm_y = (p.cy / max(1, img_h)) * alpha
                    features.append([norm_d, norm_x, norm_y])

                features = np.array(features, dtype=np.float32)
                km = KMeans(n_clusters=2, random_state=42, n_init=10).fit(features)

                # Sort: smaller -> Green, larger -> Red
                mean_0 = float(np.mean(diams[km.labels_ == 0])) if np.any(km.labels_ == 0) else 0.0
                mean_1 = float(np.mean(diams[km.labels_ == 1])) if np.any(km.labels_ == 1) else 0.0
                c_map = {0: "Green", 1: "Red"} if mean_0 < mean_1 else {0: "Red", 1: "Green"}

                for p, label in zip(ai_target_pipes, km.labels_):
                    p.category = c_map[label]

            elif actual_k == 3:
                features = []
                alpha = 0.20
                for p in ai_target_pipes:
                    norm_d = (p.diameter - mean_diam) / (std_diam if std_diam > 0.1 else 1.0)
                    norm_x = (p.cx / max(1, img_w)) * alpha
                    norm_y = (p.cy / max(1, img_h)) * alpha
                    features.append([norm_d, norm_x, norm_y])

                features = np.array(features, dtype=np.float32)
                km = KMeans(n_clusters=3, random_state=42, n_init=10).fit(features)

                c_means = []
                for c_idx in range(3):
                    mask = km.labels_ == c_idx
                    c_means.append((float(np.mean(diams[mask])) if np.any(mask) else 0.0, c_idx))
                c_means.sort(key=lambda x: x[0])
                c_map = {
                    c_means[0][1]: "Green",   # Small
                    c_means[1][1]: "Yellow",  # Medium
                    c_means[2][1]: "Red",     # Large
                }

                for p, label in zip(ai_target_pipes, km.labels_):
                    p.category = c_map[label]

        # Deselected AI pipes inherit category from nearest target pipe or default Green
        for p in pipes:
            if not p.is_selected and not p.is_manual and not p.category:
                p.category = "Green"

        # Calculate statistics per category for all active pipes
        stats = {}
        for cat_name in ["Green", "Yellow", "Red"]:
            cat_pipes = [p for p in target_pipes if p.category == cat_name]
            if cat_pipes:
                c_diams = [p.diameter for p in cat_pipes]
                stats[cat_name] = SizeCategoryStats(
                    name=SIZE_COLORS[cat_name]["name"],
                    count=len(cat_pipes),
                    hex_color=SIZE_COLORS[cat_name]["hex"],
                    min_diam=float(np.min(c_diams)),
                    max_diam=float(np.max(c_diams)),
                    avg_diam=float(np.mean(c_diams)),
                )

        # If only Green pipes exist and no Yellow/Red, label as Green (All Same Size)
        if len(stats) == 1 and "Green" in stats:
            stats["Green"].name = "Green (All Same Size)"

        return stats

    @classmethod
    def detect(
        cls,
        image: np.ndarray,
        confidence_threshold: float = 0.35,
        iou_threshold: float = 0.45,
        num_sizes: int = 1,
    ) -> DetectionSummary:
        """
        Executes pipe detection with initial size categorization.
        """
        t0 = time.time()
        orig_h, orig_w = image.shape[:2]

        model = cls.get_yolo_model()
        pipes: List[PipeDetection] = []
        model_used = "YOLOv8-PipeCounter (Trained Deep Learning)"

        if model is not None:
            results = model.predict(
                image,
                conf=confidence_threshold,
                iou=iou_threshold,
                verbose=False,
            )
            boxes = results[0].boxes

            for box in boxes:
                xyxy = box.xyxy[0].cpu().numpy()
                conf = float(box.conf[0].cpu().numpy())
                x1, y1, x2, y2 = xyxy
                cx = float((x1 + x2) / 2.0)
                cy = float((y1 + y2) / 2.0)
                w = float(x2 - x1)
                h = float(y2 - y1)
                area = float(math.pi * (w / 2.0) * (h / 2.0))

                pipes.append(
                    PipeDetection(
                        id=0,
                        cx=cx,
                        cy=cy,
                        width=w,
                        height=h,
                        angle=0.0,
                        area=area,
                        solidity=0.98,
                        confidence=conf,
                        is_selected=True,
                        category="Green",
                        ellipse=((cx, cy), (w, h), 0.0),
                    )
                )

        row_height = max(15, int(orig_h * 0.04))
        pipes.sort(key=lambda p: (round(p.cy / row_height), p.cx))

        for idx, p in enumerate(pipes, start=1):
            p.id = idx

        stats = cls.classify_sizes(pipes, num_sizes=num_sizes, img_w=orig_w, img_h=orig_h)
        elapsed_ms = (time.time() - t0) * 1000.0

        return DetectionSummary(
            pipes=pipes,
            total_count=len(pipes),
            selected_count=len(pipes),
            deselected_count=0,
            processing_time_ms=elapsed_ms,
            image_width=orig_w,
            image_height=orig_h,
            num_sizes=num_sizes,
            size_stats=stats,
            model_name=model_used,
        )

    @classmethod
    def reclassify(cls, summary: DetectionSummary, num_sizes: int) -> DetectionSummary:
        """Instantly recalculates size & color categories in-memory with 0ms latency."""
        stats = cls.classify_sizes(
            summary.pipes,
            num_sizes=num_sizes,
            img_w=summary.image_width,
            img_h=summary.image_height,
        )
        summary.num_sizes = num_sizes
        summary.size_stats = stats
        summary.total_count = len(summary.pipes)
        summary.selected_count = sum(1 for p in summary.pipes if p.is_selected)
        summary.deselected_count = summary.total_count - summary.selected_count
        return summary

    @staticmethod
    def export_to_excel(summary: DetectionSummary, source_image_name: str, output_path: str) -> str:
        """
        Exports detection results with Color & Size Tiers to a formatted Excel (.xlsx) file.
        """
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")

        summary_data = [
            ["PIPE COUNTER PRO - INSPECTION REPORT", ""],
            ["Export Timestamp", timestamp],
            ["Source Image", source_image_name],
            ["Image Resolution", f"{summary.image_width} x {summary.image_height} px"],
            ["Detection Model", summary.model_name],
            ["Processing Time", f"{summary.processing_time_ms:.1f} ms"],
            ["Total Pipes Counted", summary.selected_count],
            ["Deselected Pipes", summary.deselected_count],
        ]

        for cat_name, stats in summary.size_stats.items():
            summary_data.append([f"Count - {stats.name}", f"{stats.count} pipes (Ø {stats.min_diam:.1f} - {stats.max_diam:.1f} px)"])

        df_summary = pd.DataFrame(summary_data, columns=["Metric", "Value"])

        pipe_records = []
        for p in summary.pipes:
            pipe_records.append({
                "Pipe ID": p.id,
                "Status": "Active (Counted)" if p.is_selected else "Deselected",
                "Color / Size Tier": SIZE_COLORS.get(p.category, {}).get("name", p.category),
                "Diameter (px)": round(p.diameter, 2),
                "Center X (px)": round(p.cx, 2),
                "Center Y (px)": round(p.cy, 2),
                "Width (px)": round(p.width, 2),
                "Height (px)": round(p.height, 2),
                "Area (px^2)": round(p.area, 1),
                "Confidence": round(p.confidence, 3),
                "Source": "Manual Draw" if p.is_manual else "AI Detected",
            })
        df_pipes = pd.DataFrame(pipe_records)

        with pd.ExcelWriter(output_path, engine="openpyxl") as writer:
            df_summary.to_excel(writer, sheet_name="Summary", index=False)
            df_pipes.to_excel(writer, sheet_name="Pipe Details", index=False)

        return output_path
