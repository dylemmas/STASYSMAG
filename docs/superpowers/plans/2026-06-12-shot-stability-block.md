# Shot Stability Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block shot detection (piezo or jerk triggers) in ARMED state when device rotation exceeds a configurable threshold, requiring 100 ms of stability before allowing a trigger.

**Architecture:** Track consecutive samples below `rotation_limit` in `ShotDetector`. Gate the existing ARMED trigger logic behind a "stable for 100 ms" check. Add a settings-persisted threshold with a spinbox in the Settings tab.

**Tech Stack:** Python 3, PyQt5, pytest (existing test framework)

---

## File Structure

- **Modify:** `stasys_app/base.py` — Add constant, modify `ShotDetector.__init__` and `ShotDetector.process()`, add Settings tab UI block, add settings load/save handler
- **Create:** `test/test_shot_stability.py` — Unit tests for stability block behavior

---

## Task 1: Add constant for default rotation limit

**Files:**
- Modify: `stasys_app/base.py:70-79` (CONFIGURATION section)

- [ ] **Step 1: Add the constant**

In `stasys_app/base.py`, after the line `STABILITY_GYRO_DISARM_MULT = 3.0` (around line 73), add:

```python
DEFAULT_SHOT_ROTATION_LIMIT = 4.0  # rad/s — max rotation allowed while ARMED for trigger
```

- [ ] **Step 2: Verify the change is in place**

Run: `grep -n "DEFAULT_SHOT_ROTATION_LIMIT" stasys_app/base.py`
Expected: One match showing the new line.

- [ ] **Step 3: Commit**

```bash
git add stasys_app/base.py
git commit -m "feat: add DEFAULT_SHOT_ROTATION_LIMIT constant"
```

---

## Task 2: Add stability tracking attributes to ShotDetector

**Files:**
- Modify: `stasys_app/base.py:844-906` (ShotDetector.__init__)

- [ ] **Step 1: Add the new attributes**

In `ShotDetector.__init__`, after the line `self.accel_bias = [0.0, 0.0, 0.0]` (around line 880), add:

```python
# ── Stability block (rotation-gated shot trigger) ─────────────────────────
self.rotation_limit      = DEFAULT_SHOT_ROTATION_LIMIT
self._stable_below_count = 0
self._stable_below_needed = 10  # 100 ms at 100 Hz
```

- [ ] **Step 2: Verify the change is in place**

Run: `grep -n "rotation_limit" stasys_app/base.py`
Expected: Three matches — the default constant, the attribute, and one more from Task 3.

- [ ] **Step 3: Commit**

```bash
git add stasys_app/base.py
git commit -m "feat: add rotation_limit state to ShotDetector"
```

---

## Task 3: Gate ARMED trigger logic with stability counter

**Files:**
- Modify: `stasys_app/base.py:1059-1084` (ARMED state block in `process()`)

- [ ] **Step 1: Write the failing test**

Create `test/test_shot_stability.py`:

