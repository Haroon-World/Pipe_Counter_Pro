"""
Pipe Counter Pro - Desktop GUI Application (PyQt6)
Industrial-grade AI Pipe Detection, Color-Coded Size Differentiation & Interactive Annotation.

Responsive Architecture & Navbar Features:
1. Modern Responsive Glass-Dark Navbar:
   - Left: Image file chip with icon & resolution.
   - Center: Segmented tool pill with [Add Pipe], [🟢, 🟡, 🔴 Color Chips], [Delete Pipe], and [Pan Mode].
   - Right: Sleek Zoom & Fit View pill ([🔍−], [🔍+], [⛶ Fit]).
2. Fully Responsive Layout:
   - Dynamic window sizing matching screen resolution (never overflows on laptops or scaled displays).
   - Minimum window size enforced (900x600) with collapsible-safe QSplitter.
   - Left control panel wrapped in smooth QScrollArea (never squishes cards or text).
   - Auto-responsive canvas: Keeps image perfectly fitted on window resize.
3. Interactive Annotation & Color Sizing:
   - Choice of colors: 🟢 Green (Small), 🟡 Yellow (Medium), 🔴 Red (Large).
   - Clicking drops a circle matching the EXACT diameter of existing circles of that color.
   - Clicking over any circle deletes it instantly.
   - Arrow keys / WASD smooth panning, mouse wheel scrolling.
"""

import os
import sys
import math
from typing import Optional, List

import cv2
import numpy as np
from PyQt6.QtCore import Qt, QThread, pyqtSignal, QPointF, QRectF, QEvent
from PyQt6.QtGui import (
    QImage,
    QPixmap,
    QPainter,
    QPainterPath,
    QPen,
    QBrush,
    QColor,
    QFont,
    QIcon,
    QWheelEvent,
    QMouseEvent,
    QKeyEvent,
    QAction,
    QResizeEvent,
)
from PyQt6.QtWidgets import (
    QApplication,
    QMainWindow,
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QGridLayout,
    QLabel,
    QPushButton,
    QSlider,
    QFileDialog,
    QMessageBox,
    QProgressBar,
    QFrame,
    QSplitter,
    QScrollArea,
    QGraphicsView,
    QGraphicsScene,
    QGraphicsPixmapItem,
    QGraphicsItem,
    QGroupBox,
    QComboBox,
    QMenu,
    QButtonGroup,
    QRadioButton,
    QSizePolicy,
)

from pipe_counter_engine import (
    PipeCounterEngine,
    DetectionSummary,
    PipeDetection,
    SIZE_COLORS,
)


class DetectionWorker(QThread):
    finished = pyqtSignal(object)
    error = pyqtSignal(str)

    def __init__(self, image: np.ndarray, confidence: float, iou: float, num_sizes: int):
        super().__init__()
        self.image = image
        self.confidence = confidence
        self.iou = iou
        self.num_sizes = num_sizes

    def run(self):
        try:
            summary = PipeCounterEngine.detect(
                self.image,
                confidence_threshold=self.confidence,
                iou_threshold=self.iou,
                num_sizes=self.num_sizes,
            )
            self.finished.emit(summary)
        except Exception as e:
            self.error.emit(str(e))


class PipeGraphicsItem(QGraphicsItem):
    """
    Interactive circle overlay for a pipe opening.
    Color-coded: Green, Yellow, Red.
    Supports click-to-delete, drag, and right-click context menu.
    """
    def __init__(self, pipe: PipeDetection, on_click_cb, on_delete_cb, on_recolor_cb):
        super().__init__()
        self.pipe = pipe
        self.on_click_cb = on_click_cb
        self.on_delete_cb = on_delete_cb
        self.on_recolor_cb = on_recolor_cb
        self.setPos(pipe.cx, pipe.cy)
        self.setRotation(pipe.angle)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setAcceptHoverEvents(True)
        self.is_hovered = False
        self._press_pos: Optional[QPointF] = None
        self.update_tooltip()

    def update_tooltip(self):
        status_str = "Active (Counted)" if self.pipe.is_selected else "Deselected (Excluded)"
        src_str = "Manual" if self.pipe.is_manual else "AI"
        color_name = SIZE_COLORS.get(self.pipe.category, {}).get("name", self.pipe.category)
        self.setToolTip(
            f"Pipe #{self.pipe.id} ({src_str})\n"
            f"Color/Size: {color_name}\n"
            f"Diameter: {self.pipe.diameter:.1f} px\n"
            f"Center: ({self.pipe.cx:.1f}, {self.pipe.cy:.1f})\n"
            f"Status: {status_str}\n"
            f"👉 Left-Click: Action\n"
            f"👉 Right-Click: Color / Delete Menu"
        )

    def boundingRect(self) -> QRectF:
        w = max(6.0, self.pipe.width)
        h = max(6.0, self.pipe.height)
        pad = 8.0
        return QRectF(-w / 2.0 - pad, -h / 2.0 - pad, w + pad * 2, h + pad * 2)

    def shape(self) -> QPainterPath:
        path = QPainterPath()
        w = max(6.0, self.pipe.width)
        h = max(6.0, self.pipe.height)
        path.addEllipse(-w / 2.0, -h / 2.0, w, h)
        return path

    def paint(self, painter: QPainter, option, widget=None):
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        w = max(6.0, self.pipe.width)
        h = max(6.0, self.pipe.height)

        color_info = SIZE_COLORS.get(self.pipe.category, SIZE_COLORS["Green"])
        base_color = QColor(color_info["hex"])

        if self.pipe.is_selected:
            if self.is_hovered:
                pen = QPen(QColor(56, 189, 248), 2.8)  # Cyan glow on hover
                dot_color = QColor(56, 189, 248)
            else:
                pen = QPen(base_color, 2.2)
                dot_color = base_color

            pen.setCosmetic(True)
            painter.setPen(pen)
            painter.setBrush(Qt.BrushStyle.NoBrush)
            painter.drawEllipse(QPointF(0, 0), w / 2.0, h / 2.0)

            # Center dot
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(QBrush(dot_color))
            painter.drawEllipse(QPointF(0, 0), 2.5, 2.5)
        else:
            # Deselected state
            pen = QPen(QColor(148, 163, 184, 130), 1.5, Qt.PenStyle.DashLine)
            pen.setCosmetic(True)
            painter.setPen(pen)
            painter.setBrush(Qt.BrushStyle.NoBrush)
            painter.drawEllipse(QPointF(0, 0), w / 2.0, h / 2.0)

            painter.setPen(QPen(QColor(239, 68, 68, 160), 1.5))
            painter.drawLine(QPointF(-2, -2), QPointF(2, 2))
            painter.drawLine(QPointF(-2, 2), QPointF(2, -2))

    def hoverEnterEvent(self, event):
        self.is_hovered = True
        self.update()
        super().hoverEnterEvent(event)

    def hoverLeaveEvent(self, event):
        self.is_hovered = False
        self.update()
        super().hoverLeaveEvent(event)

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self._press_pos = event.pos()
            event.accept()
        elif event.button() == Qt.MouseButton.RightButton:
            event.accept()
        else:
            super().mousePressEvent(event)

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton and self._press_pos is not None:
            dist = (event.pos() - self._press_pos).manhattanLength()
            if dist < 5.0:
                self.on_click_cb(self)
                event.accept()
                return
        elif event.button() == Qt.MouseButton.RightButton:
            self.show_context_menu(event.screenPos())
            event.accept()
            return
        super().mouseReleaseEvent(event)

    def show_context_menu(self, screen_pos):
        menu = QMenu()
        menu.setStyleSheet("background-color: #1e293b; color: #f8fafc; font-size: 11px;")

        color_menu = menu.addMenu("🎨 Change Color")
        color_menu.setStyleSheet("background-color: #1e293b; color: #f8fafc;")

        act_green = QAction("🟢 Green (Small)", color_menu)
        act_green.triggered.connect(lambda: self.on_recolor_cb(self, "Green"))
        color_menu.addAction(act_green)

        act_yellow = QAction("🟡 Yellow (Medium)", color_menu)
        act_yellow.triggered.connect(lambda: self.on_recolor_cb(self, "Yellow"))
        color_menu.addAction(act_yellow)

        act_red = QAction("🔴 Red (Large)", color_menu)
        act_red.triggered.connect(lambda: self.on_recolor_cb(self, "Red"))
        color_menu.addAction(act_red)

        menu.addSeparator()

        act_toggle = QAction("Toggle Active / Excluded", menu)
        act_toggle.triggered.connect(self.toggle_selection)
        menu.addAction(act_toggle)

        act_delete = QAction("🗑️ Delete This Circle", menu)
        act_delete.triggered.connect(lambda: self.on_delete_cb(self))
        menu.addAction(act_delete)

        menu.exec(screen_pos)

    def toggle_selection(self):
        self.pipe.is_selected = not self.pipe.is_selected
        self.update_tooltip()
        self.update()


