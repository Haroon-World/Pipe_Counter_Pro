import unittest
import numpy as np
import cv2
import os

from pipe_counter_engine import (
    PipeCounterEngine,
    PipeDetection,
    DetectionSummary,
    optimal_1d_partition,
    analyze_size_distribution,
    split_thresholds_fixed_k,
    auto_confidence_threshold,
    is_duplicate_detection,
    is_nested_inside,
    nested_aware_dedupe,
    assign_nesting,
    find_nested_inner_circles,
    clamp_crop_rect,
    fit_circle_taubin,
    ransac_circle_fit,
    refine_pipe_rims,
    find_occluded_background_pipes,
)

class TestPipeCounterEngineV2(unittest.TestCase):
    def test_optimal_1d_partition_bimodal(self):
        # Two distinct clusters: small ~20px and large ~50px
        small = np.random.normal(loc=20.0, scale=1.5, size=40)
        large = np.random.normal(loc=50.0, scale=2.0, size=30)
        data = np.sort(np.concatenate([small, large]))
        
        bounds, sse = optimal_1d_partition(data, k=2, min_size=5)
        self.assertEqual(len(bounds), 1)
        # Split point should be close to index 40
        self.assertTrue(38 <= bounds[0] <= 42)

    def test_analyze_size_distribution(self):
        small = [19.0, 20.0, 21.0, 19.5, 20.5] * 8  # 40 items ~20
        large = [48.0, 50.0, 52.0, 49.0, 51.0] * 6  # 30 items ~50
        diameters = small + large
        
        res = analyze_size_distribution(diameters, max_k=3)
        self.assertEqual(res.k, 2)
        self.assertEqual(len(res.thresholds), 1)
        self.assertTrue(25.0 < res.thresholds[0] < 45.0)

    def test_auto_confidence_threshold(self):
        # High confidence cluster (clean pipes) + low confidence cluster (background noise)
        noise = np.random.uniform(0.10, 0.22, 15)
        pipes = np.random.uniform(0.65, 0.95, 80)
        confs = np.concatenate([noise, pipes])
        
        chosen = auto_confidence_threshold(confs)
        self.assertTrue(0.20 <= chosen <= 0.60)
        # The threshold should cleanly separate noise from pipes
        self.assertTrue(0.22 <= chosen <= 0.65)

    def test_is_duplicate_vs_nested(self):
        # Case A: duplicate detection (similar radius, nearby center)
        p1 = PipeDetection(id=1, cx=100.0, cy=100.0, width=40.0, height=40.0, angle=0.0, area=1256.0, solidity=1.0, confidence=0.9)
        p2 = PipeDetection(id=2, cx=102.0, cy=101.0, width=39.0, height=39.0, angle=0.0, area=1194.0, solidity=1.0, confidence=0.85)
        self.assertTrue(is_duplicate_detection(p1, p2))
        self.assertFalse(is_nested_inside(p2, p1))

        # Case B: nested concentric pipe (small pipe radius 12 inside big pipe radius 30)
        outer = PipeDetection(id=1, cx=200.0, cy=200.0, width=60.0, height=60.0, angle=0.0, area=2827.0, solidity=1.0, confidence=0.95)
        inner = PipeDetection(id=2, cx=202.0, cy=199.0, width=24.0, height=24.0, angle=0.0, area=452.0, solidity=1.0, confidence=0.90)
        self.assertFalse(is_duplicate_detection(outer, inner))
        self.assertTrue(is_nested_inside(inner, outer))

    def test_assign_nesting(self):
        outer = PipeDetection(id=1, cx=200.0, cy=200.0, width=60.0, height=60.0, angle=0.0, area=2827.0, solidity=1.0, confidence=0.95)
        inner = PipeDetection(id=2, cx=202.0, cy=199.0, width=24.0, height=24.0, angle=0.0, area=452.0, solidity=1.0, confidence=0.90)
        standalone = PipeDetection(id=3, cx=50.0, cy=50.0, width=25.0, height=25.0, angle=0.0, area=490.0, solidity=1.0, confidence=0.92)
        
        assign_nesting([outer, inner, standalone])
        self.assertEqual(inner.nested_in, 1)
        self.assertIsNone(outer.nested_in)
        self.assertIsNone(standalone.nested_in)

    def test_clamp_crop_rect(self):
        # Inside image bounds
        res = clamp_crop_rect(img_w=1000, img_h=800, rect=(100, 100, 200, 300), min_size=20)
        self.assertEqual(res, (100, 100, 200, 300))

        # Out-of-bounds clipping
        res2 = clamp_crop_rect(img_w=500, img_h=400, rect=(-20, 350, 200, 100), min_size=20)
        self.assertEqual(res2, (0, 350, 180, 50))

        # Too small
        res3 = clamp_crop_rect(img_w=500, img_h=400, rect=(10, 10, 10, 10), min_size=20)
        self.assertIsNone(res3)

    def test_synthetic_nested_circle_detection(self):
        # Create a synthetic image with an outer dark pipe and inner opening
        img = np.full((160, 160, 3), 180, dtype=np.uint8)
        # Outer ring: center 80,80, radius 50
        cv2.circle(img, (80, 80), 50, (30, 30, 30), thickness=4)
        # Inner ring: center 80,80, radius 22
        cv2.circle(img, (80, 80), 22, (20, 20, 20), thickness=4)

        outer_pipe = PipeDetection(id=1, cx=80.0, cy=80.0, width=100.0, height=100.0, angle=0.0, area=7854.0, solidity=1.0, confidence=0.95)
        inners = find_nested_inner_circles(img, [outer_pipe])
        self.assertGreaterEqual(len(inners), 1)
        inner = inners[0]
        self.assertAlmostEqual(inner.cx, 80.0, delta=4.0)
        self.assertAlmostEqual(inner.cy, 80.0, delta=4.0)
        self.assertAlmostEqual(inner.avg_radius, 22.0, delta=4.0)

    def test_fit_circle_taubin_clean(self):
        # Generate clean circle points
        theta = np.linspace(0, 2 * np.pi, 30, endpoint=False)
        pts = np.column_stack([50.0 + 15.0 * np.cos(theta), 70.0 + 15.0 * np.sin(theta)])
        res = fit_circle_taubin(pts)
        self.assertIsNotNone(res)
        xc, yc, r = res
        self.assertAlmostEqual(xc, 50.0, places=2)
        self.assertAlmostEqual(yc, 70.0, places=2)
        self.assertAlmostEqual(r, 15.0, places=2)

    def test_ransac_circle_fit_partial_arc(self):
        # Generate 120-degree partial arc (representing an occluded pipe)
        theta = np.linspace(-np.pi / 3, np.pi / 3, 35)
        xs = 100.0 + 20.0 * np.cos(theta)
        ys = 100.0 + 20.0 * np.sin(theta)
        pts = np.column_stack([xs, ys])

        res = ransac_circle_fit(pts, max_iterations=40, dist_threshold=1.5)
        self.assertIsNotNone(res)
        xc, yc, r, inliers, inlier_ratio, coverage = res
        self.assertAlmostEqual(xc, 100.0, delta=0.5)
        self.assertAlmostEqual(yc, 100.0, delta=0.5)
        self.assertAlmostEqual(r, 20.0, delta=0.5)
        self.assertTrue(0.25 <= coverage <= 0.45)

    def test_refine_and_occlusion_real_image(self):
        img_path = "assets/real_pipes_test.jpg"
        if os.path.exists(img_path):
            img = cv2.imread(img_path)
            res = PipeCounterEngine.detect(
                img, confidence_threshold=0.30, detect_nested=True, detect_occluded=True
            )
            self.assertGreater(res.total_count, 150)
            self.assertTrue(res.detect_occluded)
            # Should have found partially occluded pipes
            self.assertGreater(res.occluded_count, 0)
            self.assertGreater(res.total_count, res.occluded_count)

if __name__ == "__main__":
    unittest.main()
