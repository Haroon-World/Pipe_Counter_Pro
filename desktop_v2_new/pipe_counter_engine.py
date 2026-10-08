"""
Pipe Counter Pro - Core Computer Vision & Deep Learning Engine (v2.0.0)
Integrates:
1. Pre-Trained YOLOv8 Pipe Detection Model
2. Color-Coded Size Categories:
   - Green (#22c55e): Small / Standard
   - Yellow (#eab308): Medium
   - Red (#ef4444): Large
3. Preservation of Manual Pipe Color Selection
4. Interactive Selection, Manual Addition, & Direct Deletion
5. Professional Excel (.xlsx) Export with Color/Size Tiers

v2.0.0 Intelligent Detection additions:
6. Auto confidence threshold picked from the YOLO score distribution (Otsu + largest gap)
7. Robust 1D size clustering (optimal Jenks / Fisher partition on diameters, k = 1..3)
   with exposed split thresholds for live manual override
8. Nested / concentric pipe resolution (scale-aware dedupe + classical Hough fallback)
9. Crop / ROI metadata carried into the Excel export
"""

import os
import sys
import time
import math
from dataclasses import dataclass, field
from typing import List, Tuple, Optional, Dict, Any, Sequence
import cv2
import numpy as np
import pandas as pd

try:
    from ultralytics import YOLO
    HAS_YOLO = True
except ImportError:
    HAS_YOLO = False


ENGINE_VERSION = "2.0.0"

SIZE_COLORS = {
    "Green": {"hex": "#22c55e", "rgb": (34, 197, 94), "name": "Green (Small)"},
    "Yellow": {"hex": "#eab308", "rgb": (234, 179, 8), "name": "Yellow (Medium)"},
    "Red": {"hex": "#ef4444", "rgb": (239, 68, 68), "name": "Red (Large)"},
    "Small": {"hex": "#22c55e", "rgb": (34, 197, 94), "name": "Green (Small)"},
    "Medium": {"hex": "#eab308", "rgb": (234, 179, 8), "name": "Yellow (Medium)"},
    "Large": {"hex": "#ef4444", "rgb": (239, 68, 68), "name": "Red (Large)"},
    "Standard": {"hex": "#22c55e", "rgb": (34, 197, 94), "name": "Green (Standard)"},
}

# Category names used for k = 1, 2, 3 size tiers (sorted small -> large)
TIER_CATEGORIES = {
    1: ["Green"],
    2: ["Green", "Red"],
    3: ["Green", "Yellow", "Red"],
}

# Auto-confidence configuration
AUTO_CONF_PROBE = 0.10   # YOLO is run once at this low confidence in auto mode
AUTO_CONF_MIN = 0.20
AUTO_CONF_MAX = 0.60

# Nested-pipe configuration
NESTED_RATIO = 0.70          # radius ratio at/below which a small circle may be a nested pipe
DUP_CENTER_FRAC = 0.60       # same-size boxes closer than this * maxR are duplicates
NESTED_YOLO_IOU = 0.70       # YOLO NMS IoU used when nested detection is enabled


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
    nested_in: Optional[int] = None  # id of the outer pipe if this pipe sits inside another
    is_occluded: bool = False        # True if partially hidden by a foreground pipe (front/back stack)
    visibility_ratio: float = 1.0    # Estimated visible fraction of circular rim (0.20..1.0)
    occluded_by: Optional[int] = None # ID of the foreground pipe that occludes this one
    visible_arc_span: Optional[Tuple[float, float]] = None # (start_deg, end_deg) of visible crescent

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
    # ---- v2.0.0 fields ----
    split_thresholds: List[float] = field(default_factory=list)  # diameter cut points (px), ascending
    auto_detected_k: int = 1               # number of size tiers suggested by the 1D analysis
    active_k: int = 1                      # number of size tiers currently applied
    manual_split: bool = False             # True when split_thresholds came from the user slider
    confidence_used: float = 0.35          # final confidence threshold applied
    auto_confidence: bool = False          # True when confidence_used was picked automatically
    nested_detection: bool = False         # True when nested-aware detection was enabled
    detect_occluded: bool = False          # True when partial arc / occlusion reconstruction was enabled
    crop_rect: Optional[Tuple[int, int, int, int]] = None  # (x, y, w, h) in original image px
    original_width: Optional[int] = None
    original_height: Optional[int] = None

    @property
    def nested_count(self) -> int:
        return sum(1 for p in self.pipes if p.nested_in is not None)

    @property
    def occluded_count(self) -> int:
        return sum(1 for p in self.pipes if p.is_occluded)


@dataclass
class SizeSplitResult:
    k: int
    thresholds: List[float]
    means: List[float]
    counts: List[int]
    explained: float  # between-class variance ratio (eta^2) of the chosen partition


# =====================================================================
# Pure helper functions (unit-testable, no model required)
# =====================================================================

