# ISSF Target Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend STASYS Shot Analysis tab with ISSF standard target visualization and decimal scoring

**Architecture:** Extend existing `ShotTraceCanvas` widget to support ISSF target rendering mode alongside current simple rings. Add dual scoring (ISSF decimal + stability) and Settings controls for target type selection.

**Tech Stack:** PyQt5, QPainter, Python dataclasses, SQLite (optional extension)

---

## File Structure

### Primary File
- **`stasys_app/base.py`** - All changes go here (~250-300 new lines)
  - Configuration section (lines ~50-150): Add `ISSFTargetSpec` dataclass, `TARGET_SPECS` dictionary, scoring function
  - `ShotTraceCanvas` class (lines ~1276-1368): Extend with ISSF rendering properties and methods
  - `PerShotStatsWidget` class (lines ~1421-1577): Add ISSF score label and display logic
  - `MainWindow._build_settings_tab()`: Add target type and view mode dropdowns

### Optional Test File
- **`test/test_issf_target.py`** - Unit tests for scoring calculation (new file)

---

## Task 1: Add Dataclass and Target Specifications

**Files:**
- Modify: `stasys_app/base.py` (insert after line 162, after `SCREEN_Y_SIGN = 1.0`)

- [ ] **Step 1: Add dataclass import and ISSFTargetSpec definition**

```python
from dataclasses import dataclass
from typing import List, Tuple

@dataclass
class ISSFTargetSpec:
    """ISSF target specification for rendering and scoring."""
    name: str                      # Display name
    distance_m: float              # Target distance in metres
    total_diameter_mm: float       # Outer edge diameter (1-ring)
    ten_ring_diameter_mm: float   # 10-ring outer edge diameter
    inner_ten_mm: float            # 10.9 ring diameter
    ring_count: int = 10           # Number of scoring rings
```

- [ ] **Step 2: Add TARGET_SPECS dictionary with all three target types**

```python
TARGET_SPECS = {
    '10m_air_pistol': ISSFTargetSpec(
        name='10m Air Pistol',
        distance_m=10.0,
        total_diameter_mm=170.0,
        ten_ring_diameter_mm=11.5,
        inner_ten_mm=5.75,
        ring_count=10,
    ),
    '25m_sport_pistol': ISSFTargetSpec(
        name='25m Sport Pistol',
        distance_m=25.0,
        total_diameter_mm=500.0,
        ten_ring_diameter_mm=50.0,
        inner_ten_mm=25.0,
        ring_count=10,
    ),
    '50m_free_pistol': ISSFTargetSpec(
        name='50m Free Pistol',
        distance_m=50.0,
        total_diameter_mm=500.0,
        ten_ring_diameter_mm=50.0,
        inner_ten_mm=25.0,
        ring_count=10,
    ),
}
```

- [ ] **Step 3: Commit the data structures**

```bash
git add stasys_app/base.py
git commit -m "feat: add ISSF target specification data structures"
```

---

## Task 2: Implement ISSF Scoring Calculation

**Files:**
- Modify: `stasys_app/base.py` (insert after TARGET_SPECS definition)

- [ ] **Step 1: Write calculate_issf_score function**

```python
def calculate_issf_score(impact_x_cm: float, impact_y_cm: float,
                        target_spec: ISSFTargetSpec) -> Tuple[float, int]:
    """
    Convert impact position to ISSF decimal score.

    Args:
        impact_x_cm: X offset from center (cm) at target distance
        impact_y_cm: Y offset from center (cm) at target distance
        target_spec: Target specification with dimensions

    Returns:
        (decimal_score, ring_number)
        Examples: (10.9, 10) for center, (8.5, 8), (0.0, 0) for miss
    """
    # Calculate radial distance from center in millimetres
    distance_mm = math.sqrt(impact_x_cm**2 + impact_y_cm**2) * 10.0

    # Check for miss (outside target area)
    target_radius_mm = target_spec.total_diameter_mm / 2.0
    if distance_mm > target_radius_mm:
        return (0.0, 0)

    # Determine ring number (1-10)
    # Calculate spacing between rings outside the 10-ring
    ring_spacing = (target_spec.total_diameter_mm -
                    target_spec.ten_ring_diameter_mm) / (target_spec.ring_count - 1)

    if distance_mm <= target_spec.inner_ten_mm:
        # Inside 10-ring: calculate decimal score (10.0 to 10.9)
        ring = 10
        # Inner edge = 10.9, outer edge of inner-ten = 10.0
        decimal = 10.0 + (1.0 - (distance_mm / target_spec.inner_ten_mm))
    elif distance_mm <= target_spec.ten_ring_diameter_mm / 2.0:
        # In the 10-ring but outside inner-ten zone
        ring = 10
        decimal = 10.0
    else:
        # Outside 10-ring: calculate which ring
        distance_from_ten_edge = distance_mm - (target_spec.ten_ring_diameter_mm / 2.0)
        ring = int(10 - (distance_from_ten_edge / ring_spacing))
        ring = max(1, min(10, ring))
        decimal = float(ring)

    return (round(decimal, 1), ring)
```