```python
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import math
from stasys_app.base import ShotDetector, GRAVITY_NOMINAL


def _make_packet(ax=0.0, ay=0.0, az=GRAVITY_NOMINAL,
                 gx=0.0, gy=0.0, gz=0.0, piezo=0, bat=80):
    return [ax, ay, az, gx, gy, gz, piezo, bat]


def _force_into_armed(detector, n_samples=20):
    """Drive the detector through IDLE → ARMING → ARMED."""
    for _ in range(n_samples):
        detector.calibrate([_make_packet() for _ in range(100)], source="manual")
    for _ in range(50):
        detector.process(_make_packet())
        if detector.state == "ARMED":
            return
    raise RuntimeError(f"Failed to reach ARMED state, stuck in {detector.state}")


def test_high_rotation_blocks_piezo_trigger():
    """In ARMED state, high rotation should prevent piezo trigger."""
    d = ShotDetector()
    d.rotation_limit = 4.0
    d._stable_below_needed = 5  # shorten for fast test
    d.calibrate([_make_packet() for _ in range(100)], source="manual")
    _force_into_armed(d)

    # 30 consecutive samples with high rotation + piezo spike — no trigger
    for _ in range(30):
        shot, *_ = d.process(_make_packet(gx=8.0, piezo=500))
        assert shot is None, "Should not trigger while rotation > limit"
    assert d.state == "ARMED", f"State should remain ARMED, got {d.state}"


def test_stable_after_100ms_allows_trigger():
    """After 100 ms of low rotation, piezo trigger should fire."""
    d = ShotDetector()
    d.rotation_limit = 4.0
    d._stable_below_needed = 5  # shorten for fast test
    d.calibrate([_make_packet() for _ in range(100)], source="manual")
    _force_into_armed(d)

    # 30 samples of low rotation, with piezo spike at the end
    result = None
    for i in range(30):
        shot, *_ = d.process(_make_packet(gx=0.5, piezo=500 if i == 29 else 0))
        if shot is not None:
            result = shot
            break
    assert result is not None, "Should trigger after stability window clears"


def test_rotation_spike_resets_counter():
    """A single high-rotation sample should reset the stability counter."""
    d = ShotDetector()
    d.rotation_limit = 4.0
    d._stable_below_needed = 5
    d.calibrate([_make_packet() for _ in range(100)], source="manual")
    _force_into_armed(d)

    # Build up counter to 4 (just below threshold of 5)
    for _ in range(4):
        d.process(_make_packet(gx=0.5, piezo=0))
    assert d._stable_below_count == 4

    # One spike resets
    d.process(_make_packet(gx=8.0, piezo=0))
    assert d._stable_below_count == 0

    # 4 more stable samples — still not at threshold
    for _ in range(4):
        d.process(_make_packet(gx=0.5, piezo=0))
    assert d._stable_below_count == 4

    # Piezo now should NOT trigger
    shot, *_ = d.process(_make_packet(gx=0.5, piezo=500))
    assert shot is None, "Should not trigger with only 5 samples (counter at 4+1=5, but the spike reset earlier)"


def test_jerk_mode_also_blocked():
    """In live fire (jerk) mode, high rotation should also block trigger."""
    d = ShotDetector()
    d.trigger_mode = 1
    d.accel_thresh = 8.0
    d.rotation_limit = 4.0
    d._stable_below_needed = 5
    d.calibrate([_make_packet() for _ in range(100)], source="manual")
    _force_into_armed(d)

    # High rotation + high jerk — no trigger
    for _ in range(30):
        # Use huge accel deltas to generate jerk spike
        pkt = _make_packet(ax=20.0, gx=8.0, piezo=0)
        shot, *_ = d.process(pkt)
        assert shot is None, "Jerk trigger should also be blocked by rotation"
    assert d.state == "ARMED"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python -m pytest test/test_shot_stability.py -v`
Expected: FAIL — tests will fail because the stability gate is not yet implemented (shots trigger immediately in ARMED).

- [ ] **Step 3: Implement the gate in process()**

In `stasys_app/base.py`, replace the `elif self.state == "ARMED":` block (around line 1059) with:

```python
        elif self.state == "ARMED":
            triggered = False
            if rot_mag < self.rotation_limit:
                self._stable_below_count += 1
            else:
                self._stable_below_count = 0

            if self._stable_below_count >= self._stable_below_needed:
                if self.trigger_mode == 1:
                    if jerk_mag > (self.accel_thresh * LIVE_FIRE_JERK_MULT):
                        triggered = True
                else:
                    if self.piezo_thresh <= piezo <= PIEZO_MAX_LIMIT:
                        if rot_mag < ARMED_ROT_LIMIT:
                            triggered = True
                        else:
                            logger.debug(
                                "Piezo OK (%d) but rotation too high (%.2f > %.1f)",
                                piezo, rot_mag, ARMED_ROT_LIMIT)
                    elif piezo > 0:
                        logger.debug(
                            "Piezo %d outside range [%.0f, %.0f]",
                            piezo, self.piezo_thresh, PIEZO_MAX_LIMIT)

            if triggered:
                logger.info("SHOT TRIGGERED — Piezo: %d, Rot: %.2f", piezo, rot_mag)
                self.last_trigger_piezo = piezo
                self.state          = "POST_GATHER"
                self.gather_counter = RECOIL_DURATION_IDX
                self._stable_below_count = 0

            if rot_mag > (STABILITY_GYRO_LIMIT * STABILITY_GYRO_DISARM_MULT):
                self.state = "IDLE"
                self._stable_below_count = 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python -m pytest test/test_shot_stability.py -v`