def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def otsu_threshold_1d(values: Sequence[float]) -> Tuple[float, float]:
    """
    Exact 1D Otsu on raw (sorted) values.
    Returns (threshold, eta) where eta = between-class variance / total variance (0..1).
    """
    x = np.sort(np.asarray(values, dtype=np.float64))
    n = len(x)
    if n < 2:
        return (float(x[0]) if n else 0.0), 0.0
    total_var = float(np.var(x))
    if total_var <= 1e-12:
        return float(x[0]), 0.0
    c = np.cumsum(x)
    i = np.arange(1, n)                 # split after index i-1 -> lower = x[:i]
    w0 = i / n
    w1 = 1.0 - w0
    m0 = c[i - 1] / i
    m1 = (c[-1] - c[i - 1]) / (n - i)
    between = w0 * w1 * (m0 - m1) ** 2
    best = int(np.argmax(between))
    s = best + 1
    thr = float((x[s - 1] + x[s]) / 2.0)
    return thr, float(between[best] / total_var)


def auto_confidence_threshold(
    confidences: Sequence[float],
    lo: float = AUTO_CONF_MIN,
    hi: float = AUTO_CONF_MAX,
    default: float = 0.35,
) -> float:
    """
    Picks a confidence threshold adaptively from the YOLO score distribution.

    1. Otsu on the confidence values separates low-score clutter from real pipes.
    2. If the distribution is not clearly bimodal (eta < 0.5) we stay conservative
       and never go above the default threshold.
    3. The threshold is snapped to the middle of the largest empty gap between
       sorted scores near the Otsu value (if that gap is significant).
    4. Result is clamped to [lo, hi].
    """
    c = np.sort(np.asarray([float(v) for v in confidences], dtype=np.float64))
    if len(c) < 4:
        return round(_clamp(default, lo, hi), 3)

    thr, eta = otsu_threshold_1d(c)
    if eta < 0.5:
        thr = min(thr, default)

    # Largest-gap refinement inside the allowed band
    in_band = c[(c >= lo - 0.05) & (c <= hi + 0.05)]
    if len(in_band) >= 2:
        gaps = np.diff(in_band)
        g_idx = int(np.argmax(gaps))
        gap = float(gaps[g_idx])
        mid = float((in_band[g_idx] + in_band[g_idx + 1]) / 2.0)
        if gap >= 0.08 and abs(mid - thr) <= 0.15:
            thr = mid

    return round(_clamp(thr, lo, hi), 3)


def _segment_sse(s1: np.ndarray, s2: np.ndarray, a, b):
    """Sum of squared errors of sorted x[a:b] using prefix sums (s1, s2 have a leading 0)."""
    cnt = b - a
    sm = s1[b] - s1[a]
    return (s2[b] - s2[a]) - (sm * sm) / np.maximum(cnt, 1)


def optimal_1d_partition(values: Sequence[float], k: int, min_size: int = 1) -> Tuple[List[int], float]:
    """
    Optimal (Jenks / Fisher natural breaks) partition of 1D values into k contiguous
    groups minimizing within-group SSE. Each group has at least `min_size` members.

    Returns (boundaries, sse) where boundaries are indices into the *sorted* array
    marking the start of groups 2..k. Returns ([], sse_total) if impossible.
    """
    x = np.sort(np.asarray(values, dtype=np.float64))
    n = len(x)
    s1 = np.concatenate([[0.0], np.cumsum(x)])
    s2 = np.concatenate([[0.0], np.cumsum(x * x)])
    total = float(_segment_sse(s1, s2, 0, n)) if n else 0.0
    min_size = max(1, int(min_size))

    if k <= 1 or n < k * min_size:
        return [], total

    if k == 2:
        b = np.arange(min_size, n - min_size + 1)
        cost = _segment_sse(s1, s2, 0, b) + _segment_sse(s1, s2, b, n)
        j = int(np.argmin(cost))
        return [int(b[j])], float(cost[j])

    if k == 3:
        best_cost = math.inf
        best = (0, 0)
        for b1 in range(min_size, n - 2 * min_size + 1):
            b2 = np.arange(b1 + min_size, n - min_size + 1)
            if len(b2) == 0:
                continue
            cost = (
                _segment_sse(s1, s2, 0, b1)
                + _segment_sse(s1, s2, b1, b2)
                + _segment_sse(s1, s2, b2, n)
            )
            j = int(np.argmin(cost))
            if cost[j] < best_cost:
                best_cost = float(cost[j])
                best = (b1, int(b2[j]))
        if best_cost is math.inf:
            return [], total
        return [best[0], best[1]], best_cost

    raise ValueError("optimal_1d_partition supports k <= 3")


def _partition_summary(x_sorted: np.ndarray, bounds: List[int]):
    edges = [0] + list(bounds) + [len(x_sorted)]
    means, counts = [], []
    for a, b in zip(edges[:-1], edges[1:]):
        seg = x_sorted[a:b]
        means.append(float(np.mean(seg)) if len(seg) else 0.0)
        counts.append(int(len(seg)))
    thresholds = [float((x_sorted[b - 1] + x_sorted[b]) / 2.0) for b in bounds]
    return means, counts, thresholds