- [ ] **Step 2: Write a simple inline test to verify the function**

```python
# Add this test block directly after the function (remove after verification)
if __name__ == "__main__":
    spec = TARGET_SPECS['10m_air_pistol']
    # Test center shot
    assert calculate_issf_score(0, 0, spec) == (10.9, 10), "Center should be 10.9"
    # Test edge of 10-ring (half of 11.5mm = 5.75mm radius)
    result, ring = calculate_issf_score(0.0575, 0, spec)
    assert abs(result - 10.0) < 0.1, f"Edge of 10-ring should be ~10.0, got {result}"
    # Test miss (beyond 85mm radius)
    assert calculate_issf_score(9.0, 9.0, spec) == (0.0, 0), "Should be a miss"
    print("All scoring tests passed!")
```

- [ ] **Step 3: Run the inline test**

```bash
cd stasys_app
python -c "from base import calculate_issf_score, TARGET_SPECS; spec = TARGET_SPECS['10m_air_pistol']; print(calculate_issf_score(0, 0, spec)); print(calculate_issf_score(0.0575, 0, spec))"
```

Expected output: `(10.9, 10)` and `(10.0, 10)` (or approximately)

- [ ] **Step 4: Remove the test block from the code**

- [ ] **Step 5: Commit the scoring function**

```bash
git add stasys_app/base.py
git commit -m "feat: implement ISSF decimal scoring calculation"
```

---

## Task 3: Extend ShotTraceCanvas with ISSF Properties

**Files:**
- Modify: `stasys_app/base.py` (ShotTraceCanvas.__init__ method, lines ~1283-1295)

- [ ] **Step 1: Add new properties to ShotTraceCanvas.__init__**

Find the `__init__` method and add these new properties after existing ones (after line 1294):

```python
class ShotTraceCanvas(QWidget):
    """Shot trace canvas with 3 phases: Hold (red), Press (yellow), Recoil (cyan)."""

    COL_HOLD  = '#FF0000'
    COL_PRESS = '#FFFF00'
    COL_RECOIL = '#00FFFF'

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(400, 400)
        self.hol_x, self.hol_y = [], []
        self.pre_x, self.pre_y = [], []
        self.rec_x, self.rec_y = [], []
        self.score = 0
        self.impact_x_cm = 0.0
        self.impact_y_cm = 0.0
        self.current_shot_idx = 0
        self.scale = 1.0
        self.plot_range = PLOT_RANGE

        # NEW: ISSF target properties
        self.target_type = '10m_air_pistol'  # Default target
        self.issf_mode = True                 # Enable ISSF rendering by default
        self.impact_points = []               # List of (x_cm, y_cm, score) for overlay
```

- [ ] **Step 2: Add set_target_type method**

Add this method after `clear_trace` method (after line 1315):

```python
    def set_target_type(self, type_key: str):
        """Set the target type for ISSF rendering."""
        if type_key not in TARGET_SPECS:
            logger.warning(f"Unknown target type: {type_key}, defaulting to 10m_air_pistol")
            self.target_type = '10m_air_pistol'
        else:
            self.target_type = type_key
        self.update()
```

- [ ] **Step 3: Add set_issf_mode method**

Add after `set_target_type`:

```python
    def set_issf_mode(self, enabled: bool):
        """Enable or disable ISSF target rendering mode."""
        self.issf_mode = enabled
        self.update()
```

- [ ] **Step 4: Add add_impact_point method for overlay**

Add after `set_issf_mode`:

```python
    def add_impact_point(self, x_cm: float, y_cm: float, score: float):
        """Add an impact point for overlay display."""
        self.impact_points.append((x_cm, y_cm, score))
        self.update()
```

- [ ] **Step 5: Modify clear_trace to also clear impact points**

Find the `clear_trace` method and add a line to clear impact points:

