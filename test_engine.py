import unittest
import os
import cv2
import pandas as pd
from pipe_counter_engine import PipeCounterEngine, DetectionSummary, PipeDetection

class TestPipeCounterEngine(unittest.TestCase):
    def setUp(self):
        self.img_path = "assets/real_pipes_test.jpg"
        self.assertTrue(os.path.exists(self.img_path), "Test pipe image must exist.")
        self.img = cv2.imread(self.img_path)
        self.assertIsNotNone(self.img, "Image must be readable by OpenCV.")

    def test_detection_and_colors(self):
        summary = PipeCounterEngine.detect(
            self.img, confidence_threshold=0.35, iou_threshold=0.45, num_sizes=1
        )
        self.assertIsInstance(summary, DetectionSummary)
        self.assertGreater(summary.total_count, 150)
        self.assertIn("Green", summary.size_stats)

    def test_manual_pipe_with_color_choice(self):
        summary = PipeCounterEngine.detect(
            self.img, confidence_threshold=0.35, iou_threshold=0.45, num_sizes=1
        )
        initial_count = summary.total_count

        # Add a Yellow pipe manually
        yellow_pipe = PipeDetection(
            id=initial_count + 1,
            cx=200.0,
            cy=200.0,
            width=23.0,
            height=23.0,
            area=415.0,
            is_selected=True,
            is_manual=True,
            category="Yellow",
        )
        summary.pipes.append(yellow_pipe)
        summary = PipeCounterEngine.reclassify(summary, num_sizes=1)

        self.assertEqual(summary.selected_count, initial_count + 1)
        self.assertIn("Yellow", summary.size_stats)
        self.assertEqual(summary.size_stats["Yellow"].count, 1)

    def test_direct_deletion(self):
        summary = PipeCounterEngine.detect(
            self.img, confidence_threshold=0.35, iou_threshold=0.45, num_sizes=1
        )
        initial_count = summary.total_count

        # Simulate deleting a pipe directly
        pipe_to_delete = summary.pipes[0]
        summary.pipes.remove(pipe_to_delete)
        summary = PipeCounterEngine.reclassify(summary, num_sizes=1)

        self.assertEqual(summary.total_count, initial_count - 1)
        self.assertEqual(summary.selected_count, initial_count - 1)

    def test_excel_export_with_colors(self):
        summary = PipeCounterEngine.detect(
            self.img, confidence_threshold=0.35, iou_threshold=0.45, num_sizes=1
        )
        out_path = "assets/test_output_report_colors.xlsx"
        res_path = PipeCounterEngine.export_to_excel(summary, "real_pipes_test.jpg", out_path)
        self.assertTrue(os.path.exists(res_path))

        with pd.ExcelFile(res_path) as xls:
            df_pipes = pd.read_excel(xls, sheet_name="Pipe Details")
            self.assertIn("Color / Size Tier", df_pipes.columns)
            self.assertEqual(len(df_pipes), summary.total_count)

if __name__ == "__main__":
    unittest.main()