class InteractiveGraphicsView(QGraphicsView):
    """
    Responsive Graphics View with auto-centering on resize,
    smooth scrolling, and interactive drawing.
    """
    pipe_drawn = pyqtSignal(float, float, float)
    mode_changed = pyqtSignal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.SmoothPixmapTransform)
        self.setTransformationAnchor(QGraphicsView.ViewportAnchor.AnchorUnderMouse)
        self.setResizeAnchor(QGraphicsView.ViewportAnchor.AnchorUnderMouse)

        self.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.setBackgroundBrush(QBrush(QColor(15, 23, 42)))
        self.setFrameShape(QFrame.Shape.NoFrame)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

        self._tool_mode = "draw"
        self._zoom_level = 1.0
        self._auto_fit_on_resize = True

        self._press_pos_view: Optional[QPointF] = None
        self._press_pos_scene: Optional[QPointF] = None
        self._preview_item = None
        self._is_dragging_to_pan = False
        self._is_drawing_circle = False

    def resizeEvent(self, event: QResizeEvent):
        super().resizeEvent(event)
        # Keep image auto-fitted if user has not manually zoomed
        if self._auto_fit_on_resize and self.scene() and self.scene().sceneRect().isValid():
            self.fitInView(self.scene().sceneRect(), Qt.AspectRatioMode.KeepAspectRatio)

    def pan_by(self, dx: int, dy: int):
        h_bar = self.horizontalScrollBar()
        v_bar = self.verticalScrollBar()
        h_bar.setValue(h_bar.value() + dx)
        v_bar.setValue(v_bar.value() + dy)

    def keyPressEvent(self, event: QKeyEvent):
        step = 120 if (event.modifiers() & Qt.KeyboardModifier.ShiftModifier) else 50

        if event.key() in (Qt.Key.Key_Up, Qt.Key.Key_W):
            self.pan_by(0, -step)
            event.accept()
        elif event.key() in (Qt.Key.Key_Down, Qt.Key.Key_S):
            self.pan_by(0, step)
            event.accept()
        elif event.key() in (Qt.Key.Key_Left, Qt.Key.Key_A):
            self.pan_by(-step, 0)
            event.accept()
        elif event.key() in (Qt.Key.Key_Right, Qt.Key.Key_D):
            self.pan_by(step, 0)
            event.accept()
        elif event.key() in (Qt.Key.Key_Plus, Qt.Key.Key_Equal):
            self.zoom_in()
            event.accept()
        elif event.key() in (Qt.Key.Key_Minus, Qt.Key.Key_Underscore):
            self.zoom_out()
            event.accept()
        elif event.key() in (Qt.Key.Key_0, Qt.Key.Key_F):
            if self.scene() and self.scene().sceneRect().isValid():
                self.reset_view(self.scene().sceneRect())
            event.accept()
        else:
            super().keyPressEvent(event)

    def zoom_in(self):
        self._auto_fit_on_resize = False
        self.scale(1.2, 1.2)
        self._zoom_level *= 1.2

    def zoom_out(self):
        self._auto_fit_on_resize = False
        self.scale(1.0 / 1.2, 1.0 / 1.2)
        self._zoom_level /= 1.2

    def wheelEvent(self, event: QWheelEvent):
        if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            self._auto_fit_on_resize = False
            factor = 1.15 if event.angleDelta().y() > 0 else 1.0 / 1.15
            new_zoom = self._zoom_level * factor
            if 0.05 <= new_zoom <= 40.0:
                self._zoom_level = new_zoom
                self.scale(factor, factor)
            event.accept()
        elif event.modifiers() & Qt.KeyboardModifier.ShiftModifier:
            delta = event.angleDelta().y() or event.angleDelta().x()
            self.pan_by(int(-delta * 0.8), 0)
            event.accept()
        else:
            delta = event.angleDelta().y()
            self.pan_by(0, int(-delta * 0.8))
            event.accept()

    def set_tool_mode(self, mode: str):
        self._tool_mode = mode
        if mode == "pan":
            self.setDragMode(QGraphicsView.DragMode.ScrollHandDrag)
            self.viewport().setCursor(Qt.CursorShape.OpenHandCursor)
        elif mode == "delete":
            self.setDragMode(QGraphicsView.DragMode.NoDrag)
            self.viewport().setCursor(Qt.CursorShape.PointingHandCursor)
        else:
            self.setDragMode(QGraphicsView.DragMode.NoDrag)
            self.viewport().setCursor(Qt.CursorShape.CrossCursor)
        self.mode_changed.emit(self._tool_mode)

    def mousePressEvent(self, event: QMouseEvent):
        self.setFocus()
        item = self.itemAt(event.pos())
        is_pipe_item = isinstance(item, PipeGraphicsItem)

        if event.button() == Qt.MouseButton.LeftButton:
            self._press_pos_view = event.position()
            self._press_pos_scene = self.mapToScene(event.pos())

            if is_pipe_item:
                super().mousePressEvent(event)
                return

            if self._tool_mode == "pan":
                self._is_dragging_to_pan = True
                self.viewport().setCursor(Qt.CursorShape.ClosedHandCursor)
                event.accept()
                return

            if self._tool_mode == "draw":
                self._is_drawing_circle = True
                event.accept()
                return

        elif event.button() in (Qt.MouseButton.MiddleButton, Qt.MouseButton.RightButton) and not is_pipe_item:
            self._is_dragging_to_pan = True
            self._press_pos_view = event.position()
            self.viewport().setCursor(Qt.CursorShape.ClosedHandCursor)
            event.accept()
            return

        super().mousePressEvent(event)

    def mouseMoveEvent(self, event: QMouseEvent):
        if self._is_dragging_to_pan and self._press_pos_view is not None:
            delta = event.position() - self._press_pos_view
            self._press_pos_view = event.position()
            self.pan_by(int(-delta.x()), int(-delta.y()))
            event.accept()
            return

        if self._is_drawing_circle and self._press_pos_scene is not None:
            curr_scene = self.mapToScene(event.pos())
            dx = curr_scene.x() - self._press_pos_scene.x()
            dy = curr_scene.y() - self._press_pos_scene.y()
            radius = math.hypot(dx, dy)

            if self._preview_item is not None:
                self.scene().removeItem(self._preview_item)

            cx = self._press_pos_scene.x()
            cy = self._press_pos_scene.y()
            pen = QPen(QColor(56, 189, 248), 2.2, Qt.PenStyle.DashLine)
            pen.setCosmetic(True)
            self._preview_item = self.scene().addEllipse(
                cx - radius, cy - radius, radius * 2, radius * 2, pen
            )
            event.accept()
            return

        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event: QMouseEvent):
        if self._is_dragging_to_pan:
            self._is_dragging_to_pan = False
            self.set_tool_mode(self._tool_mode)
            event.accept()
            return

        if self._is_drawing_circle and self._press_pos_scene is not None:
            self._is_drawing_circle = False
            curr_scene = self.mapToScene(event.pos())
            dx = curr_scene.x() - self._press_pos_scene.x()
            dy = curr_scene.y() - self._press_pos_scene.y()
            radius = math.hypot(dx, dy)

            if self._preview_item is not None:
                self.scene().removeItem(self._preview_item)
                self._preview_item = None

            cx = self._press_pos_scene.x()
            cy = self._press_pos_scene.y()
            final_radius = radius if radius >= 4.0 else 0.0
            self.pipe_drawn.emit(cx, cy, final_radius)
            event.accept()
            return

        super().mouseReleaseEvent(event)

    def reset_view(self, scene_rect: QRectF):
        self._auto_fit_on_resize = True
        self.fitInView(scene_rect, Qt.AspectRatioMode.KeepAspectRatio)
        self._zoom_level = 1.0