```python
    def clear_trace(self):
        self.hol_x, self.hol_y = [], []
        self.pre_x, self.pre_y = [], []
        self.rec_x, self.rec_y = [], []
        self.score = 0
        self.impact_x_cm = 0.0
        self.impact_y_cm = 0.0
        self.current_shot_idx = 0
        self.impact_points = []  # NEW: Clear impact points
        self.update()
```

- [ ] **Step 6: Commit the property extensions**

```bash
git add stasys_app/base.py
git commit -m "feat: add ISSF properties and methods to ShotTraceCanvas"
```

---

## Task 4: Implement ISSF Target Drawing Method

**Files:**
- Modify: `stasys_app/base.py` (ShotTraceCanvas class, add new method after `_draw_path`)

- [ ] **Step 1: Add draw_issf_target method**

Add this method after the `_draw_path` method (after line 1334):

```python
    def _draw_issf_target(self, painter, cx, cy, scale):
        """Draw ISSF standard target with proper scoring rings and colors."""
        spec = TARGET_SPECS[self.target_type]

        # Convert millimetres to screen coordinates
        # Target is displayed at actual scale relative to plot_range
        # plot_range is in radians, need to convert to target distance
        # Use a fixed scale factor for target display
        target_scale_factor = scale / (self.plot_range * 100)  # Adjust for mm display

        # Draw rings from outer to inner
        painter.setPen(QPen(QColor('#333333'), 1))

        # Ring colors: 1-3 white, 4-7 black, 8-10 black (ISSF standard)
        # But for display we use: outer rings lighter, inner rings darker
        ring_colors = {
            1: '#FFFFFF', 2: '#FFFFFF', 3: '#FFFFFF',
            4: '#333333', 5: '#333333', 6: '#333333', 7: '#333333',
            8: '#000000', 9: '#000000', 10: '#000000'
        }

        for ring_num in range(spec.ring_count, 0, -1):
            # Calculate ring diameter
            if ring_num == 10:
                radius_mm = spec.ten_ring_diameter_mm / 2
            elif ring_num == 1:
                radius_mm = spec.total_diameter_mm / 2
            else:
                # Interpolate between 10-ring and outer edge
                ring_spacing = (spec.total_diameter_mm -
                                spec.ten_ring_diameter_mm) / (spec.ring_count - 1)
                radius_mm = (spec.ten_ring_diameter_mm / 2) + ((10 - ring_num) * ring_spacing)

            screen_radius = radius_mm * target_scale_factor * 50  # Scale for visibility

            color = ring_colors.get(ring_num, '#333333')
            painter.setBrush(QBrush(QColor(color)))
            painter.setPen(QPen(QColor('#666666'), 1))

            rect = QRectF(cx - screen_radius, cy - screen_radius,
                         screen_radius * 2, screen_radius * 2)
            painter.drawEllipse(rect)

        # Draw inner 10-ring (10.9 zone indicator)
        inner_radius = (spec.inner_ten_mm / 2) * target_scale_factor * 50
        painter.setBrush(Qt.NoBrush)
        painter.setPen(QPen(QColor(COLORS['accent_good']), 1))
        inner_rect = QRectF(cx - inner_radius, cy - inner_radius,
                            inner_radius * 2, inner_radius * 2)
        painter.drawEllipse(inner_rect)
```

- [ ] **Step 2: Add draw_impact_points method**

Add after `_draw_issf_target`:

```python
    def _draw_impact_points(self, painter, cx, cy, scale):
        """Draw shot impact points overlay with color coding by score."""
        target_scale_factor = scale / (self.plot_range * 100)

        for x_cm, y_cm, score in self.impact_points:
            # Convert impact position to screen coordinates
            screen_x = cx + (x_cm * 10 * target_scale_factor * 50)
            screen_y = cy - (y_cm * 10 * target_scale_factor * 50)

            # Color code by score
            if score >= 10.0:
                color = QColor(COLORS['accent_good'])  # Green for 10+
            elif score >= 8.0:
                color = QColor(COLORS['accent_ok'])    # Yellow for 8-9
            elif score > 0:
                color = QColor(COLORS['accent_bad'])   # Red for 1-7
            else:
                color = QColor(COLORS['text_muted'])   # Gray for miss

            if score == 0.0:
                # Draw 'X' for miss
                painter.setPen(QPen(color, 2))
                marker_size = 6
                painter.drawLine(int(screen_x - marker_size), int(screen_y - marker_size),
                                int(screen_x + marker_size), int(screen_y + marker_size))
                painter.drawLine(int(screen_x + marker_size), int(screen_y - marker_size),
                                int(screen_x - marker_size), int(screen_y + marker_size))
            else:
                # Draw circle for hit
                painter.setBrush(QBrush(color))
                painter.setPen(Qt.NoPen)
                painter.drawEllipse(int(screen_x) - 4, int(screen_y) - 4, 8, 8)
```