def analyze_size_distribution(
    diameters: Sequence[float],
    max_k: int = 3,
    min_rel_gap: float = 0.18,
    min_cluster_frac: float = 0.05,
    min_cluster_abs: int = 2,
    min_explained_2: float = 0.78,
    min_explained_3: float = 0.90,
) -> SizeSplitResult:
    """
    Robust 1D analysis of pipe diameters choosing k in {1, 2, 3} size tiers.

    For each k the optimal natural-breaks partition is computed (pure numpy). A k > 1
    partition is accepted only if:
      * adjacent cluster means differ by >= `min_rel_gap` (relative to the smaller mean),
      * every cluster has >= `min_cluster_abs` pipes and either >= `min_cluster_frac`
        of all pipes, or is separated from its neighbour by a very large gap (2x min gap),
      * the between-class variance ratio eta^2 is high enough
        (>= `min_explained_2` for k=2, >= `min_explained_3` for k=3), and for k=3 the
        residual variance must at least halve compared to a valid k=2.
    """
    x = np.sort(np.asarray([float(d) for d in diameters if d is not None and d > 0], dtype=np.float64))
    n = len(x)
    one = SizeSplitResult(k=1, thresholds=[], means=[float(np.mean(x)) if n else 0.0], counts=[n], explained=0.0)
    if n < 2 * max(1, min_cluster_abs):
        return one

    sst = float(np.sum((x - np.mean(x)) ** 2))
    med = float(np.median(x))
    if sst <= 1e-9 or med <= 0 or (x[-1] - x[0]) / med < min_rel_gap:
        return one

    def evaluate(k: int):
        bounds, sse = optimal_1d_partition(x, k, min_size=min_cluster_abs)
        if not bounds:
            return None
        means, counts, thresholds = _partition_summary(x, bounds)
        rel_gaps = [
            (means[i + 1] - means[i]) / max(means[i], 1e-9) for i in range(len(means) - 1)
        ]
        if any(g < min_rel_gap for g in rel_gaps):
            return None
        for ci, cnt in enumerate(counts):
            if cnt < min_cluster_abs:
                return None
            if cnt < min_cluster_frac * n:
                neighbour_gaps = []
                if ci > 0:
                    neighbour_gaps.append(rel_gaps[ci - 1])
                if ci < len(rel_gaps):
                    neighbour_gaps.append(rel_gaps[ci])
                if min(neighbour_gaps) < 2.0 * min_rel_gap:
                    return None
        eta = 1.0 - sse / sst
        return SizeSplitResult(k=k, thresholds=thresholds, means=means, counts=counts, explained=float(eta))

    best = one
    r2 = evaluate(2) if max_k >= 2 else None
    if r2 is not None and r2.explained >= min_explained_2:
        best = r2

    if max_k >= 3 and n >= 3 * max(1, min_cluster_abs):
        r3 = evaluate(3)
        if r3 is not None and r3.explained >= min_explained_3:
            if best.k == 2:
                if (1.0 - r3.explained) <= 0.5 * (1.0 - best.explained):
                    best = r3
            else:
                best = r3
    return best


def split_thresholds_fixed_k(diameters: Sequence[float], k: int) -> List[float]:
    """Natural-breaks thresholds for a user-forced number of tiers (no validity checks)."""
    x = np.sort(np.asarray([float(d) for d in diameters if d > 0], dtype=np.float64))
    if k <= 1 or len(x) < k:
        return []
    bounds, _ = optimal_1d_partition(x, k, min_size=1)
    if not bounds:
        return []
    _, _, thresholds = _partition_summary(x, bounds)
    return thresholds


def tier_index(diameter: float, thresholds: Sequence[float]) -> int:
    """0-based tier for a diameter given ascending thresholds (upper tier if d > threshold)."""
    return int(sum(1 for t in thresholds if diameter > t))


def is_duplicate_detection(a: PipeDetection, b: PipeDetection,
                           dup_ratio: float = NESTED_RATIO,
                           center_frac: float = DUP_CENTER_FRAC) -> bool:
    """Two detections are duplicates only if similarly sized AND nearly concentric."""
    ra, rb = a.avg_radius, b.avg_radius
    max_r = max(ra, rb)
    min_r = min(ra, rb)
    if max_r <= 0:
        return False
    ratio = min_r / max_r
    dist = math.hypot(a.cx - b.cx, a.cy - b.cy)
    return ratio > dup_ratio and dist < center_frac * max_r


def is_nested_inside(inner: PipeDetection, outer: PipeDetection,
                     max_ratio: float = NESTED_RATIO, tolerance: float = 1.05) -> bool:
    """True if `inner` is significantly smaller than `outer` and lies inside it."""
    ri, ro = inner.avg_radius, outer.avg_radius
    if ro <= 0 or ri >= ro:
        return False
    if ri / ro > max_ratio:
        return False
    dist = math.hypot(inner.cx - outer.cx, inner.cy - outer.cy)
    return dist + ri <= ro * tolerance


def nested_aware_dedupe(pipes: List[PipeDetection],
                        dup_ratio: float = NESTED_RATIO,
                        center_frac: float = DUP_CENTER_FRAC) -> List[PipeDetection]:
    """
    Scale-aware NMS replacement. Keeps highest-confidence boxes, dropping a candidate
    only if it duplicates a kept box (radius ratio > dup_ratio and centers within
    center_frac * maxR). Small circles inside large ones are kept (nested pipes).
    Manual pipes are never dropped.
    """
    order = sorted(pipes, key=lambda p: (not p.is_manual, -p.confidence))
    kept: List[PipeDetection] = []
    for cand in order:
        if cand.is_manual:
            kept.append(cand)
            continue
        if any(is_duplicate_detection(cand, k, dup_ratio, center_frac) for k in kept):
            continue
        kept.append(cand)
    # Preserve original relative order for stable downstream sorting
    kept_ids = {id(p) for p in kept}
    return [p for p in pipes if id(p) in kept_ids]