def get_app_icon_path() -> str:
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    for name in ["app_icon.ico", "logo.png", "app_icon.png"]:
        p = os.path.join(base, "assets", name)
        if os.path.exists(p):
            return p
    return ""


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Pipe Counter Pro — AI Pipe Detection & Intelligent Size Differentiation")
        icon_path = get_app_icon_path()
        if icon_path:
            self.setWindowIcon(QIcon(icon_path))

        # Responsive default window sizing matching monitor dimensions
        screen = QApplication.primaryScreen()
        if screen:
            avail = screen.availableGeometry()
            w = min(1400, max(960, int(avail.width() * 0.94)))
            h = min(920, max(640, int(avail.height() * 0.92)))
            self.resize(w, h)
        else:
            self.resize(1360, 880)

        self.setMinimumSize(940, 620)

        self.cv_image: Optional[np.ndarray] = None
        self.source_image_name: str = "sample_pipes.jpg"
        self.summary: Optional[DetectionSummary] = None
        self.worker: Optional[DetectionWorker] = None

        self.scene = QGraphicsScene(self)
        self.pixmap_item: Optional[QGraphicsPixmapItem] = None
        self.pipe_items: List[PipeGraphicsItem] = []

        self.current_draw_color = "Green"
        self.click_behavior = "delete"

        self.init_ui()
        self.apply_dark_theme()

        QApplication.instance().installEventFilter(self)

        base_dir = getattr(sys, "_MEIPASS", os.getcwd())
        default_path = os.path.join(base_dir, "assets", "real_pipes_test.jpg")
        if not os.path.exists(default_path):
            default_path = os.path.join(os.getcwd(), "assets", "real_pipes_test.jpg")
        if os.path.exists(default_path):
            self.load_image(default_path)

    def eventFilter(self, obj, event):
        if event.type() == QEvent.Type.KeyPress:
            if isinstance(obj, QComboBox):
                return super().eventFilter(obj, event)

            key = event.key()
            step = 120 if (event.modifiers() & Qt.KeyboardModifier.ShiftModifier) else 50
            if key in (Qt.Key.Key_Up, Qt.Key.Key_W):
                self.view.pan_by(0, -step)
                return True
            elif key in (Qt.Key.Key_Down, Qt.Key.Key_S):
                self.view.pan_by(0, step)
                return True
            elif key in (Qt.Key.Key_Left, Qt.Key.Key_A):
                self.view.pan_by(-step, 0)
                return True
            elif key in (Qt.Key.Key_Right, Qt.Key.Key_D):
                self.view.pan_by(step, 0)
                return True
        return super().eventFilter(obj, event)

    def init_ui(self):
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        main_layout = QHBoxLayout(main_widget)
        main_layout.setContentsMargins(8, 8, 8, 8)
        main_layout.setSpacing(8)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.setChildrenCollapsible(False)
        main_layout.addWidget(splitter)

        # ----------------- LEFT PANEL: Inside QScrollArea -----------------
        control_panel = QWidget()
        control_layout = QVBoxLayout(control_panel)
        control_layout.setContentsMargins(8, 8, 12, 12)
        control_layout.setSpacing(12)

        header_box = QVBoxLayout()
        header_box.setSpacing(2)
        title_lbl = QLabel("PIPE COUNTER PRO")
        title_lbl.setStyleSheet("font-size: 19px; font-weight: 800; color: #38bdf8; letter-spacing: 1.5px;")
        subtitle_lbl = QLabel("AI Pipe Counter with Intelligent Size Differentiation")
        subtitle_lbl.setStyleSheet("font-size: 11px; color: #94a3b8;")
        header_box.addWidget(title_lbl)
        header_box.addWidget(subtitle_lbl)
        control_layout.addLayout(header_box)

        self.btn_upload = QPushButton("📁 Upload Pipe Image")
        self.btn_upload.setFixedHeight(40)
        self.btn_upload.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_upload.clicked.connect(self.on_upload_clicked)
        control_layout.addWidget(self.btn_upload)

        # ----------------- LIVE COUNT SUMMARY -----------------
        kpi_group = QGroupBox("LIVE PIPE COUNT SUMMARY")
        kpi_layout = QVBoxLayout(kpi_group)
        kpi_layout.setContentsMargins(10, 14, 10, 10)
        kpi_layout.setSpacing(8)

        total_hero_box = QFrame()
        total_hero_box.setFixedHeight(82)
        total_hero_box.setStyleSheet("background-color: #1e293b; border-radius: 8px; padding: 8px;")
        total_hero_layout = QVBoxLayout(total_hero_box)
        total_hero_layout.setContentsMargins(0, 0, 0, 0)
        total_hero_layout.setSpacing(2)

        self.lbl_total_val = QLabel("0")
        self.lbl_total_val.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.lbl_total_val.setFixedHeight(42)
        self.lbl_total_val.setStyleSheet("font-size: 40px; font-weight: 900; color: #38bdf8;")
        self.lbl_total_title = QLabel("TOTAL PIPES (COUNTED)")
        self.lbl_total_title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.lbl_total_title.setStyleSheet("font-size: 11px; font-weight: 700; color: #94a3b8; letter-spacing: 1px;")

        total_hero_layout.addWidget(self.lbl_total_val)
        total_hero_layout.addWidget(self.lbl_total_title)
        kpi_layout.addWidget(total_hero_box)

        self.size_cards_container = QWidget()
        self.size_cards_layout = QVBoxLayout(self.size_cards_container)
        self.size_cards_layout.setContentsMargins(0, 2, 0, 2)
        self.size_cards_layout.setSpacing(6)
        kpi_layout.addWidget(self.size_cards_container)

        self.lbl_perf = QLabel("Engine Ready")
        self.lbl_perf.setStyleSheet("font-size: 10px; color: #64748b; font-style: italic; margin-top: 2px;")
        self.lbl_perf.setAlignment(Qt.AlignmentFlag.AlignCenter)
        kpi_layout.addWidget(self.lbl_perf)

        control_layout.addWidget(kpi_group)

        # ----------------- DRAW COLOR CHOICE -----------------
        draw_color_group = QGroupBox("NEW CIRCLE COLOR / SIZE")
        draw_color_layout = QVBoxLayout(draw_color_group)
        draw_color_layout.setContentsMargins(10, 14, 10, 10)
        draw_color_layout.setSpacing(6)

        lbl_color_hint = QLabel("Select color for manual pipe circles:")
        lbl_color_hint.setStyleSheet("font-size: 11px; color: #cbd5e1;")
        draw_color_layout.addWidget(lbl_color_hint)

        color_btn_row = QHBoxLayout()
        color_btn_row.setSpacing(6)
        self.btn_col_green = QPushButton("🟢 Green")
        self.btn_col_green.setCheckable(True)
        self.btn_col_green.setChecked(True)
        self.btn_col_green.setFixedHeight(30)
        self.btn_col_green.setStyleSheet("background-color: #14532d; color: #86efac; border: 2px solid #22c55e;")
        self.btn_col_green.clicked.connect(lambda: self.set_draw_color("Green"))

        self.btn_col_yellow = QPushButton("🟡 Yellow")
        self.btn_col_yellow.setCheckable(True)
        self.btn_col_yellow.setFixedHeight(30)
        self.btn_col_yellow.setStyleSheet("background-color: #713f12; color: #fde047; border: 1px solid #ca8a04;")
        self.btn_col_yellow.clicked.connect(lambda: self.set_draw_color("Yellow"))

        self.btn_col_red = QPushButton("🔴 Red")
        self.btn_col_red.setCheckable(True)
        self.btn_col_red.setFixedHeight(30)
        self.btn_col_red.setStyleSheet("background-color: #7f1d1d; color: #fca5a5; border: 1px solid #dc2626;")
        self.btn_col_red.clicked.connect(lambda: self.set_draw_color("Red"))

        self.color_button_group = QButtonGroup(self)
        self.color_button_group.addButton(self.btn_col_green)
        self.color_button_group.addButton(self.btn_col_yellow)
        self.color_button_group.addButton(self.btn_col_red)

        color_btn_row.addWidget(self.btn_col_green)
        color_btn_row.addWidget(self.btn_col_yellow)
        color_btn_row.addWidget(self.btn_col_red)
        draw_color_layout.addLayout(color_btn_row)

        control_layout.addWidget(draw_color_group)

        # ----------------- CIRCLE CLICK ACTION -----------------
        action_group = QGroupBox("CLICKING ON EXISTING CIRCLES")
        action_layout = QVBoxLayout(action_group)
        action_layout.setContentsMargins(10, 14, 10, 10)
        action_layout.setSpacing(6)

        self.radio_click_delete = QRadioButton("🗑️ Delete Circle on Click (Recommended)")
        self.radio_click_delete.setChecked(True)
        self.radio_click_delete.toggled.connect(self.on_click_behavior_changed)

        self.radio_click_toggle = QRadioButton("⚪ Toggle Active / Deselected on Click")
        self.radio_click_toggle.toggled.connect(self.on_click_behavior_changed)

        action_layout.addWidget(self.radio_click_delete)
        action_layout.addWidget(self.radio_click_toggle)

        bulk_row = QHBoxLayout()
        btn_sel_all = QPushButton("Select All")
        btn_sel_all.setFixedHeight(28)
        btn_sel_all.setStyleSheet("font-size: 11px; background-color: #334155; color: #86efac;")
        btn_sel_all.clicked.connect(self.select_all_pipes)

        btn_desel_all = QPushButton("Deselect All")
        btn_desel_all.setFixedHeight(28)
        btn_desel_all.setStyleSheet("font-size: 11px; background-color: #334155; color: #f87171;")
        btn_desel_all.clicked.connect(self.deselect_all_pipes)

        bulk_row.addWidget(btn_sel_all)
        bulk_row.addWidget(btn_desel_all)
        action_layout.addLayout(bulk_row)

        control_layout.addWidget(action_group)

        # ----------------- AI SIZE DIFFERENTIATION -----------------
        size_settings_group = QGroupBox("AI SIZE DIFFERENTIATION")
        size_settings_layout = QVBoxLayout(size_settings_group)
        size_settings_layout.setContentsMargins(10, 14, 10, 10)
        size_settings_layout.setSpacing(6)

        lbl_size_mode = QLabel("Auto-Categorize Detected Pipes:")
        lbl_size_mode.setStyleSheet("font-size: 11px; font-weight: 600; color: #cbd5e1;")
        size_settings_layout.addWidget(lbl_size_mode)

        self.combo_size_tiers = QComboBox()
        self.combo_size_tiers.addItem("🟢 All Same Size (Green)", 1)
        self.combo_size_tiers.addItem("🟢🔴 2 Types (Green Small / Red Large)", 2)
        self.combo_size_tiers.addItem("🟢🟡🔴 3 Types (Green / Yellow / Red)", 3)
        self.combo_size_tiers.addItem("⚡ Smart Auto-Detect Tiers", 0)
        self.combo_size_tiers.setFixedHeight(32)
        self.combo_size_tiers.setStyleSheet(
            "background-color: #1e293b; color: #f8fafc; border: 1px solid #475569; padding: 3px 8px; border-radius: 4px;"
        )
        self.combo_size_tiers.currentIndexChanged.connect(self.on_size_tiers_changed)
        size_settings_layout.addWidget(self.combo_size_tiers)

        control_layout.addWidget(size_settings_group)

        # ----------------- AI MODEL SETTINGS -----------------
        ai_group = QGroupBox("AI MODEL SETTINGS")
        ai_layout = QVBoxLayout(ai_group)
        ai_layout.setContentsMargins(10, 14, 10, 10)
        ai_layout.setSpacing(8)

        conf_row = QHBoxLayout()
        conf_row.addWidget(QLabel("Confidence:"))
        self.lbl_conf_val = QLabel("35%")
        self.lbl_conf_val.setStyleSheet("font-weight: 700; color: #38bdf8;")
        conf_row.addStretch()
        conf_row.addWidget(self.lbl_conf_val)
        ai_layout.addLayout(conf_row)

        self.slider_conf = QSlider(Qt.Orientation.Horizontal)
        self.slider_conf.setRange(10, 85)
        self.slider_conf.setValue(35)
        self.slider_conf.valueChanged.connect(lambda v: self.lbl_conf_val.setText(f"{v}%"))
        ai_layout.addWidget(self.slider_conf)

        self.btn_run = QPushButton("⚡ Detect & Count (AI)")
        self.btn_run.setFixedHeight(40)
        self.btn_run.setStyleSheet(
            "background-color: #0284c7; color: #ffffff; font-size: 12px; font-weight: 700; border-radius: 6px;"
        )
        self.btn_run.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_run.clicked.connect(self.on_run_clicked)
        ai_layout.addWidget(self.btn_run)

        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 0)
        self.progress_bar.setFixedHeight(4)
        self.progress_bar.setTextVisible(False)
        self.progress_bar.hide()
        ai_layout.addWidget(self.progress_bar)

        control_layout.addWidget(ai_group)

        # Export Excel Button
        self.btn_export = QPushButton("📊 Export Data to Excel (.xlsx)")
        self.btn_export.setFixedHeight(40)
        self.btn_export.setStyleSheet(
            "background-color: #15803d; color: #ffffff; font-size: 12px; font-weight: 700; border-radius: 6px;"
        )
        self.btn_export.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_export.clicked.connect(self.on_export_clicked)
        control_layout.addWidget(self.btn_export)

        control_layout.addStretch()

        control_scroll = QScrollArea()
        control_scroll.setWidgetResizable(True)
        control_scroll.setFrameShape(QFrame.Shape.NoFrame)
        control_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        control_scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        control_scroll.setWidget(control_panel)
        control_scroll.setMinimumWidth(300)
        control_scroll.setMaximumWidth(400)
        splitter.addWidget(control_scroll)

        # ----------------- RIGHT PANEL: Responsive Canvas & Modern Navbar -----------------
        canvas_container = QWidget()
        canvas_layout = QVBoxLayout(canvas_container)
        canvas_layout.setContentsMargins(0, 0, 0, 0)
        canvas_layout.setSpacing(6)

        self.view = InteractiveGraphicsView(self.scene)
        self.view.pipe_drawn.connect(self.on_manual_pipe_drawn)
        self.view.mode_changed.connect(self.on_view_mode_changed)

        # ----------------- MODERN RESPONSIVE NAVBAR -----------------
        navbar = QFrame()
        navbar.setObjectName("topNavbar")
        navbar.setFixedHeight(48)
        navbar.setStyleSheet("""
            #topNavbar {
                background-color: #1e293b;
                border: 1px solid #334155;
                border-radius: 8px;
            }
        """)
        nav_layout = QHBoxLayout(navbar)
        nav_layout.setContentsMargins(10, 4, 10, 4)
        nav_layout.setSpacing(10)

        # Left: File Info Badge
        self.lbl_img_info = QLabel("No image loaded")
        self.lbl_img_info.setStyleSheet(
            "background-color: #0f172a; border: 1px solid #334155; border-radius: 6px; "
            "padding: 4px 10px; font-size: 11px; font-weight: 600; color: #cbd5e1;"
        )
        nav_layout.addWidget(self.lbl_img_info)
        nav_layout.addStretch()

        # Center: Tool Mode Segmented Pill
        tools_pill = QFrame()
        tools_pill.setStyleSheet("""
            QFrame {
                background-color: #0f172a;
                border: 1px solid #334155;
                border-radius: 6px;
            }
        """)
        pill_layout = QHBoxLayout(tools_pill)
        pill_layout.setContentsMargins(3, 3, 3, 3)
        pill_layout.setSpacing(4)

        self.btn_tool_add = QPushButton("✏️ Add")
        self.btn_tool_add.setCheckable(True)
        self.btn_tool_add.setChecked(True)
        self.btn_tool_add.setFixedHeight(28)
        self.btn_tool_add.setStyleSheet("padding: 0 10px; font-size: 11px; border: none;")
        self.btn_tool_add.clicked.connect(lambda: self.view.set_tool_mode("draw"))
        pill_layout.addWidget(self.btn_tool_add)

        # Quick Color chips inside tool pill
        self.tb_col_green = QPushButton("🟢")
        self.tb_col_green.setToolTip("Select Green (Small)")
        self.tb_col_green.setCheckable(True)
        self.tb_col_green.setChecked(True)
        self.tb_col_green.setFixedSize(26, 26)
        self.tb_col_green.setStyleSheet("border-radius: 13px; padding: 0px; border: 2px solid #22c55e;")
        self.tb_col_green.clicked.connect(lambda: self.set_draw_color("Green"))
        pill_layout.addWidget(self.tb_col_green)

        self.tb_col_yellow = QPushButton("🟡")
        self.tb_col_yellow.setToolTip("Select Yellow (Medium)")
        self.tb_col_yellow.setCheckable(True)
        self.tb_col_yellow.setFixedSize(26, 26)
        self.tb_col_yellow.setStyleSheet("border-radius: 13px; padding: 0px; border: 1px solid transparent;")
        self.tb_col_yellow.clicked.connect(lambda: self.set_draw_color("Yellow"))
        pill_layout.addWidget(self.tb_col_yellow)

        self.tb_col_red = QPushButton("🔴")
        self.tb_col_red.setToolTip("Select Red (Large)")
        self.tb_col_red.setCheckable(True)
        self.tb_col_red.setFixedSize(26, 26)
        self.tb_col_red.setStyleSheet("border-radius: 13px; padding: 0px; border: 1px solid transparent;")
        self.tb_col_red.clicked.connect(lambda: self.set_draw_color("Red"))
        pill_layout.addWidget(self.tb_col_red)

        self.tb_color_group = QButtonGroup(self)
        self.tb_color_group.addButton(self.tb_col_green)
        self.tb_color_group.addButton(self.tb_col_yellow)
        self.tb_color_group.addButton(self.tb_col_red)

        # Subtle divider line
        div1 = QFrame()
        div1.setFrameShape(QFrame.Shape.VLine)
        div1.setStyleSheet("color: #334155; margin: 4px 2px;")
        pill_layout.addWidget(div1)

        self.btn_tool_delete = QPushButton("🗑️ Delete")
        self.btn_tool_delete.setCheckable(True)
        self.btn_tool_delete.setFixedHeight(28)
        self.btn_tool_delete.setStyleSheet("padding: 0 10px; font-size: 11px; color: #f87171; border: none;")
        self.btn_tool_delete.clicked.connect(lambda: self.view.set_tool_mode("delete"))
        pill_layout.addWidget(self.btn_tool_delete)

        div2 = QFrame()
        div2.setFrameShape(QFrame.Shape.VLine)
        div2.setStyleSheet("color: #334155; margin: 4px 2px;")
        pill_layout.addWidget(div2)

        self.btn_tool_pan = QPushButton("✋ Pan")
        self.btn_tool_pan.setCheckable(True)
        self.btn_tool_pan.setFixedHeight(28)
        self.btn_tool_pan.setStyleSheet("padding: 0 10px; font-size: 11px; border: none;")
        self.btn_tool_pan.clicked.connect(lambda: self.view.set_tool_mode("pan"))
        pill_layout.addWidget(self.btn_tool_pan)

        self.canvas_tool_group = QButtonGroup(self)
        self.canvas_tool_group.addButton(self.btn_tool_add)
        self.canvas_tool_group.addButton(self.btn_tool_delete)
        self.canvas_tool_group.addButton(self.btn_tool_pan)

        nav_layout.addWidget(tools_pill)
        nav_layout.addStretch()

        # Right: Zoom & Fit Pill
        zoom_pill = QFrame()
        zoom_pill.setStyleSheet("""
            QFrame {
                background-color: #0f172a;
                border: 1px solid #334155;
                border-radius: 6px;
            }
        """)
        zoom_layout = QHBoxLayout(zoom_pill)
        zoom_layout.setContentsMargins(3, 3, 3, 3)
        zoom_layout.setSpacing(4)

        btn_zout = QPushButton("🔍−")
        btn_zout.setToolTip("Zoom Out (Minus key or Ctrl + Wheel)")
        btn_zout.setFixedSize(46, 28)
        btn_zout.setStyleSheet("border: none; font-size: 12px; padding: 0px 4px;")
        btn_zout.clicked.connect(self.view.zoom_out)
        zoom_layout.addWidget(btn_zout)

        btn_zin = QPushButton("🔍+")
        btn_zin.setToolTip("Zoom In (Plus key or Ctrl + Wheel)")
        btn_zin.setFixedSize(46, 28)
        btn_zin.setStyleSheet("border: none; font-size: 12px; padding: 0px 4px;")
        btn_zin.clicked.connect(self.view.zoom_in)
        zoom_layout.addWidget(btn_zin)

        btn_fit = QPushButton("⛶ Fit")
        btn_fit.setToolTip("Fit to View (F or 0 key)")
        btn_fit.setFixedHeight(28)
        btn_fit.setStyleSheet("padding: 0 10px; font-size: 11px; border: none; color: #38bdf8;")
        btn_fit.clicked.connect(self.on_fit_screen_clicked)
        zoom_layout.addWidget(btn_fit)

        nav_layout.addWidget(zoom_pill)
        canvas_layout.addWidget(navbar)

        # Graphics Canvas View
        canvas_layout.addWidget(self.view)

        # Responsive Hint Footer Bar
        hint_bar = QLabel("💡 Navigation: Arrow keys / WASD to move image | Click on circle to Delete | Ctrl+Wheel to Zoom | Mouse Wheel to Scroll")
        hint_bar.setStyleSheet("font-size: 11px; color: #64748b; padding: 2px 8px;")
        canvas_layout.addWidget(hint_bar)

        splitter.addWidget(canvas_container)
        splitter.setStretchFactor(0, 0)
        splitter.setStretchFactor(1, 1)
        splitter.setSizes([340, 1000])

    def apply_dark_theme(self):
        qss = """
        QMainWindow, QWidget {
            background-color: #0f172a;
            color: #f8fafc;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        }
        QGroupBox {
            border: 1px solid #334155;
            border-radius: 8px;
            margin-top: 14px;
            font-weight: 700;
            font-size: 11px;
            color: #94a3b8;
            padding: 10px;
        }
        QGroupBox::title {
            subcontrol-origin: margin;
            subcontrol-position: top left;
            left: 10px;
            padding: 0 4px;
        }
        QPushButton {
            background-color: #334155;
            color: #f8fafc;
            border: 1px solid #475569;
            border-radius: 6px;
            font-weight: 600;
            padding: 5px 10px;
        }
        QPushButton:hover {
            background-color: #475569;
            border-color: #64748b;
        }
        QPushButton:checked {
            background-color: #0284c7;
            border-color: #38bdf8;
            color: #ffffff;
        }
        QRadioButton {
            color: #cbd5e1;
            font-size: 11px;
            font-weight: 500;
            spacing: 6px;
        }
        QRadioButton::indicator {
            width: 14px;
            height: 14px;
            border-radius: 7px;
            border: 1px solid #64748b;
            background-color: #1e293b;
        }
        QRadioButton::indicator:checked {
            background-color: #38bdf8;
            border-color: #0284c7;
        }
        QSlider::groove:horizontal {
            height: 6px;
            background: #334155;
            border-radius: 3px;
        }
        QSlider::sub-page:horizontal {
            background: #38bdf8;
            border-radius: 3px;
        }
        QSlider::handle:horizontal {
            background: #ffffff;
            border: 2px solid #0284c7;
            width: 16px;
            margin-top: -5px;
            margin-bottom: -5px;
            border-radius: 8px;
        }
        QProgressBar {
            background-color: #1e293b;
            border-radius: 2px;
        }
        QProgressBar::chunk {
            background-color: #38bdf8;
            border-radius: 2px;
        }
        QScrollBar:vertical {
            border: none;
            background: #0f172a;
            width: 8px;
            margin: 0px;
            border-radius: 4px;
        }
        QScrollBar::handle:vertical {
            background: #334155;
            min-height: 25px;
            border-radius: 4px;
        }
        QScrollBar::handle:vertical:hover {
            background: #475569;
        }
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
            height: 0px;
        }
        QScrollBar:horizontal {
            border: none;
            background: #0f172a;
            height: 8px;
            margin: 0px;
            border-radius: 4px;
        }
        QScrollBar::handle:horizontal {
            background: #334155;
            min-width: 25px;
            border-radius: 4px;
        }
        QScrollBar::handle:horizontal:hover {
            background: #475569;
        }
        QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {
            width: 0px;
        }
        """
        self.setStyleSheet(qss)

    def set_draw_color(self, color_name: str):
        self.current_draw_color = color_name

        self.btn_col_green.setChecked(color_name == "Green")
        self.btn_col_yellow.setChecked(color_name == "Yellow")
        self.btn_col_red.setChecked(color_name == "Red")

        self.tb_col_green.setChecked(color_name == "Green")
        self.tb_col_yellow.setChecked(color_name == "Yellow")
        self.tb_col_red.setChecked(color_name == "Red")

        # Update styling on toolbar color chips
        self.tb_col_green.setStyleSheet("border-radius: 13px; padding: 0px; border: " + ("2px solid #22c55e;" if color_name == "Green" else "1px solid transparent;"))
        self.tb_col_yellow.setStyleSheet("border-radius: 13px; padding: 0px; border: " + ("2px solid #eab308;" if color_name == "Yellow" else "1px solid transparent;"))
        self.tb_col_red.setStyleSheet("border-radius: 13px; padding: 0px; border: " + ("2px solid #ef4444;" if color_name == "Red" else "1px solid transparent;"))

        self.view.set_tool_mode("draw")

    def on_click_behavior_changed(self):
        if self.radio_click_delete.isChecked():
            self.click_behavior = "delete"
        else:
            self.click_behavior = "toggle"

    def on_view_mode_changed(self, mode: str):
        if mode == "pan":
            self.btn_tool_pan.setChecked(True)
            self.btn_tool_add.setChecked(False)
            self.btn_tool_delete.setChecked(False)
        elif mode == "delete":
            self.btn_tool_delete.setChecked(True)
            self.btn_tool_add.setChecked(False)
            self.btn_tool_pan.setChecked(False)
        else:
            self.btn_tool_add.setChecked(True)
            self.btn_tool_delete.setChecked(False)
            self.btn_tool_pan.setChecked(False)

    def on_upload_clicked(self):
        path, _ = QFileDialog.getOpenFileName(
            self,
            "Select Pipe Bundle Image",
            "",
            "Image Files (*.jpg *.jpeg *.png *.bmp *.webp *.tif *.tiff)",
        )
        if path:
            self.load_image(path)

    def load_image(self, path: str):
        img = cv2.imread(path)
        if img is None:
            QMessageBox.critical(self, "Load Error", f"Failed to read image at:\n{path}")
            return

        self.cv_image = img
        self.source_image_name = os.path.basename(path)
        h, w = img.shape[:2]
        self.lbl_img_info.setText(f"🖼️ {self.source_image_name}  •  {w} × {h} px")

        self.display_base_image()
        self.on_run_clicked()

    def display_base_image(self):
        if self.cv_image is None:
            return

        rgb_image = cv2.cvtColor(self.cv_image, cv2.COLOR_BGR2RGB)
        h, w, ch = rgb_image.shape
        bytes_per_line = ch * w
        qimg = QImage(rgb_image.data, w, h, bytes_per_line, QImage.Format.Format_RGB888)
        pixmap = QPixmap.fromImage(qimg)

        self.scene.clear()
        self.pipe_items.clear()
        self.pixmap_item = self.scene.addPixmap(pixmap)
        self.scene.setSceneRect(0, 0, w, h)
        self.view.reset_view(QRectF(0, 0, w, h))

    def on_run_clicked(self):
        if self.cv_image is None:
            QMessageBox.information(self, "No Image", "Please upload a pipe bundle image first.")
            return

        confidence = self.slider_conf.value() / 100.0
        num_sizes = self.combo_size_tiers.currentData()

        self.btn_run.setEnabled(False)
        self.progress_bar.show()
        self.lbl_perf.setText("Running AI Pipe Detection...")

        self.worker = DetectionWorker(self.cv_image, confidence, iou=0.45, num_sizes=num_sizes)
        self.worker.finished.connect(self.on_detection_finished)
        self.worker.error.connect(self.on_detection_error)
        self.worker.start()

    def on_detection_finished(self, summary: DetectionSummary):
        self.btn_run.setEnabled(True)
        self.progress_bar.hide()
        self.summary = summary

        self.build_pipe_overlays()
        self.update_kpi_dashboard()

    def on_detection_error(self, err_msg: str):
        self.btn_run.setEnabled(True)
        self.progress_bar.hide()
        self.lbl_perf.setText("Detection Error")
        QMessageBox.critical(self, "Processing Error", f"Error during pipe detection:\n{err_msg}")

    def on_size_tiers_changed(self):
        if self.summary is None or not self.summary.pipes:
            return
        num_sizes = self.combo_size_tiers.currentData()
        self.summary = PipeCounterEngine.reclassify(self.summary, num_sizes)
        for item in self.pipe_items:
            item.update_tooltip()
            item.update()
        self.update_kpi_dashboard()

    def build_pipe_overlays(self):
        for item in self.pipe_items:
            self.scene.removeItem(item)
        self.pipe_items.clear()

        if self.summary is None:
            return

        for pipe in self.summary.pipes:
            item = PipeGraphicsItem(
                pipe,
                on_click_cb=self.on_pipe_clicked,
                on_delete_cb=self.delete_pipe_item,
                on_recolor_cb=self.recolor_pipe_item,
            )
            self.scene.addItem(item)
            self.pipe_items.append(item)

    def on_pipe_clicked(self, item: PipeGraphicsItem):
        if self.view._tool_mode == "delete" or self.click_behavior == "delete":
            self.delete_pipe_item(item)
        else:
            item.toggle_selection()
            self.sync_after_change()

    def delete_pipe_item(self, item: PipeGraphicsItem):
        if item in self.pipe_items:
            self.pipe_items.remove(item)
        if self.summary and item.pipe in self.summary.pipes:
            self.summary.pipes.remove(item.pipe)
        self.scene.removeItem(item)
        self.sync_after_change()

    def recolor_pipe_item(self, item: PipeGraphicsItem, new_color: str):
        item.pipe.category = new_color
        item.pipe.is_manual = True
        item.update_tooltip()
        item.update()
        self.sync_after_change()

    def get_default_diameter_for_color(self, color_name: str) -> float:
        if self.summary and self.summary.pipes:
            matching_diams = [
                p.diameter for p in self.summary.pipes
                if p.category == color_name and p.is_selected
            ]
            if matching_diams:
                return float(np.median(matching_diams))

            active_diams = [p.diameter for p in self.summary.pipes if p.is_selected]
            if active_diams:
                base_median = float(np.median(active_diams))
                if color_name == "Green":
                    return base_median * 0.9 if self.summary.num_sizes > 1 else base_median
                elif color_name == "Yellow":
                    return base_median * 1.05
                elif color_name == "Red":
                    return base_median * 1.25

        defaults = {"Green": 19.0, "Yellow": 23.0, "Red": 27.0}
        return defaults.get(color_name, 22.0)

    def on_manual_pipe_drawn(self, cx: float, cy: float, radius: float):
        if self.summary is None or self.cv_image is None:
            return

        if radius <= 0.0:
            diam = self.get_default_diameter_for_color(self.current_draw_color)
            radius = diam / 2.0
        else:
            diam = radius * 2.0

        new_id = max([p.id for p in self.summary.pipes], default=0) + 1
        new_pipe = PipeDetection(
            id=new_id,
            cx=cx,
            cy=cy,
            width=diam,
            height=diam,
            angle=0.0,
            area=float(math.pi * radius * radius),
            solidity=1.0,
            confidence=1.0,
            is_selected=True,
            is_manual=True,
            category=self.current_draw_color,
            ellipse=((cx, cy), (diam, diam), 0.0),
        )

        self.summary.pipes.append(new_pipe)

        item = PipeGraphicsItem(
            new_pipe,
            on_click_cb=self.on_pipe_clicked,
            on_delete_cb=self.delete_pipe_item,
            on_recolor_cb=self.recolor_pipe_item,
        )
        self.scene.addItem(item)
        self.pipe_items.append(item)

        self.sync_after_change()

    def sync_after_change(self):
        if self.summary is not None:
            num_sizes = self.combo_size_tiers.currentData()
            self.summary = PipeCounterEngine.reclassify(self.summary, num_sizes)
            for it in self.pipe_items:
                it.update()
            self.update_kpi_dashboard()

    def select_all_pipes(self):
        if not self.summary:
            return
        for p in self.summary.pipes:
            p.is_selected = True
        self.sync_after_change()

    def deselect_all_pipes(self):
        if not self.summary:
            return
        for p in self.summary.pipes:
            p.is_selected = False
        self.sync_after_change()

    def update_kpi_dashboard(self):
        if self.summary is None:
            return

        selected_count = sum(1 for p in self.summary.pipes if p.is_selected)
        deselected_count = len(self.summary.pipes) - selected_count

        self.summary.selected_count = selected_count
        self.summary.deselected_count = deselected_count

        self.lbl_total_val.setText(str(selected_count))
        self.lbl_perf.setText(f"{self.summary.model_name} • {self.summary.processing_time_ms:.1f} ms")

        # Clear old cards
        while self.size_cards_layout.count():
            child = self.size_cards_layout.takeAt(0)
            if child.widget():
                child.widget().deleteLater()

        card_count = 0
        for cat_name in ["Green", "Yellow", "Red"]:
            stats = self.summary.size_stats.get(cat_name)
            if not stats or stats.count == 0:
                continue

            card = QFrame()
            card.setFixedHeight(48)
            card.setStyleSheet(
                f"background-color: #1e293b; "
                f"border: 1px solid #334155; "
                f"border-left: 5px solid {stats.hex_color}; "
                f"border-radius: 6px;"
            )
            card_layout = QHBoxLayout(card)
            card_layout.setContentsMargins(10, 4, 12, 4)
            card_layout.setSpacing(6)

            info_box = QVBoxLayout()
            info_box.setSpacing(2)
            lbl_name = QLabel(stats.name.upper())
            lbl_name.setStyleSheet(f"font-size: 11px; font-weight: 800; color: {stats.hex_color};")
            lbl_diam = QLabel(f"Ø {stats.min_diam:.1f} - {stats.max_diam:.1f} px (avg {stats.avg_diam:.1f})")
            lbl_diam.setStyleSheet("font-size: 10px; color: #94a3b8;")
            info_box.addWidget(lbl_name)
            info_box.addWidget(lbl_diam)

            lbl_count = QLabel(str(stats.count))
            lbl_count.setStyleSheet(f"font-size: 22px; font-weight: 900; color: {stats.hex_color};")
            lbl_count.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)

            card_layout.addLayout(info_box)
            card_layout.addStretch()
            card_layout.addWidget(lbl_count)

            self.size_cards_layout.addWidget(card)
            card_count += 1

        total_container_height = max(50, card_count * 56)
        self.size_cards_container.setFixedHeight(total_container_height)

        if deselected_count > 0:
            lbl_desel = QLabel(f"Excluded: {deselected_count} pipes")
            lbl_desel.setStyleSheet("font-size: 11px; color: #ef4444; font-weight: 600; padding-top: 4px;")
            self.size_cards_layout.addWidget(lbl_desel)

    def on_export_clicked(self):
        if self.summary is None or len(self.summary.pipes) == 0:
            QMessageBox.information(self, "No Data", "Please run detection on an image before exporting.")
            return

        base_name = os.path.splitext(self.source_image_name)[0]
        default_file = f"{base_name}_pipe_count.xlsx"

        path, _ = QFileDialog.getSaveFileName(
            self,
            "Save Excel Report",
            default_file,
            "Excel Workbook (*.xlsx)",
        )
        if not path:
            return

        try:
            out_path = PipeCounterEngine.export_to_excel(self.summary, self.source_image_name, path)
            QMessageBox.information(
                self,
                "Export Complete",
                f"Successfully exported data for {self.summary.selected_count} counted pipes to:\n{out_path}",
            )
        except Exception as e:
            QMessageBox.critical(self, "Export Failed", f"Failed to write Excel workbook:\n{e}")

    def on_fit_screen_clicked(self):
        if self.cv_image is not None:
            h, w = self.cv_image.shape[:2]
            self.view.reset_view(QRectF(0, 0, w, h))


def main():
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