- [ ] **Step 3: Commit the drawing methods**

```bash
git add stasys_app/base.py
git commit -m "feat: add ISSF target and impact point drawing methods"
```

---

## Task 5: Modify paintEvent to Support ISSF Mode

**Files:**
- Modify: `stasys_app/base.py` (ShotTraceCanvas.paintEvent method, lines ~1336-1368)

- [ ] **Step 1: Modify paintEvent to call ISSF drawing**

Replace the entire `paintEvent` method (lines ~1336-1368) with:

```python
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor(COLORS['bg_secondary']))

        w, h = self.width(), self.height()
        cx, cy = w // 2, h // 2
        scale = min(w, h) / (2 * self.plot_range) * 0.9 * self.scale

        # Draw target (ISSF or simple rings)
        if self.issf_mode:
            self._draw_issf_target(painter, cx, cy, scale)
        else:
            # Original simple ring drawing
            for r in self.ring_radii:
                sx, sy = cx, cy
                ring_rect = QRectF(sx - r * scale, sy - r * scale, r * 2 * scale, r * 2 * scale)
                painter.setPen(QPen(QColor('#2A2A2A'), 1))
                painter.drawEllipse(ring_rect)

        # Draw crosshair center
        painter.setPen(QPen(QColor('#333333'), 1))
        painter.drawLine(cx - 20, cy, cx + 20, cy)
        painter.drawLine(cx, cy - 20, cx, cy + 20)

        # Draw shot trace phases (unchanged)
        self._draw_path(painter, self.hol_x, self.hol_y, cx, cy, scale,
                        QPen(QColor(self.COL_HOLD), 2))
        self._draw_path(painter, self.pre_x, self.pre_y, cx, cy, scale,
                        QPen(QColor(self.COL_PRESS), 3))
        self._draw_path(painter, self.rec_x, self.rec_y, cx, cy, scale,
                        QPen(QColor(self.COL_RECOIL), 2))

        # Draw current impact marker
        if abs(self.impact_x_cm) > 0.01 or abs(self.impact_y_cm) > 0.01:
            imp_scale = scale / self.plot_range
            imp_pix_x = cx + self.impact_x_cm * 0.01 * imp_scale
            imp_pix_y = cy - self.impact_y_cm * 0.01 * imp_scale
            painter.setBrush(QBrush(QColor('#00E5FF')))
            painter.setPen(Qt.NoPen)
            painter.drawEllipse(int(imp_pix_x) - 5, int(imp_pix_y) - 5, 10, 10)

        # Draw impact points overlay if in ISSF mode
        if self.issf_mode and self.impact_points:
            self._draw_impact_points(painter, cx, cy, scale)

        # Draw shot number
        if self.current_shot_idx > 0:
            painter.setPen(QPen(QColor(COLORS['text_secondary'])))
            painter.setFont(QFont("Segoe UI", 14, QFont.Bold))
            painter.drawText(20, 30, f"Shot #{self.current_shot_idx}")
```

- [ ] **Step 2: Commit the paintEvent modification**

```bash
git add stasys_app/base.py
git commit -m "feat: integrate ISSF target rendering into paintEvent"
```

---

## Task 6: Extend PerShotStatsWidget with ISSF Score Display

**Files:**
- Modify: `stasys_app/base.py` (PerShotStatsWidget._setup_ui method, lines ~1426-1503)

- [ ] **Step 1: Add ISSF score label to _setup_ui**

Find the impact label line in `_setup_ui` (around line 1501-1502) and add ISSF label before it:

```python
        self._imp_lbl = QLabel("Impact: (--, --)")
        self._imp_lbl.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 11px;")
        layout.addWidget(self._imp_lbl)

        # NEW: ISSF score label
        self._issf_score_lbl = QLabel("ISSF: --")
        self._issf_score_lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px; font-weight: 600;")
        layout.addWidget(self._issf_score_lbl)

        layout.addStretch()
```

- [ ] **Step 2: Modify populate method to calculate ISSF score**