def assign_nesting(pipes: List[PipeDetection], max_ratio: float = NESTED_RATIO) -> int:
    """
    Sets `nested_in` on every pipe lying inside a larger pipe (innermost container wins).
    Requires final ids. Returns the number of nested pipes.
    """
    count = 0
    for p in pipes:
        best: Optional[PipeDetection] = None
        for q in pipes:
            if q is p:
                continue
            if is_nested_inside(p, q, max_ratio=max_ratio):
                if best is None or q.avg_radius < best.avg_radius:
                    best = q
        p.nested_in = best.id if best is not None else None
        if best is not None:
            count += 1
    return count


def _ring_edge_support(edges: np.ndarray, cx: float, cy: float, r: float, samples: int = 72) -> float:
    """Fraction of points on a circle that land on (dilated) edge pixels."""
    h, w = edges.shape[:2]
    ang = np.linspace(0.0, 2.0 * np.pi, samples, endpoint=False)
    xs = np.round(cx + r * np.cos(ang)).astype(int)
    ys = np.round(cy + r * np.sin(ang)).astype(int)
    valid = (xs >= 0) & (xs < w) & (ys >= 0) & (ys < h)
    if not np.any(valid):
        return 0.0
    hits = edges[ys[valid], xs[valid]] > 0
    return float(np.sum(hits)) / float(samples)


def find_nested_inner_circles(
    image: np.ndarray,
    pipes: List[PipeDetection],
    min_outer_radius: float = 10.0,
    min_ratio: float = 0.25,
    max_ratio: float = 0.72,
    center_tol: float = 0.35,
    min_support: float = 0.55,
) -> List[PipeDetection]:
    """
    Classical fallback for nested pipes: for each detected pipe (radius R) look for a
    strong concentric circle with radius in [min_ratio*R, max_ratio*R] whose center lies
    within center_tol*R of the pipe center (cv2.HoughCircles, HOUGH_GRADIENT_ALT when
    available, verified by Canny edge support along the ring).
    Returns new PipeDetection objects (id=0) – caller assigns ids / nesting.
    """
    if image is None or not pipes:
        return []
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    img_h, img_w = gray.shape[:2]
    use_alt = hasattr(cv2, "HOUGH_GRADIENT_ALT")
    found: List[PipeDetection] = []

    for p in pipes:
        R = p.avg_radius
        if R < min_outer_radius:
            continue
        # Skip if an inner pipe is already known for this pipe
        if any(q is not p and is_nested_inside(q, p) for q in pipes):
            continue

        x0 = int(max(0, math.floor(p.cx - R)))
        y0 = int(max(0, math.floor(p.cy - R)))
        x1 = int(min(img_w, math.ceil(p.cx + R) + 1))
        y1 = int(min(img_h, math.ceil(p.cy + R) + 1))
        if x1 - x0 < 8 or y1 - y0 < 8:
            continue
        roi = gray[y0:y1, x0:x1]
        roi = cv2.GaussianBlur(roi, (5, 5), 1.2)

        min_r = max(3, int(math.floor(min_ratio * R)))
        max_r = max(min_r + 1, int(math.ceil(max_ratio * R)))
        try:
            circles = None
            if use_alt:
                circles = cv2.HoughCircles(
                    roi, cv2.HOUGH_GRADIENT_ALT, dp=1.5, minDist=max(4.0, R * 0.25),
                    param1=150, param2=0.70, minRadius=min_r, maxRadius=max_r,
                )
            if circles is None or len(circles) == 0:
                circles = cv2.HoughCircles(
                    roi, cv2.HOUGH_GRADIENT, dp=1.0, minDist=max(4.0, R * 0.25),
                    param1=100, param2=max(8, int(0.5 * min_r)),
                    minRadius=min_r, maxRadius=max_r,
                )
        except cv2.error:
            circles = None
        if circles is None or len(circles) == 0:
            continue

        med = float(np.median(roi))
        lo_t = int(max(10, 0.66 * med))
        hi_t = int(max(lo_t + 20, min(255, 1.33 * med)))
        edges = cv2.Canny(roi, lo_t, hi_t)
        edges = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)

        local_cx, local_cy = p.cx - x0, p.cy - y0
        best = None
        for c in np.asarray(circles).reshape(-1, 3):
            ccx, ccy, cr = float(c[0]), float(c[1]), float(c[2])
            if math.hypot(ccx - local_cx, ccy - local_cy) > center_tol * R:
                continue
            if not (min_ratio * R * 0.95 <= cr <= max_ratio * R * 1.02):
                continue
            support = _ring_edge_support(edges, ccx, ccy, cr)
            if support < min_support:
                continue
            if best is None or support > best[3]:
                best = (ccx, ccy, cr, support)
        if best is None:
            continue

        gcx, gcy, gr = best[0] + x0, best[1] + y0, best[2]
        d = 2.0 * gr
        inner = PipeDetection(
            id=0, cx=gcx, cy=gcy, width=d, height=d, angle=0.0,
            area=float(math.pi * gr * gr), solidity=round(best[3], 3), confidence=0.6,
            is_selected=True, is_manual=False, category="Green",
            ellipse=((gcx, gcy), (d, d), 0.0),
        )
        if any(is_duplicate_detection(inner, q) for q in pipes + found):
            continue
        found.append(inner)
    return found


