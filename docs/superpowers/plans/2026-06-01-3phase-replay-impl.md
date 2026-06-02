# 3-Phase Aim Trace Replay — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a timeline-controlled replay feature to the Shot Analysis tab that animates the 3-phase aim trace (Hold → Press → Follow-Through) with a sweeping vertical cursor, full play/pause/step/skip/speed/scrub controls, and a QSlider timeline.

**Architecture:** Extend `ShotTraceCanvas` with `playback_pos` + `replay_mode` and clip path drawing in `paintEvent`. Add a new self-contained `ReplayBar` widget that owns the QTimer, buttons, slider, and speed combo, and exposes Qt signals to `MainWindow`. Replace 9 dead playback handlers with 6 thin `MainWindow` slots. Single-file change in `stasys_app/main.py`. No new files, no new dependencies.

**Tech Stack:** PyQt5 (already imported at `stasys_app/main.py:32–38`). Unit tests use `pytest` + `pytest-qt` for the new helpers and `ReplayBar`; GUI wiring verified manually.

**Spec:** [docs/superpowers/specs/2026-06-01-shot-analysis-3phase-replay-design.md](../specs/2026-06-01-shot-analysis-3phase-replay-design.md)

---

## File Structure

This plan modifies one file and adds one test file. No new production files (per the spec's "no new files" decision; the spec is intentional about minimizing churn):

- **`stasys_app/main.py`** — add `ReplayBar` class (after `ShotTraceCanvas` at line ~1840); modify `ShotTraceCanvas` (lines 1723–1841) to add `playback_pos`/`replay_mode` and clip drawing; add wiring in `_build_shot_analysis_tab` (lines 2806–2969); modify `_on_shot_selected` (line 3994); add 6 `MainWindow` slots; delete 9 dead handlers (lines 4013–4099).
- **`test/test_replay_helpers.py`** (new) — unit tests for pure logic (phase-offset math, time-interval math, sample-indexing helper) and headless `ReplayBar` interaction via `pytest-qt`.

The codebase has no existing test infrastructure, so the test file scaffolds the minimum needed to verify the helpers and the bar's timer/slider behavior without launching the full GUI.

---

## Task 1: Add canvas attributes and partial-render logic to `ShotTraceCanvas`

**Files:**
- Modify: `stasys_app/main.py:1729–1773` (`ShotTraceCanvas.__init__`, `set_trace`, `clear_trace`)
- Modify: `stasys_app/main.py:1796–1840` (`paintEvent`)
- Test: `test/test_replay_helpers.py` (new)

- [ ] **Step 1: Add the new `__init__` attributes to `ShotTraceCanvas`**

Edit `ShotTraceCanvas.__init__` at `stasys_app/main.py:1729–1743`. Replace the existing body with:

```python
def __init__(self, parent=None):
    super().__init__(parent)
    self.setMinimumSize(400, 400)
    self.hol_x = []
    self.hol_y = []
    self.pre_x = []
    self.pre_y = []
    self.ft_x = []
    self.ft_y = []
    self.score = 0
    self.impact_x_cm = 0.0
    self.impact_y_cm = 0.0
    self.current_shot_idx = 0
    self.scale = 1.0
    self.plot_range = PLOT_RANGE

    # Replay state (set by set_trace / clear_trace)
    self.playback_pos = 0
    self.replay_mode = False
    self._hold_end = 0   # len(hol_x) at time of last set_trace
    self._press_end = 0  # len(hol_x) + len(pre_x)
    self._total = 0      # sum of all three phase lengths
```

- [ ] **Step 2: Modify `set_trace` to populate phase-end indices and enter replay mode**

Edit `set_trace` at `stasys_app/main.py:1750–1760`. Replace the existing body with:

```python
def set_trace(self, hold=None, press=None, ft=None, score=0,
              impact_x_cm=0.0, impact_y_cm=0.0, shot_idx=0):
    """Load trace data for rendering (v3.4 style: hold/press/ft only)."""
    self.hol_x, self.hol_y = (hold if hold else ([], []))
    self.pre_x, self.pre_y = (press if press else ([], []))
    self.ft_x,  self.ft_y  = (ft if ft else ([], []))
    self.score = score
    self.impact_x_cm = impact_x_cm
    self.impact_y_cm = impact_y_cm
    self.current_shot_idx = shot_idx

    # Replay state
    n_hol = len(self.hol_x)
    n_pre = len(self.pre_x)
    n_ft = len(self.ft_x)
    self._hold_end = n_hol
    self._press_end = n_hol + n_pre
    self._total = n_hol + n_pre + n_ft
    self.playback_pos = 0
    self.replay_mode = True
    self.update()
```

- [ ] **Step 3: Modify `clear_trace` to exit replay mode**

Edit `clear_trace` at `stasys_app/main.py:1762–1773`. Replace the existing body with:

```python
def clear_trace(self):
    self.hol_x = []
    self.hol_y = []
    self.pre_x = []
    self.pre_y = []
    self.ft_x = []
    self.ft_y = []
    self.score = 0
    self.impact_x_cm = 0.0
    self.impact_y_cm = 0.0
    self.current_shot_idx = 0
    self.playback_mode = False
    self.playback_pos = 0
    self._hold_end = 0
    self._press_end = 0
    self._total = 0
    self.update()
```

- [ ] **Step 4: Add the `_current_sample_xy` helper**

Add this method to `ShotTraceCanvas` (insert after `wheelEvent` at `main.py:1783`, before `_draw_path` at `main.py:1785`):

```python
def _current_sample_xy(self):
    """Return (x, y) of the sample at playback_pos, or last sample if at end.

    Used to position the vertical replay cursor. Returns (0.0, 0.0) when
    no trace data is loaded.
    """
    pos = self.playback_pos
    if pos < self._hold_end and pos < len(self.hol_x):
        return self.hol_x[pos], self.hol_y[pos]
    offset = pos - self._hold_end
    if pos < self._press_end and offset < len(self.pre_x):
        return self.pre_x[offset], self.pre_y[offset]
    offset = pos - self._press_end
    if 0 <= offset < len(self.ft_x):
        return self.ft_x[offset], self.ft_y[offset]
    # At or past end — return last available sample from whichever phase
    if self.ft_x:
        return self.ft_x[-1], self.ft_y[-1]
    if self.pre_x:
        return self.pre_x[-1], self.pre_y[-1]
    if self.hol_x:
        return self.hol_x[-1], self.hol_y[-1]
    return 0.0, 0.0
```

- [ ] **Step 5: Modify `paintEvent` to clip drawing and render the cursor**

Edit `paintEvent` at `stasys_app/main.py:1796–1840`. Replace the three phase-drawing calls (lines 1815–1825) with clipped versions, and add the cursor drawing at the end. The full new `paintEvent`:

```python
def paintEvent(self, event):
    painter = QPainter(self)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.fillRect(self.rect(), QColor(COLORS['bg_secondary']))

    w, h = self.width(), self.height()
    cx, cy = w // 2, h // 2
    scale = min(w, h) / (2 * self.plot_range) * 0.9 * self.scale

    # Crosshair
    painter.setPen(QPen(QColor('#333333'), 1))
    painter.drawLine(cx - 20, cy, cx + 20, cy)
    painter.drawLine(cx, cy - 20, cx, cy + 20)

    # Phase sample counts for boundary calculations
    n_hol = len(self.hol_x)
    n_pre = len(self.pre_x)
    n_ft = len(self.ft_x)

    # Replay clip: when replay_mode is on, only draw samples up to playback_pos.
    pos = self.playback_pos if self.replay_mode else self._total

    # ── Phase 1: Hold (red) — clipped to playback_pos ─────────────────
    hold_clip = min(pos, self._hold_end)
    self._draw_path(painter, self.hol_x[:hold_clip], self.hol_y[:hold_clip],
                    cx, cy, scale, QPen(QColor(self.COL_HOLD), 2))

    # ── Phase 2: Press (yellow) — clipped to playback_pos ─────────────
    if pos > self._hold_end and n_pre > 0:
        press_clip = min(pos - self._hold_end, n_pre)
        self._draw_path(painter, self.pre_x[:press_clip], self.pre_y[:press_clip],
                        cx, cy, scale, QPen(QColor(self.COL_PRESS), 3))

    # ── Phase 3: Follow-Through (cyan) — clipped to playback_pos ──────
    if pos > self._press_end and n_ft > 0:
        ft_clip = min(pos - self._press_end, n_ft)
        self._draw_path(painter, self.ft_x[:ft_clip], self.ft_y[:ft_clip],
                        cx, cy, scale, QPen(QColor(self.COL_FT), 2))

    # ── Replay cursor (vertical line) ────────────────────────────────
    if self.replay_mode and pos < self._total and self._total > 0:
        sample_x, _ = self._current_sample_xy()
        cursor_px_x = cx + sample_x * scale
        half_height = self.plot_range * scale
        cursor_color = QColor('#FFEB3B')  # amber
        cursor_color.setAlpha(150)
        painter.setPen(QPen(cursor_color, 1.5))
        painter.drawLine(int(cursor_px_x), int(cy - half_height),
                         int(cursor_px_x), int(cy + half_height))

    # ── Bullet impact dot (cyan) ─────────────────────────────────────
    if abs(self.impact_x_cm) > 0.01 or abs(self.impact_y_cm) > 0.01:
        impact_scale = scale / self.plot_range
        imp_pix_x = cx + self.impact_x_cm * 0.01 * impact_scale
        imp_pix_y = cy - self.impact_y_cm * 0.01 * impact_scale
        painter.setBrush(QBrush(QColor('#00E5FF')))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(int(imp_pix_x) - 5, int(imp_pix_y) - 5, 10, 10)

    # ── Shot number overlay (top-left) ──────────────────────────────
    if self.current_shot_idx > 0:
        painter.setPen(QPen(QColor(COLORS['text_secondary'])))
        painter.setFont(QFont("Segoe UI", 14, QFont.Bold))
        painter.drawText(20, 30, f"Shot #{self.current_shot_idx}")
```

- [ ] **Step 6: Verify no import changes are needed**

`QColor`, `QPen`, `QPainter`, `QPainterPath` (via `_draw_path`), `QFont`, `QBrush`, `Qt` are all already imported at `stasys_app/main.py:38`. No new imports.

- [ ] **Step 7: Commit the canvas changes**

```bash
git add stasys_app/main.py
git commit -m "feat(canvas): add playback_pos and replay_mode to ShotTraceCanvas"
```

---

## Task 2: Create the test file and write failing tests for the canvas helpers

**Files:**
- Create: `test/test_replay_helpers.py`

- [ ] **Step 1: Add `pytest` and `pytest-qt` to the project's local venv (if present) or document the manual run**

The repo has no `requirements-dev.txt` and no test setup. Create one:

Create `requirements-dev.txt` at `d:/BASEFW/STASYSESP32/requirements-dev.txt`:

```
pytest>=7.0
pytest-qt>=4.0
```

(If a virtualenv exists at `d:/BASEFW/STASYSESP32/.venv/`, install into it: `pip install -r requirements-dev.txt`. If not, install system-wide: `pip install -r requirements-dev.txt`. Note this in a code comment at the top of the test file.)

- [ ] **Step 2: Create the test file with imports and fixtures**

Create `d:/BASEFW/STASYSESP32/test/test_replay_helpers.py`:

```python
"""Tests for the 3-phase aim trace replay helpers.

These tests target the pure-logic helpers in ShotTraceCanvas
(_current_sample_xy) and ReplayBar. They use pytest-qt to spin up
Qt widgets without showing windows (offscreen platform).

Run: pytest test/test_replay_helpers.py -v

Requires: pip install -r requirements-dev.txt
"""
import os
import sys
import pytest

# Headless Qt for CI / non-display environments
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

# Make stasys_app importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "stasys_app"))

from main import ShotTraceCanvas  # noqa: E402


@pytest.fixture
def canvas():
    """A ShotTraceCanvas with a typical 3-phase trace loaded."""
    c = ShotTraceCanvas()
    # HOLD (300 samples), PRESS (100 samples), FOLLOW-THROUGH (300 samples)
    hold_x = [float(i) * 0.01 for i in range(300)]
    hold_y = [0.0] * 300
    press_x = [3.0 + float(i) * 0.001 for i in range(100)]
    press_y = [0.0] * 100
    ft_x = [3.1 + float(i) * 0.01 for i in range(300)]
    ft_y = [0.0] * 300
    c.set_trace(hold=(hold_x, hold_y), press=(press_x, press_y), ft=(ft_x, ft_y))
    return c


class TestShotTraceCanvasReplay:
    def test_set_trace_enters_replay_mode(self, canvas):
        assert canvas.replay_mode is True
        assert canvas.playback_pos == 0

    def test_set_trace_computes_phase_end_indices(self, canvas):
        assert canvas._hold_end == 300
        assert canvas._press_end == 400
        assert canvas._total == 700

    def test_clear_trace_exits_replay_mode(self, canvas):
        canvas.clear_trace()
        assert canvas.replay_mode is False
        assert canvas.playback_pos == 0
        assert canvas._total == 0

    def test_current_sample_xy_in_hold_phase(self, canvas):
        # pos=0 should be the first hold sample
        x, y = canvas._current_sample_xy()
        assert x == pytest.approx(0.0)
        assert y == 0.0

    def test_current_sample_xy_in_press_phase(self, canvas):
        canvas.playback_pos = 350  # 50 into the press phase
        x, y = canvas._current_sample_xy()
        # press_x[50] = 3.0 + 50 * 0.001 = 3.05
        assert x == pytest.approx(3.05)
        assert y == 0.0

    def test_current_sample_xy_in_ft_phase(self, canvas):
        canvas.playback_pos = 550  # 150 into the ft phase
        x, y = canvas._current_sample_xy()
        # ft_x[150] = 3.1 + 150 * 0.01 = 4.6
        assert x == pytest.approx(4.6)
        assert y == 0.0

    def test_current_sample_xy_at_end_returns_last_sample(self, canvas):
        canvas.playback_pos = 700  # at end
        x, y = canvas._current_sample_xy()
        # ft_x[299] = 3.1 + 299 * 0.01 = 6.09
        assert x == pytest.approx(6.09)
        assert y == 0.0

    def test_current_sample_xy_empty_canvas_returns_zero(self):
        c = ShotTraceCanvas()
        x, y = c._current_sample_xy()
        assert x == 0.0
        assert y == 0.0
```

- [ ] **Step 3: Run the tests and verify they pass**

Run:
```bash
cd d:/BASEFW/STASYSESP32 && pytest test/test_replay_helpers.py -v
```

Expected: 8 tests pass.

If any fail, re-read the corresponding code in `ShotTraceCanvas` and fix the discrepancy before continuing.

- [ ] **Step 4: Commit the test file**

```bash
git add test/test_replay_helpers.py requirements-dev.txt
git commit -m "test: add unit tests for ShotTraceCanvas replay helpers"
```

---

## Task 3: Add the `ReplayBar` class

**Files:**
- Modify: `stasys_app/main.py:1840` (insert after `ShotTraceCanvas.paintEvent`)
- Test: `test/test_replay_helpers.py` (extend)

- [ ] **Step 1: Add `pyqtSignal` to the PyQt5 core import**

Edit `stasys_app/main.py:37`:

```python
from PyQt5.QtCore import QTimer, Qt, QRectF, QPointF, QSize, pyqtSignal
```

- [ ] **Step 2: Insert the `ReplayBar` class after `ShotTraceCanvas`**

Insert at the end of the `ShotTraceCanvas` class (after the `paintEvent` body, before line 1843's blank line and the next class). The exact insertion point is after the last line of `paintEvent` (the `painter.drawText(20, 30, f"Shot #{self.current_shot_idx}")` line).

```python
class ReplayBar(QWidget):
    """Play/Pause/Step/Skip/Speed/Scrub controls for ShotTraceCanvas replay.

    Owns its own QTimer. Knows nothing about the canvas — communicates
    via Qt signals that MainWindow connects to.
    """

    playToggled = pyqtSignal()           # user clicked Play/Pause
    skipToStart = pyqtSignal()
    skipToEnd = pyqtSignal()
    stepRequested = pyqtSignal(int)      # ±1
    speedChanged = pyqtSignal(float)     # 0.5 / 1.0 / 2.0
    scrubRequested = pyqtSignal(int)     # 0..total

    def __init__(self, parent=None):
        super().__init__(parent)
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._on_tick)
        self._total = 700
        self._position = 0
        self._playing = False
        self._speed = 1.0

        # Build controls
        self.btn_skip_start = QPushButton("⏮")
        self.btn_step_back = QPushButton("⏪")
        self.btn_play = QPushButton("⏯")
        self.btn_step_fwd = QPushButton("⏩")
        self.btn_skip_end = QPushButton("⏭")
        self.slider = QSlider(Qt.Horizontal)
        self.slider.setRange(0, self._total)
        self.combo_speed = QComboBox()
        self.combo_speed.addItems(["0.5×", "1×", "2×"])
        self.combo_speed.setCurrentIndex(1)  # default 1×
        self.lbl_position = QLabel("0 / 700")

        # Style buttons
        for btn in [self.btn_skip_start, self.btn_step_back, self.btn_play,
                    self.btn_step_fwd, self.btn_skip_end]:
            btn.setFixedSize(40, 32)
            btn.setCursor(Qt.PointingHandCursor)
            btn.setStyleSheet(f"""
                QPushButton {{
                    background: {COLORS['bg_tertiary']};
                    color: {COLORS['text_primary']};
                    border: 1px solid {COLORS['border']};
                    border-radius: 6px;
                    font-size: 14px;
                }}
                QPushButton:hover {{
                    background: {COLORS['bg_elevated']};
                    border: 1px solid {COLORS['accent_blue']};
                }}
                QPushButton:disabled {{
                    color: {COLORS['text_muted']};
                    background: {COLORS['bg_primary']};
                }}
            """)

        self.slider.setStyleSheet(f"""
            QSlider::groove:horizontal {{
                background: {COLORS['bg_tertiary']};
                height: 6px;
                border-radius: 3px;
            }}
            QSlider::handle:horizontal {{
                background: {COLORS['accent_blue']};
                width: 14px;
                margin: -4px 0;
                border-radius: 7px;
            }}
            QSlider::sub-page:horizontal {{
                background: {COLORS['accent_blue']};
                border-radius: 3px;
            }}
        """)
        self.combo_speed.setFixedWidth(60)
        self.combo_speed.setStyleSheet(f"""
            QComboBox {{
                background: {COLORS['bg_tertiary']};
                color: {COLORS['text_primary']};
                border: 1px solid {COLORS['border']};
                border-radius: 6px;
                padding: 4px 8px;
            }}
        """)
        self.lbl_position.setStyleSheet(
            f"color: {COLORS['text_secondary']}; font-size: 12px; min-width: 70px;"
        )
        self.lbl_position.setAlignment(Qt.AlignCenter)

        # Layout
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 4, 0, 4)
        layout.setSpacing(8)
        layout.addWidget(self.btn_skip_start)
        layout.addWidget(self.btn_step_back)
        layout.addWidget(self.btn_play)
        layout.addWidget(self.btn_step_fwd)
        layout.addWidget(self.btn_skip_end)
        layout.addWidget(self.slider, 1)
        layout.addWidget(self.combo_speed)
        layout.addWidget(self.lbl_position)

        # Wire internal handlers
        self.btn_play.clicked.connect(self._on_play_clicked)
        self.btn_skip_start.clicked.connect(self.skipToStart)
        self.btn_skip_end.clicked.connect(self.skipToEnd)
        self.btn_step_back.clicked.connect(lambda: self.stepRequested.emit(-1))
        self.btn_step_fwd.clicked.connect(lambda: self.stepRequested.emit(1))
        self.slider.valueChanged.connect(self._on_slider_changed)
        self.combo_speed.currentIndexChanged.connect(self._on_speed_changed)

    # ── Public API for MainWindow ──────────────────────────────────────

    def set_total_samples(self, n):
        """Set the timeline length and reset position to 0."""
        n = max(0, min(700, int(n)))  # defensive clamp (spec)
        self._total = n
        self.slider.setRange(0, n)
        self.reset()

    def set_position(self, value):
        """Update the slider without emitting scrubRequested (avoids feedback)."""
        value = max(0, min(self._total, int(value)))
        self._position = value
        self.slider.blockSignals(True)
        self.slider.setValue(value)
        self.slider.blockSignals(False)
        self._update_label()

    def set_playing(self, playing):
        """Update the play/pause icon to reflect the current state."""
        self._playing = bool(playing)
        self.btn_play.setText("⏸" if self._playing else "⏯")

    def set_speed(self, speed):
        """Update the speed combo to reflect the current speed."""
        idx = {0.5: 0, 1.0: 1, 2.0: 2}.get(speed, 1)
        if self.combo_speed.currentIndex() != idx:
            self.combo_speed.setCurrentIndex(idx)

    def reset(self):
        """Reset to position 0, paused, 1× speed."""
        self.stop_timer()
        self.set_position(0)
        self.set_playing(False)
        self.set_speed(1.0)
        self._speed = 1.0

    def stop_timer(self):
        """Stop the internal QTimer if running."""
        if self._timer.isActive():
            self._timer.stop()
        self._playing = False
        self.btn_play.setText("⏯")

    # ── Internal handlers ─────────────────────────────────────────────

    def _on_play_clicked(self):
        # If at end, reset to 0 before playing (play-at-end behavior)
        if self._position >= self._total and self._total > 0:
            self.set_position(0)
        self.playToggled.emit()

    def _on_slider_changed(self, value):
        # User dragged the slider — emit scrub, MainWindow will update canvas
        self._position = value
        self._update_label()
        self.scrubRequested.emit(value)

    def _on_speed_changed(self, index):
        speeds = [0.5, 1.0, 2.0]
        if 0 <= index < len(speeds):
            self._speed = speeds[index]
            self.speedChanged.emit(self._speed)

    def _on_tick(self):
        """Timer callback. Emits a stepRequested(+1) for MainWindow to drive playback_pos."""
        if self._position >= self._total:
            self._timer.stop()
            self._playing = False
            self.btn_play.setText("⏯")
            return
        self.stepRequested.emit(1)

    def _update_label(self):
        self.lbl_position.setText(f"{self._position} / {self._total}")
```

- [ ] **Step 3: Verify imports**

`QSlider`, `QComboBox`, `QPushButton`, `QLabel`, `QHBoxLayout`, `QWidget`, `pyqtSignal`, `QTimer`, `Qt` are all available (`main.py:32–37` covers widgets, `QTimer` and `Qt` at line 37, `pyqtSignal` added in Step 1).

- [ ] **Step 4: Commit the new widget**

```bash
git add stasys_app/main.py
git commit -m "feat(replay): add ReplayBar widget with timer and signals"
```

---

## Task 4: Add tests for `ReplayBar` and verify the timer/scrub logic

**Files:**
- Modify: `test/test_replay_helpers.py`

- [ ] **Step 1: Append `ReplayBar` tests to the test file**

Append to `d:/BASEFW/STASYSESP32/test/test_replay_helpers.py`:

```python
from main import ReplayBar  # noqa: E402


@pytest.fixture
def bar(qtbot):
    b = ReplayBar()
    qtbot.addWidget(b)
    return b


class TestReplayBar:
    def test_initial_state(self, bar):
        assert bar._total == 700
        assert bar._position == 0
        assert bar._speed == 1.0
        assert bar._playing is False
        assert bar.lbl_position.text() == "0 / 700"

    def test_set_total_samples_clamps_to_700(self, bar):
        bar.set_total_samples(1000)
        assert bar._total == 700

    def test_set_total_samples_resets_position(self, bar):
        bar.set_position(50)
        bar.set_total_samples(700)
        assert bar._position == 0

    def test_set_position_clamps_to_range(self, bar):
        bar.set_position(99999)
        assert bar._position == 700
        bar.set_position(-5)
        assert bar._position == 0

    def test_set_position_does_not_emit_scrub(self, qtbot, bar):
        """Position updates from MainWindow should not loop back as scrub signals."""
        with qtbot.assertNotEmitted(bar.scrubRequested):
            bar.set_position(100)
        assert bar.slider.value() == 100

    def test_slider_drag_emits_scrub(self, qtbot, bar):
        with qtbot.waitSignal(bar.scrubRequested, timeout=500) as blocker:
            bar.slider.setValue(250)
        assert blocker.args == [250]

    def test_play_pause_button_emits_play_toggled(self, qtbot, bar):
        with qtbot.waitSignal(bar.playToggled, timeout=500):
            bar.btn_play.click()

    def test_step_buttons_emit_step_requested(self, qtbot, bar):
        with qtbot.waitSignal(bar.stepRequested, timeout=500) as blocker:
            bar.btn_step_fwd.click()
        assert blocker.args == [1]
        with qtbot.waitSignal(bar.stepRequested, timeout=500) as blocker:
            bar.btn_step_back.click()
        assert blocker.args == [-1]

    def test_skip_buttons_emit_signals(self, qtbot, bar):
        with qtbot.waitSignal(bar.skipToStart, timeout=500):
            bar.btn_skip_start.click()
        with qtbot.waitSignal(bar.skipToEnd, timeout=500):
            bar.btn_skip_end.click()

    def test_speed_combo_emits_speed_changed(self, qtbot, bar):
        with qtbot.waitSignal(bar.speedChanged, timeout=500) as blocker:
            bar.combo_speed.setCurrentIndex(0)  # 0.5×
        assert blocker.args == [0.5]
        bar.combo_speed.setCurrentIndex(2)  # 2×
        assert bar._speed == 2.0

    def test_reset_restores_initial_state(self, bar):
        bar.set_position(300)
        bar.combo_speed.setCurrentIndex(0)
        bar.reset()
        assert bar._position == 0
        assert bar._speed == 1.0
        assert bar._playing is False

    def test_stop_timer_stops_active_timer(self, qtbot, bar):
        """Manually start the timer and verify stop_timer halts it."""
        bar._timer.start(10)
        bar.stop_timer()
        assert not bar._timer.isActive()
```

- [ ] **Step 2: Run the full test file**

Run:
```bash
cd d:/BASEFW/STASYSESP32 && pytest test/test_replay_helpers.py -v
```

Expected: All tests pass (8 canvas + 12 bar = 20 tests).

If `pytest-qt` is missing: `pip install pytest-qt`. If the offscreen platform fails, set `QT_QPA_PLATFORM=offscreen` in the shell or as the first line of the test file (already done in Step 2 of Task 2).

- [ ] **Step 3: Commit the bar tests**

```bash
git add test/test_replay_helpers.py
git commit -m "test: add ReplayBar unit tests"
```

---

## Task 5: Wire `ReplayBar` into the Shot Analysis tab and add MainWindow slots

**Files:**
- Modify: `stasys_app/main.py:2848–2871` (`canvas_layout` in `_build_shot_analysis_tab`)
- Modify: `stasys_app/main.py:3994–4011` (`_on_shot_selected`)
- Modify: `stasys_app/main.py:4013–4099` (delete dead handlers; replace with new slots)

- [ ] **Step 1: Add `self.replay_bar` to `canvas_layout` in `_build_shot_analysis_tab`**

Edit `stasys_app/main.py:2871`. After the existing `canvas_layout.addLayout(legend_layout)` line, insert:

```python
        # Replay bar (hidden until a shot is selected)
        self.replay_bar = ReplayBar()
        self.replay_bar.hide()
        self.replay_bar.playToggled.connect(self._on_replay_play_toggled)
        self.replay_bar.skipToStart.connect(self._on_replay_skip_start)
        self.replay_bar.skipToEnd.connect(self._on_replay_skip_end)
        self.replay_bar.stepRequested.connect(self._on_replay_step)
        self.replay_bar.speedChanged.connect(self._on_replay_speed)
        self.replay_bar.scrubRequested.connect(self._on_replay_scrub)
        canvas_layout.addWidget(self.replay_bar)
```

(Indentation matches the surrounding `canvas_layout` block — 8 spaces.)

- [ ] **Step 2: Modify `_on_shot_selected` to call `_load_shot_into_replay`**

Edit `_on_shot_selected` at `stasys_app/main.py:3994–4011`. Replace the existing body with:

```python
    def _on_shot_selected(self, item):
        """Handle shot selection from history list — load trace and stats."""
        idx = self.list_history.row(item)
        if 0 <= idx < len(self.shot_history):
            shot = self.shot_history[idx]

            # Load trace into canvas (3-phase format)
            self.trace_canvas.set_trace(
                hold=shot.get('hold'),
                press=shot.get('press'),
                recoil=shot.get('ft'))
            self.trace_canvas.current_shot_idx = shot.get('shot_number', idx + 1)

            # Populate per-shot stats
            self._per_shot_stats.populate(shot)

            # Update session stats (from all shots)
            self._session_stats.populate(self.shot_history)

            # Load into replay bar
            self._load_shot_into_replay(shot)
```

- [ ] **Step 3: Delete the 9 dead handlers at `main.py:4013–4099`**

Use `Edit` with `replace_all=False` and the exact 9-method block as `old_string`. Delete lines 4013 through 4099 inclusive (the methods `_step_trace`, `_step_playback`, `_toggle_playback`, `_advance_playback`, `_set_playback_speed`, `_skip_to_start`, `_skip_to_end`, `_on_timeline_changed`, `_get_total_trace_samples`).

Verify with a Read of the area that the deletion left the file with the next method (`_on_session_selected` at line 4101) directly following `_on_shot_selected`.

- [ ] **Step 4: Add the 6 new `MainWindow` slots + the load helper**

Insert these 7 methods in `MainWindow` directly after `_on_shot_selected` (which now ends at the `_load_shot_into_replay(shot)` call) and before the next method (formerly `_on_session_selected` at line 4101). The indentation is 4 spaces (class body):

```python
    def _load_shot_into_replay(self, shot):
        """Reset replay state for the newly selected shot."""
        self.replay_bar.stop_timer()
        self.trace_canvas.playback_pos = 0
        self.trace_canvas.replay_mode = True
        self.replay_bar.set_total_samples(700)
        self.replay_bar.reset()
        self.replay_bar.show()
        self.replay_bar.setEnabled(True)

    def _on_replay_play_toggled(self):
        """Start the timer at the current speed if not running, else stop it."""
        if not hasattr(self, 'replay_bar') or not hasattr(self, 'trace_canvas'):
            return
        if self.replay_bar._timer.isActive():
            self.replay_bar.stop_timer()
        else:
            speed = self.replay_bar._speed
            interval = max(1, int(10 / speed))  # 10ms base, scaled by speed
            self.replay_bar._timer.start(interval)
            self.replay_bar._playing = True
            self.replay_bar.btn_play.setText("⏸")

    def _on_replay_skip_start(self):
        if hasattr(self, 'trace_canvas'):
            self.trace_canvas.playback_pos = 0
            self.replay_bar.set_position(0)
            self.replay_bar._timer.stop()
            self.replay_bar._playing = False
            self.replay_bar.btn_play.setText("⏯")
            self.trace_canvas.update()

    def _on_replay_skip_end(self):
        if hasattr(self, 'trace_canvas'):
            self.trace_canvas.playback_pos = self.trace_canvas._total
            self.replay_bar.set_position(self.trace_canvas._total)
            self.replay_bar._timer.stop()
            self.replay_bar._playing = False
            self.replay_bar.btn_play.setText("⏯")
            self.trace_canvas.update()

    def _on_replay_step(self, delta):
        if hasattr(self, 'trace_canvas'):
            new_pos = self.trace_canvas.playback_pos + delta
            new_pos = max(0, min(self.trace_canvas._total, new_pos))
            self.trace_canvas.playback_pos = new_pos
            self.replay_bar.set_position(new_pos)
            self.trace_canvas.update()

    def _on_replay_speed(self, speed):
        """Speed change — if timer is running, restart it at the new interval."""
        if not hasattr(self, 'replay_bar'):
            return
        if self.replay_bar._timer.isActive():
            interval = max(1, int(10 / speed))
            self.replay_bar._timer.start(interval)

    def _on_replay_scrub(self, value):
        """Slider drag — update canvas position; pause if playing."""
        if not hasattr(self, 'trace_canvas'):
            return
        value = max(0, min(self.trace_canvas._total, int(value)))
        self.trace_canvas.playback_pos = value
        if self.replay_bar._timer.isActive():
            self.replay_bar.stop_timer()
        self.trace_canvas.update()
```

Note: The `_on_replay_play_toggled` slot starts the timer directly, but the bar's internal `_on_tick` (which fires every interval) emits `stepRequested(1)`, which routes back to `_on_replay_step` here. That means **playback_pos is driven entirely by `_on_replay_step`**, which keeps the canvas, bar, and label all in sync via `set_position`. This avoids two sources of truth.

- [ ] **Step 5: Verify the file still parses**

Run:
```bash
cd d:/BASEFW/STASYSESP32 && python -c "import ast; ast.parse(open('stasys_app/main.py').read()); print('OK')"
```

Expected output: `OK`. If syntax error, fix the inserted code.

- [ ] **Step 6: Re-run the unit tests to make sure nothing regressed**

Run:
```bash
cd d:/BASEFW/STASYSESP32 && pytest test/test_replay_helpers.py -v
```

Expected: All 20 tests still pass.

- [ ] **Step 7: Commit the wiring**

```bash
git add stasys_app/main.py
git commit -m "feat(replay): wire ReplayBar into Shot Analysis tab"
```

---

## Task 6: Manual end-to-end verification

**Files:** None (verification only).

- [ ] **Step 1: Launch the app**

Run:
```bash
cd d:/BASEFW/STASYSESP32 && python stasys_app/main.py
```

Expected: App launches, Shot Analysis tab visible, ReplayBar is hidden.

- [ ] **Step 2: Populate shot history**

Either connect to the ESP32 and fire a dry-fire click, or load a saved session via the Session History tab. Click a shot in the Shot History list (right panel of Shot Analysis tab).

Expected: Trace loads, ReplayBar appears with slider at 0/700, Play button enabled, position label reads "0 / 700".

- [ ] **Step 3: Play forward**

Click the Play button (⏯). Observe:
- The vertical yellow cursor sweeps left-to-right across the trace.
- The trace is revealed in time order: Hold (red) first, then Press (yellow) joins, then Follow-Through (cyan).
- The slider knob tracks the cursor.
- The position label updates "N / 700" each tick.
- At 700, the icon changes back to ⏯ and the timer stops.

- [ ] **Step 4: Speed change**

Change the speed combo to 0.5×. Click Play. The cursor should move at half speed (~20ms per sample). Switch to 2×. Click Play. Should move at double speed (~5ms per sample).

- [ ] **Step 5: Scrub**

Drag the slider to position 350. The cursor jumps to the middle of the trace. The trace shows Hold (full) + half of Press, no Follow-Through. The timer should NOT restart (slider drag is a one-shot set, not a play trigger).

- [ ] **Step 6: Step / Skip**

Click ⏭ (skip to end). Cursor jumps to 700. Click ⏪ (step back) five times. Cursor moves to 695. Click ⏮ (skip to start). Cursor returns to 0.

- [ ] **Step 7: Switch shots while paused**

Click a different shot in the list. Trace reloads, slider resets to 0, no errors.

- [ ] **Step 8: Zoom with cursor active**

Scroll the wheel over the canvas while a shot is loaded. Trace and cursor zoom together; cursor remains on the correct data sample.

- [ ] **Step 9: Empty history edge case**

Close the app. Relaunch. Without loading any session, switch to Shot Analysis tab. ReplayBar must be hidden (not shown in disabled state).

- [ ] **Step 10: Close mid-playback**

Start playback, then close the app window while the cursor is mid-trace. No Python traceback, no QTimer warnings in stderr.

- [ ] **Step 11: Commit any final tweaks**

If manual verification surfaced any small fix (e.g., a typo in a label, a color that didn't match the spec), commit it:

```bash
git add stasys_app/main.py
git commit -m "fix(replay): address issues from manual verification"
```

---

## Self-Review (run after writing the plan, before final approval)

- [ ] **Spec coverage:** Architecture ✓ Task 1+5; ReplayBar widget ✓ Task 3; data flow ✓ Task 5; canvas rendering changes ✓ Task 1; error handling (empty data, replaced shot, slider feedback, play-at-end, out-of-range) ✓ covered in Tasks 1+3+5; verification ✓ Task 6.
- [ ] **Placeholder scan:** No TBD/TODO. All code blocks are complete. Imports explicit.
- [ ] **Type consistency:** `playback_pos`, `replay_mode`, `_hold_end`, `_press_end`, `_total` — defined in Task 1, used throughout. `_position`, `_total`, `_speed`, `_playing`, `_timer` on `ReplayBar` — defined in Task 3, used in tests and slots. Signals named consistently across `ReplayBar` and `MainWindow` slots.

---

**Plan complete and saved to `docs/superpowers/plans/2026-06-01-3phase-replay-impl.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