Find the `populate` method (around line 1506-1541) and add ISSF score calculation after impact handling:

```python
    def populate(self, shot):
        for phase, key in [('Hold', 'hold_score'),
                           ('Press', 'press_score'),
                           ('Recoil', 'recoil_score'),
                           ('FT', 'ft_score')]:
            score = shot.get(key, 0) or 0
            self._phase_bars[phase].setValue(int(score))
            self._phase_bars[f'{phase}_lbl'].setText(f"{int(score)}")

        a2c_angle = shot.get('a2c_angle', 0) or 0
        a2c_mag = shot.get('a2c_mag', 0) or 0
        self._a2c_lbl.setText(f"A2C: {a2c_angle:+.1f}° / {a2c_mag:.1f}mrad")

        stab = shot.get('score', 0) or 0
        self._stab_lbl.setText(f"Stability: {int(stab)}")
        self._shoot_lbl.setText(f"Shooting: {int(stab)}")

        score_val = shot.get('score', 0) or 0
        grade_color = self._score_color(score_val)
        grade = self._letter_grade(score_val)
        self._grade_lbl.setText(f"Grade: {grade}")
        self._grade_lbl.setStyleSheet(
            f"background: {grade_color}33; border: 1px solid {grade_color}88; "
            f"border-radius: 8px; padding: 6px 14px; "
            f"font-size: 12px; font-weight: 700; color: {grade_color};")

        err = shot.get('error_type', '') or ''
        if err and err not in ('NONE', 'none', ''):
            self._err_lbl.setText(f"Error: {err}")
            self._err_lbl.setVisible(True)
        else:
            self._err_lbl.setVisible(False)

        ix = shot.get('impact_x_cm', 0) or 0
        iy = shot.get('impact_y_cm', 0) or 0
        self._imp_lbl.setText(f"Impact: ({ix:+.1f}, {iy:+.1f}) cm")

        # NEW: Calculate and display ISSF score
        target_spec = TARGET_SPECS.get('10m_air_pistol', TARGET_SPECS['10m_air_pistol'])
        issf_score, ring = calculate_issf_score(ix, iy, target_spec)
        self._issf_score_lbl.setText(f"ISSF: {issf_score:.1f} (Ring {ring})")
```

- [ ] **Step 3: Modify clear method to reset ISSF label**

Find the `clear` method (around line 1563-1576) and add ISSF label reset:

```python
    def clear(self):
        for phase in ['Hold', 'Press', 'Recoil', 'FT']:
            self._phase_bars[phase].setValue(0)
            self._phase_bars[f'{phase}_lbl'].setText("--")
        self._a2c_lbl.setText("A2C: --")
        self._stab_lbl.setText("Stability: --")
        self._shoot_lbl.setText("Shooting: --")
        self._grade_lbl.setText("Grade: --")
        self._grade_lbl.setStyleSheet(
            f"background: {COLORS['bg_tertiary']}; border: 1px solid {COLORS['border']}; "
            f"border-radius: 8px; padding: 6px 14px; "
            f"font-size: 12px; font-weight: 700; color: {COLORS['text_secondary']};")
        self._err_lbl.setVisible(False)
        self._imp_lbl.setText("Impact: (--, --)")
        self._issf_score_lbl.setText("ISSF: --")  # NEW: Clear ISSF label
```

- [ ] **Step 4: Commit the PerShotStatsWidget extensions**

```bash
git add stasys_app/base.py
git commit -m "feat: add ISSF score display to PerShotStatsWidget"
```

---

## Task 7: Add Settings Tab Controls

**Files:**
- Modify: `stasys_app/base.py` (find `_build_settings_tab` method, add controls)

- [ ] **Step 1: Locate the Settings tab build method**

Search for `_build_settings_tab` in the file. If it doesn't exist, you'll need to create it. Based on the pattern from other tab builders, add it after `_build_shot_analysis_tab`.

- [ ] **Step 2: Add target type dropdown to Settings**

Insert these controls in the settings layout (find where other settings controls are and add there):