def fit_circle_taubin(points: np.ndarray) -> Optional[Tuple[float, float, float]]:
    """
    Algebraic circle fitting using Taubin / Kåsa method on 2D points.
    points: (N, 2) array of (x, y) coordinates.
    Returns (xc, yc, r) or None if degenerate.
    """
    if points is None or len(points) < 3:
        return None
    x = points[:, 0].astype(np.float64)
    y = points[:, 1].astype(np.float64)
    n = len(x)

    mx = float(np.mean(x))
    my = float(np.mean(y))
    u = x - mx
    v = y - my
    z = u * u + v * v

    try:
        A = np.column_stack([u, v, np.ones(n)])
        p, residuals, rank, s = np.linalg.lstsq(A, z, rcond=None)
        uc = p[0] / 2.0
        vc = p[1] / 2.0
        r_sq = p[2] + uc * uc + vc * vc
        if r_sq <= 0:
            return None
        r = math.sqrt(r_sq)
        xc = uc + mx
        yc = vc + my
        return float(xc), float(yc), float(r)
    except Exception:
        return None


def ransac_circle_fit(
    points: np.ndarray,
    max_iterations: int = 40,
    dist_threshold: float = 1.5,
    min_inliers_fraction: float = 0.50,
) -> Optional[Tuple[float, float, float, np.ndarray, float, float]]:
    """
    Robust RANSAC circle fitting for noisy edge / partial arc points.
    Returns (xc, yc, r, inliers_mask, inlier_ratio, angular_coverage) or None.
    angular_coverage is fraction in [0..1] of the 360-degree perimeter spanned by inliers.
    """
    if points is None or len(points) < 6:
        return None

    best_inliers = None
    best_circle = None
    best_score = 0
    n = len(points)

    for _ in range(max_iterations):
        sample_idx = np.random.choice(n, 3, replace=False)
        pts_sample = points[sample_idx]
        res = fit_circle_taubin(pts_sample)
        if res is None:
            continue
        xc, yc, r = res
        if r <= 2.0 or r > 300.0:
            continue

        dists = np.abs(np.hypot(points[:, 0] - xc, points[:, 1] - yc) - r)
        inliers = dists <= dist_threshold
        inlier_count = int(np.sum(inliers))

        if inlier_count > best_score:
            best_score = inlier_count
            best_inliers = inliers
            best_circle = (xc, yc, r)

    if best_circle is None or best_score < 6:
        return None

    # Refit using all inliers
    inlier_pts = points[best_inliers]
    refit = fit_circle_taubin(inlier_pts)
    if refit is not None:
        xc, yc, r = refit
        dists = np.abs(np.hypot(points[:, 0] - xc, points[:, 1] - yc) - r)
        best_inliers = dists <= dist_threshold
        inlier_pts = points[best_inliers]

    if len(inlier_pts) < 6:
        return None

    # Compute angular coverage across 36 angular bins (10 deg each)
    angles = np.arctan2(inlier_pts[:, 1] - yc, inlier_pts[:, 0] - xc)
    bins = np.zeros(36, dtype=bool)
    deg_idx = np.floor((np.degrees(angles) % 360) / 10.0).astype(int)
    bins[np.clip(deg_idx, 0, 35)] = True
    angular_coverage = float(np.sum(bins)) / 36.0

    inlier_ratio = float(len(inlier_pts)) / float(n)
    return (float(xc), float(yc), float(r), best_inliers, inlier_ratio, angular_coverage)


def refine_pipe_rims(
    image: np.ndarray,
    pipes: List[PipeDetection],
    max_refine_dist: float = 4.5,
) -> Tuple[List[PipeDetection], int, int]:
    """
    Refines detected pipe positions and radii by fitting circular arcs to sub-pixel edges.
    Restores true circular diameter for pipes whose YOLO bounding box was squished due
    to partial occlusion (front/back stacking).
    Returns (refined_pipes, refined_count, occluded_count).
    """
    if image is None or not pipes:
        return pipes, 0, 0

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    h_img, w_img = gray.shape[:2]

    # Contrast enhancement for shadow-penetrating edge detection
    clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    blurred = cv2.bilateralFilter(enhanced, d=7, sigmaColor=35, sigmaSpace=7)
    med = float(np.median(blurred))
    lo_t = int(max(10, 0.66 * med))
    hi_t = int(max(lo_t + 20, min(255, 1.33 * med)))
    edges = cv2.Canny(blurred, lo_t, hi_t)

    refined_pipes: List[PipeDetection] = []
    refined_count = 0
    occluded_count = 0

    for p in pipes:
        if p.is_manual:
            refined_pipes.append(p)
            continue

        r_box = p.avg_radius
        pad = int(math.ceil(r_box * 0.40))
        x0 = max(0, int(math.floor(p.cx - r_box - pad)))
        y0 = max(0, int(math.floor(p.cy - r_box - pad)))
        x1 = min(w_img, int(math.ceil(p.cx + r_box + pad)))
        y1 = min(h_img, int(math.ceil(p.cy + r_box + pad)))

        if x1 - x0 < 8 or y1 - y0 < 8:
            refined_pipes.append(p)
            continue

        roi_edges = edges[y0:y1, x0:x1]
        local_cx = p.cx - x0
        local_cy = p.cy - y0

        y_pts, x_pts = np.where(roi_edges > 0)
        if len(x_pts) < 12:
            refined_pipes.append(p)
            continue

        dists = np.hypot(x_pts - local_cx, y_pts - local_cy)
        ring_mask = (dists >= r_box * 0.70) & (dists <= r_box * 1.30)
        candidate_pts = np.column_stack([x_pts[ring_mask], y_pts[ring_mask]])

        if len(candidate_pts) >= 12:
            fit = ransac_circle_fit(candidate_pts, max_iterations=40, dist_threshold=1.5)
            if fit is not None:
                fcx, fcy, fr, inliers, inlier_ratio, coverage = fit
                dist_shift = math.hypot(fcx - local_cx, fcy - local_cy)
                rad_change = abs(fr - r_box) / max(r_box, 1.0)

                if dist_shift <= max_refine_dist and rad_change <= 0.35 and fr >= 4.0:
                    global_cx = fcx + x0
                    global_cy = fcy + y0
                    p.cx = global_cx
                    p.cy = global_cy
                    p.width = fr * 2.0
                    p.height = fr * 2.0
                    p.area = float(math.pi * fr * fr)
                    p.ellipse = ((global_cx, global_cy), (fr * 2.0, fr * 2.0), 0.0)
                    refined_count += 1

                    if coverage < 0.68:
                        p.is_occluded = True
                        p.visibility_ratio = round(coverage, 2)
                        occluded_count += 1

        refined_pipes.append(p)

    return refined_pipes, refined_count, occluded_count