Expected: PASS — all 4 tests pass.

- [ ] **Step 5: Run the full test suite to confirm no regressions**

Run: `python -m pytest test/ -v`
Expected: All tests pass (the existing ISSF/replay/SVG tests should be unaffected).

- [ ] **Step 6: Commit**

```bash
git add stasys_app/base.py test/test_shot_stability.py
git commit -m "feat: gate ARMED shot trigger behind 100ms stability window"
```

---

## Task 4: Add rotation limit to settings load/save

**Files:**
- Modify: `stasys_app/base.py:2803-2821` (`_load_settings` method in MainWindow)

- [ ] **Step 1: Add settings load for rotation limit**

In `MainWindow._load_settings`, after the line `self.cmb_view_mode.setCurrentIndex(view_index)` (around line 2816), add:

```python
        # Load shot rotation limit
        rotation_limit = settings.get('shot_rotation_limit', DEFAULT_SHOT_ROTATION_LIMIT)
        if hasattr(self, 'spin_rotation_limit'):
            self.spin_rotation_limit.setValue(rotation_limit)
        self.detector.rotation_limit = rotation_limit
```

- [ ] **Step 2: Add a settings handler method**

After `_load_settings` (around line 2821), add a new method:

```python
    def change_rotation_limit(self):
        """Handle shot rotation limit spinbox change."""
        value = self.spin_rotation_limit.value()
        self.detector.rotation_limit = value
        settings = load_settings()
        settings['shot_rotation_limit'] = value
        save_settings(settings)
```

- [ ] **Step 3: Verify the changes compile**

Run: `python -c "import ast; ast.parse(open('stasys_app/base.py').read())"`
Expected: No output (successful parse).

- [ ] **Step 4: Commit**

```bash
git add stasys_app/base.py
git commit -m "feat: load/save shot rotation limit from settings"
```

---

## Task 5: Add stability settings UI to Settings tab

**Files:**
- Modify: `stasys_app/base.py:2718-2719` (just before the Exit button in Settings tab)
- Modify: `stasys_app/base.py:2816` (already done in Task 4)

- [ ] **Step 1: Add the spinbox to the Settings tab**

In `_build_settings_tab`, after the view_mode row block (search for `view_row.addWidget(self.cmb_view_mode, 1)` around line 2680) and before the COM Port label, add a new QFrame section:

```python
        # Stability Settings Section
        stability_section = QFrame()
        stability_section.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_secondary']};
                border: 1px solid {COLORS['border']};
                border-radius: 12px;
                padding: 16px;
            }}
        """)
        stability_layout = QVBoxLayout(stability_section)

        stability_title = QLabel("Stability Settings")
        stability_title.setFont(QFont("Segoe UI", 14, QFont.Bold))
        stability_title.setStyleSheet(f"color: {COLORS['accent_good']};")
        stability_layout.addWidget(stability_title)

        # Max Rotation for Trigger
        rot_row = QHBoxLayout()
        rot_lbl = QLabel("Max Rotation for Trigger (rad/s):")
        rot_lbl.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 13px;")
        rot_lbl.setFixedWidth(220)
        rot_row.addWidget(rot_lbl)

        self.spin_rotation_limit = QDoubleSpinBox()
        self.spin_rotation_limit.setRange(1.0, 20.0)
        self.spin_rotation_limit.setSingleStep(0.5)
        self.spin_rotation_limit.setValue(DEFAULT_SHOT_ROTATION_LIMIT)
        self.spin_rotation_limit.setFont(QFont("Segoe UI", 13))
        self.spin_rotation_limit.setStyleSheet(f"""
            QDoubleSpinBox {{
                background: {COLORS['bg_tertiary']};
                color: {COLORS['text_primary']};
                border: 2px solid {COLORS['border']};
                border-radius: 8px;
                padding: 8px 12px;
                font-size: 13px;
            }}
        """)
        self.spin_rotation_limit.valueChanged.connect(self.change_rotation_limit)
        rot_row.addWidget(self.spin_rotation_limit, 1)
        stability_layout.addLayout(rot_row)

        rot_hint = QLabel("Shots won't trigger while rotation exceeds this value. Requires 100ms of stability.")
        rot_hint.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 11px;")
        rot_hint.setWordWrap(True)
        stability_layout.addWidget(rot_hint)

        tab4_layout.addWidget(stability_section)
        tab4_layout.addSpacing(16)
```