```python
    def _build_settings_tab(self):
        tab = QWidget()
        tab.setStyleSheet(f"background: {COLORS['bg_primary']};")
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(16)

        # Target Settings Section
        target_section = QFrame()
        target_section.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_secondary']};
                border: 1px solid {COLORS['border']};
                border-radius: 12px;
                padding: 16px;
            }}
        """)
        target_layout = QVBoxLayout(target_section)

        target_title = QLabel("Target Settings")
        target_title.setFont(QFont("Segoe UI", 14, QFont.Bold))
        target_title.setStyleSheet(f"color: {COLORS['accent_good']};")
        target_layout.addWidget(target_title)

        # Target Type Dropdown
        type_row = QHBoxLayout()
        type_lbl = QLabel("Target Type:")
        type_lbl.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 13px;")
        type_lbl.setFixedWidth(100)
        type_row.addWidget(type_lbl)

        self.cmb_target_type = QComboBox()
        self.cmb_target_type.addItems(["10m Air Pistol", "25m Sport Pistol", "50m Free Pistol"])
        self.cmb_target_type.setFont(QFont("Segoe UI", 13))
        self.cmb_target_type.setStyleSheet(f"""
            QComboBox {{
                background: {COLORS['bg_tertiary']};
                color: {COLORS['text_primary']};
                border: 2px solid {COLORS['border']};
                border-radius: 8px;
                padding: 8px 12px;
                font-size: 13px;
            }}
            QComboBox::drop-down {{ border: none; }}
            QComboBox QAbstractItemView {{
                background: {COLORS['bg_tertiary']};
                color: {COLORS['text_primary']};
                border: 1px solid {COLORS['border']};
                selection-background-color: {COLORS['accent_good']};
                selection-color: #000000;
            }}
        """)
        self.cmb_target_type.currentIndexChanged.connect(self.change_target_type)
        type_row.addWidget(self.cmb_target_type, 1)
        target_layout.addLayout(type_row)

        # View Mode Dropdown
        view_row = QHBoxLayout()
        view_lbl = QLabel("Target View:")
        view_lbl.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 13px;")
        view_lbl.setFixedWidth(100)
        view_row.addWidget(view_lbl)

        self.cmb_view_mode = QComboBox()
        self.cmb_view_mode.addItems(["ISSF Target", "Simple Rings"])
        self.cmb_view_mode.setFont(QFont("Segoe UI", 13))
        self.cmb_view_mode.setStyleSheet(f"""
            QComboBox {{
                background: {COLORS['bg_tertiary']};
                color: {COLORS['text_primary']};
                border: 2px solid {COLORS['border']};
                border-radius: 8px;
                padding: 8px 12px;
                font-size: 13px;
            }}
            QComboBox::drop-down {{ border: none; }}
            QComboBox QAbstractItemView {{
                background: {COLORS['bg_tertiary']};
                color: {COLORS['text_primary']};
                border: 1px solid {COLORS['border']};
                selection-background-color: {COLORS['accent_good']};
                selection-color: #000000;
            }}
        """)
        self.cmb_view_mode.setCurrentIndex(0)  # Default to ISSF
        self.cmb_view_mode.currentIndexChanged.connect(self.change_view_mode)
        view_row.addWidget(self.cmb_view_mode, 1)
        target_layout.addLayout(view_row)

        layout.addWidget(target_section)
        layout.addStretch()

        self.tabs.addTab(tab, "Settings")
```

- [ ] **Step 3: Add callback methods to MainWindow**

Add these methods to the `MainWindow` class (find a good spot after other callback methods):

```python
    def change_target_type(self, index):
        """Handle target type dropdown change."""
        type_map = {
            0: '10m_air_pistol',
            1: '25m_sport_pistol',
            2: '50m_free_pistol'
        }
        target_key = type_map.get(index, '10m_air_pistol')

        # Update shot trace canvas if it exists
        if hasattr(self, 'shot_trace_canvas'):
            self.shot_trace_canvas.set_target_type(target_key)
```

```python
    def change_view_mode(self, index):
        """Handle view mode dropdown change."""
        issf_enabled = (index == 0)  # First option is ISSF

        # Update shot trace canvas if it exists
        if hasattr(self, 'shot_trace_canvas'):
            self.shot_trace_canvas.set_issf_mode(issf_enabled)
```

- [ ] **Step 4: Store reference to shot_trace_canvas**

Find where the shot analysis tab is built (in `_build_shot_analysis_tab`) and add a reference:

```python
        # After creating the ShotTraceCanvas instance
        self.shot_trace_canvas = ShotTraceCanvas()
```

- [ ] **Step 5: Commit the Settings controls**

```bash
git add stasys_app/base.py
git commit -m "feat: add target type and view mode controls to Settings"
```

---

## Task 8: Wire Up Impact Points from Session Data

**Files:**
- Modify: `stasys_app/base.py` (find where shots are loaded and displayed in Shot Analysis tab)