def find_occluded_background_pipes(
    image: np.ndarray,
    known_pipes: List[PipeDetection],
    min_arc_points: int = 14,
) -> List[PipeDetection]:
    """
    Discovers candidate pipes in the background (partially occluded by foreground pipes)
    using residual edge arcs not accounted for by foreground pipes.
    Returns new PipeDetection items (id=0).
    """
    if image is None or not known_pipes:
        return []

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    h_img, w_img = gray.shape[:2]

    diams = [p.diameter for p in known_pipes if p.is_selected]
    if not diams:
        return []
    median_r = float(np.median(diams)) / 2.0

    # Build mask of foreground pipe interiors
    known_mask = np.zeros((h_img, w_img), dtype=np.uint8)
    for p in known_pipes:
        cv2.circle(
            known_mask,
            (int(round(p.cx)), int(round(p.cy))),
            int(round(p.avg_radius * 0.85)),
            255,
            -1,
        )

    clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    blurred = cv2.bilateralFilter(enhanced, d=7, sigmaColor=35, sigmaSpace=7)
    med = float(np.median(blurred))
    edges = cv2.Canny(blurred, int(max(10, 0.66 * med)), int(max(30, 1.33 * med)))

    residual_edges = cv2.bitwise_and(edges, edges, mask=cv2.bitwise_not(known_mask))
    contours, _ = cv2.findContours(residual_edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)

    candidates: List[PipeDetection] = []
    for cnt in contours:
        pts = cnt.reshape(-1, 2)
        if len(pts) < min_arc_points:
            continue

        fit = ransac_circle_fit(pts, max_iterations=30, dist_threshold=1.5)
        if fit is None:
            continue
        xc, yc, r, inliers, inlier_ratio, coverage = fit

        # Must match expected pipe radius distribution
        if not (0.70 * median_r <= r <= 1.35 * median_r):
            continue

        # Must lie inside image bounds
        if not (r <= xc <= w_img - r and r <= yc <= h_img - r):
            continue

        # Must not duplicate an existing pipe center
        center_dist = min(math.hypot(xc - p.cx, yc - p.cy) for p in known_pipes)
        if center_dist < median_r * 0.82:
            continue

        # Must be occluded by at least one foreground pipe
        occluding_pipe = None
        for p in known_pipes:
            d = math.hypot(xc - p.cx, yc - p.cy)
            if d < r + p.avg_radius and d > abs(r - p.avg_radius) * 0.4:
                occluding_pipe = p
                break

        if occluding_pipe is not None and coverage >= 0.22:
            d = 2.0 * r
            cand = PipeDetection(
                id=0,
                cx=float(xc),
                cy=float(yc),
                width=d,
                height=d,
                angle=0.0,
                area=float(math.pi * r * r),
                solidity=round(inlier_ratio, 3),
                confidence=0.55,
                is_selected=True,
                is_manual=False,
                category="Green",
                ellipse=((float(xc), float(yc)), (d, d), 0.0),
                is_occluded=True,
                visibility_ratio=round(coverage, 2),
                occluded_by=occluding_pipe.id,
            )
            # Check against already found candidates
            if not any(is_duplicate_detection(cand, q, dup_ratio=0.85, center_frac=0.55) for q in candidates):
                candidates.append(cand)

    return candidates