Place this BEFORE the existing "tab4_layout.addStretch()" call.

- [ ] **Step 2: Verify the file still parses**

Run: `python -c "import ast; ast.parse(open('stasys_app/base.py').read())"`
Expected: No output (successful parse).

- [ ] **Step 3: Verify the spinbox is created before _load_settings runs**

Look at `MainWindow.__init__`: the call order is `self.init_ui()` (line 2040) → `self._load_settings()` (line 2049). The spinbox is created inside `_build_settings_tab` which is called from `init_ui`, so the order is correct.

- [ ] **Step 4: Run the full test suite**

Run: `python -m pytest test/ -v`
Expected: All tests pass (the UI changes don't affect unit tests, but confirm no syntax error in base.py).

- [ ] **Step 5: Commit**

```bash
git add stasys_app/base.py
git commit -m "feat: add Stability Settings UI with rotation limit spinbox"
```

---

## Task 6: Final integration test

**Files:**
- Modify: None (verification only)

- [ ] **Step 1: Run all tests**

Run: `python -m pytest test/ -v`
Expected: All tests pass.

- [ ] **Step 2: Verify the imports work end-to-end**

Run: `python -c "from stasys_app.base import ShotDetector, DEFAULT_SHOT_ROTATION_LIMIT; d = ShotDetector(); print('rotation_limit:', d.rotation_limit); print('default:', DEFAULT_SHOT_ROTATION_LIMIT)"`
Expected: Output showing `rotation_limit: 4.0` and `default: 4.0`.

- [ ] **Step 3: Verify simulation mode runs without error**

Run: `python -c "
import sys
sys.path.insert(0, 'stasys_app')
from base import ShotDetector
d = ShotDetector()
# Simulate 50 stable samples
for _ in range(50):
    d.process([0.0, 0.0, 9.81, 0.1, 0.0, 0.0, 0, 80])
print('State after stable samples:', d.state)
print('Stability counter:', d._stable_below_count)
"`
Expected: State in ARMED (or progressing toward it), stability counter incrementing.

- [ ] **Step 4: Commit any final tweaks**

```bash
git status
# If clean, no commit needed. If changes exist:
# git add -A
# git commit -m "chore: final integration verification"
```

---

## Self-Review

**Spec coverage:**
- ✅ Config constant (Task 1)
- ✅ ShotDetector attributes (Task 2)
- ✅ ARMED trigger gating with 100ms stability (Task 3)
- ✅ Settings load/save (Task 4)
- ✅ UI spinbox (Task 5)
- ✅ Verification (Task 6)

**Placeholder scan:** No "TODO", "TBD", or vague "add appropriate error handling" — every step has concrete code.

**Type consistency:**
- `self.rotation_limit` — float, defined in Task 2, used in Task 3, persisted in Task 4, exposed in Task 5
- `self._stable_below_count` — int, defined in Task 2, incremented/reset in Task 3
- `self._stable_below_needed` — int (10 = 100ms at 100Hz), defined in Task 2, tested in Task 3
- `DEFAULT_SHOT_ROTATION_LIMIT` — float, defined in Task 1, used in Tasks 2, 4, 5
- `shot_rotation_limit` settings key — string, consistent in Task 4

**Gaps:** None identified.