- [ ] **Step 1: Find shot loading code**

Search for where session shots are displayed. This is typically in a method that handles shot selection or session loading.

- [ ] **Step 2: Add impact point recording when shots are displayed**

When a shot is displayed, add its impact point to the canvas. Add this after the shot trace is set:

```python
        # After calling set_trace on shot_trace_canvas
        if self.shot_trace_canvas:
            # Calculate ISSF score for this shot
            ix = shot.get('impact_x_cm', 0) or 0
            iy = shot.get('impact_y_cm', 0) or 0
            target_spec = TARGET_SPECS.get(self.shot_trace_canvas.target_type,
                                           TARGET_SPECS['10m_air_pistol'])
            issf_score, _ = calculate_issf_score(ix, iy, target_spec)

            # Add impact point to canvas
            self.shot_trace_canvas.add_impact_point(ix, iy, issf_score)
```

- [ ] **Step 3: Commit the impact point wiring**

```bash
git add stasys_app/base.py
git commit -m "feat: wire up impact points display from session data"
```

---

## Task 9: Add Configuration Persistence

**Files:**
- Modify: `stasys_app/base.py` (settings loading/saving)

- [ ] **Step 1: Add default settings for target configuration**

Find where settings are initialized or loaded. Add default values:

```python
        # In settings initialization or load function
        'target_type': '10m_air_pistol',
        'target_view_mode': 'issf',
```

- [ ] **Step 2: Load target settings on startup**

Add to the settings loading section:

```python
        # Load target type from settings
        target_type = loaded_settings.get('target_type', '10m_air_pistol')
        type_key_map = {'10m_air_pistol': 0, '25m_sport_pistol': 1, '50m_free_pistol': 2}
        self.cmb_target_type.setCurrentIndex(type_key_map.get(target_type, 0))

        # Load view mode from settings
        view_mode = loaded_settings.get('target_view_mode', 'issf')
        self.cmb_view_mode.setCurrentIndex(0 if view_mode == 'issf' else 1)

        # Apply to canvas
        if hasattr(self, 'shot_trace_canvas'):
            self.shot_trace_canvas.set_target_type(target_type)
            self.shot_trace_canvas.set_issf_mode(view_mode == 'issf')
```

- [ ] **Step 3: Save target settings on change**

Modify the callback methods to save settings:

```python
    def change_target_type(self, index):
        """Handle target type dropdown change."""
        type_map = {
            0: '10m_air_pistol',
            1: '25m_sport_pistol',
            2: '50m_free_pistol'
        }
        target_key = type_map.get(index, '10m_air_pistol')

        # Save to settings
        self.save_setting('target_type', target_key)

        # Update shot trace canvas if it exists
        if hasattr(self, 'shot_trace_canvas'):
            self.shot_trace_canvas.set_target_type(target_key)
```

```python
    def change_view_mode(self, index):
        """Handle view mode dropdown change."""
        mode = 'issf' if index == 0 else 'simple'

        # Save to settings
        self.save_setting('target_view_mode', mode)

        # Update shot trace canvas if it exists
        if hasattr(self, 'shot_trace_canvas'):
            self.shot_trace_canvas.set_issf_mode(mode == 'issf')
```

- [ ] **Step 4: Commit the persistence code**

```bash
git add stasys_app/base.py
git commit -m "feat: add target settings persistence"
```

---

## Task 10: Verify and Test End-to-End

**Files:**
- None (verification only)

- [ ] **Step 1: Run the application**

```bash
cd stasys_app
python main.py
```

- [ ] **Step 2: Navigate to Settings tab and verify controls**

Check that:
- Target Type dropdown shows all three options
- View Mode dropdown shows ISSF Target and Simple Rings

- [ ] **Step 3: Navigate to Shot Analysis tab and verify ISSF target**

Check that:
- ISSF target displays with proper ring colors (black/white)
- Center crosshair is visible
- Target scales properly with zoom

- [ ] **Step 4: Load a session with shot data and verify impacts**

Check that:
- Shot traces display with phase colors over ISSF target
- Impact points overlay with correct colors
- ISSF score displays in Per-Shot Statistics

- [ ] **Step 5: Switch target types and verify scaling**

Check that:
- Switching between 10m, 25m, 50m targets changes ring sizes
- ISSF scores recalculate correctly for each target type

- [ ] **Step 6: Switch to Simple Rings mode and verify fallback**