def clamp_crop_rect(*args, min_size: int = 8, **kwargs) -> Optional[Tuple[int, int, int, int]]:
    """
    Normalizes a (possibly negative-size) rectangle to integer image bounds.
    Accepts:
      - clamp_crop_rect(x, y, w, h, img_w, img_h, min_size=8)
      - clamp_crop_rect(img_w, img_h, (x, y, w, h), min_size=8)
      - clamp_crop_rect((x, y, w, h), img_w, img_h, min_size=8)
      - clamp_crop_rect(img_w=..., img_h=..., rect=(x, y, w, h))
    """
    if len(args) == 6:
        x, y, w, h, img_w, img_h = args
    elif len(args) == 3:
        if isinstance(args[2], (tuple, list)):
            img_w, img_h, (x, y, w, h) = args
        elif isinstance(args[0], (tuple, list)):
            (x, y, w, h), img_w, img_h = args
        else:
            return None
    elif "rect" in kwargs:
        x, y, w, h = kwargs["rect"]
        img_w = kwargs.get("img_w", args[0] if len(args) > 0 else 0)
        img_h = kwargs.get("img_h", args[1] if len(args) > 1 else 0)
    else:
        return None

    x0, x1 = sorted((float(x), float(x) + float(w)))
    y0, y1 = sorted((float(y), float(y) + float(h)))
    x0 = int(max(0, math.floor(x0)))
    y0 = int(max(0, math.floor(y0)))
    x1 = int(min(img_w, math.ceil(x1)))
    y1 = int(min(img_h, math.ceil(y1)))
    if x1 - x0 < min_size or y1 - y0 < min_size:
        return None
    return (x0, y0, x1 - x0, y1 - y0)


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
    def classify_sizes_ex(
        cls,
        pipes: List[PipeDetection],
        num_sizes: int = 1,
        img_w: int = 1000,
        img_h: int = 1000,
        thresholds: Optional[Sequence[float]] = None,
    ) -> Tuple[Dict[str, SizeCategoryStats], int, List[float], int]:
        """
        Differentiates pipe sizes into Green, Yellow, and Red using 1D diameter analysis.
        Preserves user-chosen colors for manual pipes.

        num_sizes: 0 = Auto (k chosen by `analyze_size_distribution`), 1/2/3 = forced tiers.
        thresholds: optional manual split diameters (px) – overrides the computed ones.

        Returns (stats, active_k, split_thresholds, auto_detected_k).
        """
        if not pipes:
            return {}, 1, [], 1

        active_pipes = [p for p in pipes if p.is_selected]
        target_pipes = active_pipes if active_pipes else pipes

        # Separate AI-detected pipes from manual pipes (which keep their chosen color)
        ai_target_pipes = [p for p in target_pipes if not p.is_manual]
        diams = [p.diameter for p in ai_target_pipes]

        analysis = analyze_size_distribution(diams)
        auto_k = analysis.k

        if thresholds is not None and len(thresholds) > 0:
            split = sorted(float(t) for t in thresholds)[:2]
        elif num_sizes == 0:
            split = list(analysis.thresholds)
        elif num_sizes <= 1:
            split = []
        else:
            split = split_thresholds_fixed_k(diams, min(3, int(num_sizes)))

        active_k = len(split) + 1
        names = TIER_CATEGORIES[active_k]

        # Every AI pipe (including deselected ones) is recoloured by the thresholds
        for p in pipes:
            if p.is_manual:
                continue
            p.category = names[min(tier_index(p.diameter, split), active_k - 1)]

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

        return stats, active_k, split, auto_k

    @classmethod
    def classify_sizes(
        cls,
        pipes: List[PipeDetection],
        num_sizes: int = 1,
        img_w: int = 1000,
        img_h: int = 1000,
        thresholds: Optional[Sequence[float]] = None,
    ) -> Dict[str, SizeCategoryStats]:
        """Backward-compatible wrapper returning only the per-category statistics."""
        stats, _, _, _ = cls.classify_sizes_ex(pipes, num_sizes, img_w, img_h, thresholds)
        return stats

    @classmethod
    def detect(
        cls,
        image: np.ndarray,
        confidence_threshold: float = 0.35,
        iou_threshold: float = 0.45,
        num_sizes: int = 1,
        auto_confidence: bool = False,
        detect_nested: bool = False,
        detect_occluded: bool = True,
    ) -> DetectionSummary:
        """
        Executes pipe detection with initial size categorization.

        auto_confidence: run YOLO once at a low confidence and choose the threshold
                         from the score distribution (`auto_confidence_threshold`).
        detect_nested:   raise YOLO NMS IoU, apply nested-aware dedupe and the classical
                         Hough fallback for pipes sleeved inside larger pipes.
        detect_occluded: sub-pixel RANSAC arc curvature fitting to restore squished
                         diameters and discover partially occluded / stacked background pipes.
        """
        t0 = time.time()
        orig_h, orig_w = image.shape[:2]

        model = cls.get_yolo_model()
        pipes: List[PipeDetection] = []
        model_used = "YOLOv8-PipeCounter (Trained Deep Learning)"
        used_conf = float(confidence_threshold)

        if model is not None:
            yolo_conf = AUTO_CONF_PROBE if auto_confidence else float(confidence_threshold)
            yolo_iou = max(float(iou_threshold), NESTED_YOLO_IOU) if (detect_nested or detect_occluded) else float(iou_threshold)
            results = model.predict(
                image,
                conf=yolo_conf,
                iou=yolo_iou,
                max_det=3000,
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

            if auto_confidence:
                used_conf = auto_confidence_threshold([p.confidence for p in pipes])
                pipes = [p for p in pipes if p.confidence >= used_conf]

            if detect_nested:
                pipes = nested_aware_dedupe(pipes)
                pipes.extend(find_nested_inner_circles(image, pipes))

            # Arc curvature refinement & background pipe discovery
            if detect_occluded:
                pipes, _, _ = refine_pipe_rims(image, pipes)
                background_candidates = find_occluded_background_pipes(image, pipes)
                if background_candidates:
                    pipes.extend(background_candidates)
                pipes = nested_aware_dedupe(pipes)

        row_height = max(15, int(orig_h * 0.04))
        pipes.sort(key=lambda p: (round(p.cy / row_height), p.cx))

        for idx, p in enumerate(pipes, start=1):
            p.id = idx

        if detect_nested:
            assign_nesting(pipes)

        # Associate occluded pipes with their foreground occluding pipe
        if detect_occluded:
            for p in pipes:
                if p.is_occluded and p.occluded_by is None:
                    best_fg = None
                    best_dist = math.inf
                    for q in pipes:
                        if q is not p and not q.is_occluded:
                            d = math.hypot(p.cx - q.cx, p.cy - q.cy)
                            if d < p.avg_radius + q.avg_radius and d < best_dist:
                                best_dist = d
                                best_fg = q.id
                    p.occluded_by = best_fg

        stats, active_k, split, auto_k = cls.classify_sizes_ex(
            pipes, num_sizes=num_sizes, img_w=orig_w, img_h=orig_h
        )
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
            split_thresholds=split,
            auto_detected_k=auto_k,
            active_k=active_k,
            manual_split=False,
            confidence_used=used_conf,
            auto_confidence=bool(auto_confidence),
            nested_detection=bool(detect_nested),
            detect_occluded=bool(detect_occluded),
        )

    @classmethod
    def reclassify(
        cls,
        summary: DetectionSummary,
        num_sizes: int,
        thresholds: Optional[Sequence[float]] = None,
    ) -> DetectionSummary:
        """Instantly recalculates size & color categories in-memory with 0ms latency.
        Pass `thresholds` to apply a manual size split (slider override)."""
        stats, active_k, split, auto_k = cls.classify_sizes_ex(
            summary.pipes,
            num_sizes=num_sizes,
            img_w=summary.image_width,
            img_h=summary.image_height,
            thresholds=thresholds,
        )
        summary.num_sizes = num_sizes
        summary.size_stats = stats
        summary.split_thresholds = split
        summary.active_k = active_k
        summary.auto_detected_k = auto_k
        summary.manual_split = bool(thresholds)
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
            ["PIPE COUNTER PRO - INSPECTION REPORT", f"v{ENGINE_VERSION}"],
            ["Export Timestamp", timestamp],
            ["Source Image", source_image_name],
            ["Image Resolution", f"{summary.image_width} x {summary.image_height} px"],
        ]

        if summary.crop_rect:
            cx0, cy0, cw, ch = summary.crop_rect
            if summary.original_width and summary.original_height:
                summary_data.append(["Original Image Resolution", f"{summary.original_width} x {summary.original_height} px"])
            summary_data.extend([
                ["Crop Applied", "Yes"],
                ["Crop Origin (x, y)", f"{cx0}, {cy0} px"],
                ["Crop Size (w x h)", f"{cw} x {ch} px"],
            ])
        else:
            summary_data.append(["Crop Applied", "No (full image)"])

        summary_data.extend([
            ["Detection Model", summary.model_name],
            ["Processing Time", f"{summary.processing_time_ms:.1f} ms"],
            ["Confidence Threshold", f"{summary.confidence_used * 100:.0f}% ({'Auto' if summary.auto_confidence else 'Manual'})"],
            ["Nested Pipe Detection", f"{'On' if summary.nested_detection else 'Off'} ({summary.nested_count} nested pipes)"],
            ["Stacked / Occluded Pipes", f"{'On' if summary.detect_occluded else 'Off'} ({summary.occluded_count} partially occluded pipes with reconstructed Ø)"],
            ["Size Tiers", f"{summary.active_k} ({'Manual split' if summary.manual_split else ('Auto' if summary.num_sizes == 0 else 'Fixed')})"],
            ["Size Split Thresholds (Ø px)", ", ".join(f"{t:.1f}" for t in summary.split_thresholds) or "-"],
            ["Total Pipes Counted", summary.selected_count],
            ["Deselected Pipes", summary.deselected_count],
        ])

        for cat_name, stats in summary.size_stats.items():
            summary_data.append([f"Count - {stats.name}", f"{stats.count} pipes (Ø {stats.min_diam:.1f} - {stats.max_diam:.1f} px)"])

        df_summary = pd.DataFrame(summary_data, columns=["Metric", "Value"])

        ox, oy = (summary.crop_rect[0], summary.crop_rect[1]) if summary.crop_rect else (0, 0)
        pipe_records = []
        for p in summary.pipes:
            rec = {
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
                "Nested In (Pipe ID)": p.nested_in if p.nested_in is not None else "",
                "Stacked / Occluded": f"Yes (~{int(p.visibility_ratio * 100)}% visible)" if p.is_occluded else "No (Full Rim)",
                "Occluded By (Pipe ID)": p.occluded_by if p.occluded_by is not None else "",
            }
            if summary.crop_rect:
                rec["Center X (original px)"] = round(p.cx + ox, 2)
                rec["Center Y (original px)"] = round(p.cy + oy, 2)
            pipe_records.append(rec)
        df_pipes = pd.DataFrame(pipe_records)

        with pd.ExcelWriter(output_path, engine="openpyxl") as writer:
            df_summary.to_excel(writer, sheet_name="Summary", index=False)
            df_pipes.to_excel(writer, sheet_name="Pipe Details", index=False)

        return output_path