Check that:
- Simple rings display correctly
- Shot traces still render
- Functionality is preserved

- [ ] **Step 7: Close and restart to verify persistence**

Check that:
- Last selected target type is remembered
- View mode preference is remembered

- [ ] **Step 8: Commit any fixes from testing**

```bash
git add stasys_app/base.py
git commit -m "fix: address issues found during testing"
```

---

## Task 11: (Optional) Add Unit Tests

**Files:**
- Create: `test/test_issf_target.py`

- [ ] **Step 1: Create test file**

```bash
touch test/test_issf_target.py
```

- [ ] **Step 2: Write scoring tests**

```python
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from stasys_app.base import calculate_issf_score, TARGET_SPECS

def test_issf_scoring_center():
    """Test that center shot gets 10.9"""
    spec = TARGET_SPECS['10m_air_pistol']
    result, ring = calculate_issf_score(0, 0, spec)
    assert result == 10.9, f"Expected 10.9, got {result}"
    assert ring == 10, f"Expected ring 10, got {ring}"

def test_issf_scoring_ten_ring_edge():
    """Test edge of 10-ring (5.75mm radius)"""
    spec = TARGET_SPECS['10m_air_pistol']
    result, ring = calculate_issf_score(0.0575, 0, spec)
    assert abs(result - 10.0) < 0.1, f"Expected ~10.0, got {result}"
    assert ring == 10, f"Expected ring 10, got {ring}"

def test_issf_scoring_miss():
    """Test that shot outside target is a miss"""
    spec = TARGET_SPECS['10m_air_pistol']
    result, ring = calculate_issf_score(9.0, 9.0, spec)
    assert result == 0.0, f"Expected 0.0 for miss, got {result}"
    assert ring == 0, f"Expected ring 0 for miss, got {ring}"

def test_issf_scoring_25m_target():
    """Test scoring with 25m target (different dimensions)"""
    spec = TARGET_SPECS['25m_sport_pistol']
    # Center should still be 10.9
    result, ring = calculate_issf_score(0, 0, spec)
    assert result == 10.9, f"Expected 10.9, got {result}"

if __name__ == '__main__':
    test_issf_scoring_center()
    test_issf_scoring_ten_ring_edge()
    test_issf_scoring_miss()
    test_issf_scoring_25m_target()
    print("All tests passed!")
```

- [ ] **Step 3: Run the tests**

```bash
cd test
python test_issf_target.py
```

Expected: "All tests passed!"

- [ ] **Step 4: Commit the test file**

```bash
git add test/test_issf_target.py
git commit -m "test: add unit tests for ISSF scoring calculation"
```

---

## Verification Checklist

After completing all tasks, verify:

- [ ] Code follows existing style and patterns in base.py
- [ ] All three ISSF target types (10m, 25m, 50m) render correctly
- [ ] ISSF decimal scoring calculates accurately (10.0-10.9 for center)
- [ ] Impact points overlay with correct color coding
- [ ] Both ISSF and stability scores display simultaneously
- [ ] Target type switching works without visual glitches
- [ ] View mode toggle (ISSF/Simple) preserves functionality
- [ ] Settings persist across application restarts
- [ ] Shot trace phases still render correctly over ISSF target
- [ ] Zoom and pan work with ISSF target rendering
- [ ] No crashes or errors in console output

---

## Success Criteria

The implementation is complete when:

1. **ISSF Target Rendering**: Targets display with accurate ring proportions for all three types (10m, 25m, 50m)
2. **Dual Scoring**: Both ISSF decimal score and stability score display for each shot
3. **Impact Visualization**: Shot impacts overlay on target with color coding
4. **User Control**: Users can select target type and view mode from Settings
5. **Persistence**: User preferences are saved and restored
6. **Backward Compatibility**: Simple rings mode still works as before

---

## Post-Implementation Notes

1. **Performance**: ISSF target rendering is lightweight QPainter drawing, no performance impact expected
2. **Memory**: Impact points list should be cleared when switching sessions to avoid memory buildup
3. **Extensibility**: Additional target types can be added by extending TARGET_SPECS dictionary
4. **Database**: Optional future enhancement to store ISSF scores in shot_traces table
5. **Internationalization**: Target names and labels could be localized in future

---

## End of Implementation Plan

**Total Estimated Time**: 2-3 hours for implementation

**Total Commits**: ~11 commits (atomic, well-documented changes)

**Files Modified**: 1 primary file (stasys_app/base.py), 1 optional test file
