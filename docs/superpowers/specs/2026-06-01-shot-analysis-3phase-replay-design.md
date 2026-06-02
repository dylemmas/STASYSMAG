# Shot Analysis — 3-Phase Aim Trace Replay

**Date:** 2026-06-01
**Status:** Approved
**Supersedes / Narrows:** [2026-05-22-shot-analysis-full-trace-playback-design.md](2026-05-22-shot-analysis-full-trace-playback-design.md)

---

## Context

The Shot Analysis tab in STASYS shows the per-shot aim trace via `ShotTraceCanvas` (a custom `QWidget` in `stasys_app/main.py:1723`). Currently:

- The trace is rendered as a **static** plot — all three phases (Hold, Press, Follow-Through) are drawn fully on every `paintEvent`.
- Half-built **playback handler code** exists at `stasys_app/main.py:4013–4099` (`_step_trace`, `_toggle_playback`, `_advance_playback`, `_set_playback_speed`, `_skip_to_start`, `_skip_to_end`, `_on_timeline_changed`, `_get_total_trace_samples`), but the supporting widgets and the `playback_pos` attribute they reference were never instantiated — they would raise `AttributeError` if called.
- The user has asked for a replay feature that animates the aim trace with a moving cursor and full timeline controls (Play/Pause, Step, Skip, Speed, Scrubber).

### Why a new (narrower) spec?

A prior approved spec exists: [2026-05-22-shot-analysis-full-trace-playback-design.md](2026-05-22-shot-analysis-full-trace-playback-design.md). It was a much larger effort that aimed for all 6 phases (1600 samples) and a pyqtgraph-based `MantisTraceWidget` rewrite, plus fixes to DB save, frozen-buffer reconstruction, and `PerShotStatsWidget` key names. The actual codebase never moved in that direction: `ShotTraceCanvas` (custom `QWidget`) is still the rendering widget, only 3 phases are stored, and the playback handlers remain dead code.

This spec implements the **narrow 3-phase replay** the user actually asked for now. It is intentionally scoped to:

- Animate only the **3 currently rendered phases** (Hold, Press, Follow-Through) — total 700 samples ≈ 7 s of replay at 1×.
- Live in the **Shot Analysis tab only** (not Session History).
- Reuse the existing `ShotTraceCanvas` (no pyqtgraph rewrite, no widget replacement).
- **No DB schema changes**, **no `PerShotStatsWidget` key fixes**, **no frozen-buffer reconstruction changes** — those remain tracked by the older spec if/when a fuller effort returns.

This keeps the change small, shippable, and uses the dead code that's already in the file.

---

## Design

### What the user sees

When a shot is selected in the Shot History list (right panel of the Shot Analysis tab):

1. The aim trace loads in `ShotTraceCanvas` (top-left, as today).
2. A new **ReplayBar** appears below the canvas (still in the left panel) with: ⏮ Skip-to-start, ⏪ Step-back, ⏯ Play/Pause, ⏩ Step-forward, ⏭ Skip-to-end, a `QSlider` timeline (0–700), a `QComboBox` speed selector (0.5×, 1×, 2×), and a "Sample N / 700" status label.
3. Clicking **Play** sweeps a vertical yellow cursor from left to right across the trace, revealing Hold (red) → Press (yellow) → Follow-Through (cyan) in time order. The slider and status label track the cursor.
4. Dragging the slider scrubs the cursor; changing speed while playing restarts the timer at the new rate.

When no shot is selected, the ReplayBar is hidden.

### Architecture

Two new pieces of state, one new widget:

1. **`ShotTraceCanvas` gains two attributes** — `playback_pos: int` (0–700) and `replay_mode: bool`. When `replay_mode=True`, `paintEvent` clips each phase's path to samples ≤ `playback_pos` and draws a vertical yellow cursor at the current sample's x-coordinate. When `replay_mode=False`, behavior is identical to today (full paths drawn).
2. **New `ReplayBar(QWidget)`** in `stasys_app/main.py`. Owns a `QTimer` (10 ms base interval; `int(10 / speed)` for 0.5×/1×/2×), the buttons, the `QSlider`, and the speed combo. Exposes Qt signals (`playToggled`, `speedChanged`, `scrubRequested`, `stepRequested`) that `MainWindow` connects to. Knows nothing about the canvas.
3. **`_on_shot_selected` (`main.py:3994`) gets a new tail**: after `set_trace`, it calls a new `MainWindow._load_shot_into_replay(shot)` that resets `playback_pos=0`, sets `replay_mode=True`, shows the `ReplayBar`, and primes it with `total=700`.

### Why this shape

- The dead handlers at `main.py:4013–4099` already encode the right design (sample-by-sample advance, 10 ms base, `int(10/speed)` for 0.5×/1×/2×). Implementing that design against the new `ReplayBar` is the shortest path to a working feature.
- Owning the timer inside `ReplayBar` (not `MainWindow`) keeps the widget self-contained and reusable if a future spec extends it to Session History.
- `playback_pos` lives on the canvas (where the rendering logic is) rather than the bar, so the canvas remains the single source of truth for "what's visible right now."

### Data flow

**Loading a shot for replay:**

1. `_on_shot_selected(item)` (`main.py:3994`) gets the shot dict from `self.shot_history[idx]`.
2. Existing `self.trace_canvas.set_trace(hold=..., press=..., recoil=...)` populates `hol_x/hol_y`, `pre_x/pre_y`, `ft_x/ft_y` on the canvas.
3. New `_load_shot_into_replay(shot)`:
   - `self.trace_canvas.playback_pos = 0`
   - `self.trace_canvas.replay_mode = True`
   - `self.replay_bar.set_total_samples(700)` (300 + 100 + 300, from `HOLD_DURATION_IDX`, `PRESS_DURATION_IDX`, `FOLLOWTHROUGH_DURATION_IDX` at `main.py:122–125`)
   - `self.replay_bar.reset()` (slider to 0, paused, speed 1×)
   - `self.replay_bar.show()` and `self.replay_bar.setEnabled(True)`

**Tick handler (`MainWindow._on_replay_tick`):**

1. Increment `self.trace_canvas.playback_pos` by 1.
2. If `>= 700`: stop timer, set bar to paused state, leave `playback_pos = 700` (cursor at end).
3. `self.replay_bar.set_position(playback_pos)` (slider signal blocked to avoid feedback).
4. `self.trace_canvas.update()`.

**Scrubbing:**

1. User drags `QSlider` → `ReplayBar._on_slider_changed(value)` emits `scrubRequested(value)`.
2. `MainWindow._on_replay_scrub(value)` clamps to `[0, 700]`, sets `playback_pos=value`, pauses timer if active, calls `self.trace_canvas.update()`.

**Speed change:**

1. User picks 0.5×/1×/2× → `ReplayBar._on_speed_changed(speed)` emits `speedChanged(speed)`.
2. `MainWindow._on_replay_speed(speed)` stores it; if timer is active, restarts with `int(10 / speed)` ms.

**Step / Skip:** buttons emit `stepRequested(±1)` / `skipToStart` / `skipToEnd`; `MainWindow` updates `playback_pos` accordingly.

### Canvas rendering changes (`ShotTraceCanvas`)

**New `__init__` attributes:**

```python
self.playback_pos = 0
self.replay_mode = False
self._hold_end  = 0   # set by set_trace: len(self.hol_x)
self._press_end = 0   # set by set_trace: len(self.hol_x) + len(self.pre_x)
self._total     = 0   # set by set_trace: sum of all three phase lengths
```

**Modified `set_trace`** — after the existing assignments:

```python
n_hol = len(self.hol_x)
n_pre = len(self.pre_x)
n_ft  = len(self.ft_x)
self._hold_end  = n_hol
self._press_end = n_hol + n_pre
self._total     = n_hol + n_pre + n_ft
self.playback_pos = 0
self.replay_mode  = True
self.update()
```

**Modified `clear_trace`** — add `self.replay_mode = False; self.playback_pos = 0`.

**Modified `paintEvent`** — clip each phase's `_draw_path` to samples ≤ `playback_pos` when `replay_mode=True`:

```python
pos = self.playback_pos if self.replay_mode else self._total

# Hold
hold_clip = min(pos, self._hold_end)
self._draw_path(painter, self.hol_x[:hold_clip], self.hol_y[:hold_clip], cx, cy, scale,
                QPen(QColor(self.COL_HOLD), 2))

# Press
if pos > self._hold_end:
    press_clip = min(pos - self._hold_end, len(self.pre_x))
    self._draw_path(painter, self.pre_x[:press_clip], self.pre_y[:press_clip], cx, cy, scale,
                    QPen(QColor(self.COL_PRESS), 3))

# Follow-Through
if pos > self._hold_end + n_pre:
    ft_clip = min(pos - self._hold_end - n_pre, len(self.ft_x))
    self._draw_path(painter, self.ft_x[:ft_clip], self.ft_y[:ft_clip], cx, cy, scale,
                    QPen(QColor(self.COL_FT), 2))
```

**Vertical cursor** (drawn only when `replay_mode=True` and `playback_pos < _total`):

Compute the current sample's spatial x: if `pos < _hold_end`, use `hol_x[pos]`; else if `pos < _press_end`, use `pre_x[pos - _hold_end]`; else, use `ft_x[pos - _press_end]`. Draw a vertical line at `cx + x_sample * scale` from `cy - plot_range * scale` to `cy + plot_range * scale` in `#FFEB3B` at 150 alpha, 1.5 px wide.

A small `_current_sample_xy()` helper returns the (x, y) tuple for the current sample, or the last sample's coords if `pos == _total` (so the cursor parks at the end without out-of-range access).

**Bullet impact dot** and **Shot number overlay** — unchanged; always drawn.

### ReplayBar widget

```python
class ReplayBar(QWidget):
    """Play/Pause/Step/Skip/Speed/Scrub controls for ShotTraceCanvas replay."""

    playToggled     = pyqtSignal()           # user clicked Play/Pause
    skipToStart     = pyqtSignal()
    skipToEnd       = pyqtSignal()
    stepRequested   = pyqtSignal(int)        # ±1
    speedChanged    = pyqtSignal(float)      # 0.5 / 1.0 / 2.0
    scrubRequested  = pyqtSignal(int)        # 0..total

    def __init__(self, parent=None):
        super().__init__(parent)
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._on_tick)
        self._total = 700
        self._playing = False
        self._speed = 1.0
        # ... build buttons (⏮ ⏪ ⏯ ⏩ ⏭), QSlider 0..700, QComboBox [0.5×, 1×, 2×], QLabel "N / 700"
        # ... wire internal handlers that emit the signals above
```

Methods on `ReplayBar` for the canvas-side control: `set_total_samples(n)`, `set_position(n)` (blocks slider signals), `set_playing(bool)`, `set_speed(s)`, `reset()`, `stop_timer()` (stops `self._timer`).

### Wiring in `_build_shot_analysis_tab` (`main.py:2806`)

In the `canvas_layout` of the existing `canvas_panel`, after the legend `QHBoxLayout` and before the `self.trace_canvas` line, add a horizontal layout containing the ReplayBar. The ReplayBar starts hidden and disabled; `_load_shot_into_replay` shows it.

```python
# Inside canvas_layout, after legend_layout (line 2871)
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

### Replacing the dead handlers

The 9 dead methods at `main.py:4013–4099` (`_step_trace`, `_step_playback`, `_toggle_playback`, `_advance_playback`, `_set_playback_speed`, `_skip_to_start`, `_skip_to_end`, `_on_timeline_changed`, `_get_total_trace_samples`) are **deleted**. Their behavior is now:

- `_step_trace` / `_step_playback` → handled by `_on_replay_step` (connected to `stepRequested`).
- `_toggle_playback` / `_advance_playback` → handled by `_on_replay_play_toggled` and the bar's internal `_on_tick` (drives `playback_pos` and calls `set_position`).
- `_set_playback_speed` → `_on_replay_speed`.
- `_skip_to_start` / `_skip_to_end` → `_on_replay_skip_start` / `_on_replay_skip_end`.
- `_on_timeline_changed` → `_on_replay_scrub`.
- `_get_total_trace_samples` → not needed; the bar owns `_total` (initialized to 700, updated via `set_total_samples`).

### Files modified

- `stasys_app/main.py` (single file):
  - **Add** `ReplayBar` class (new widget).
  - **Modify** `ShotTraceCanvas` (add 2 attributes, modify `set_trace`/`clear_trace`/`paintEvent`, add `_current_sample_xy` helper).
  - **Modify** `_build_shot_analysis_tab` (instantiate and connect `ReplayBar`).
  - **Modify** `_on_shot_selected` (call `_load_shot_into_replay` after `set_trace`).
  - **Add** `MainWindow._load_shot_into_replay`, `_on_replay_play_toggled`, `_on_replay_skip_start`, `_on_replay_skip_end`, `_on_replay_step`, `_on_replay_speed`, `_on_replay_scrub`.
  - **Delete** dead handlers `_step_trace`, `_step_playback`, `_toggle_playback`, `_advance_playback`, `_set_playback_speed`, `_skip_to_start`, `_skip_to_end`, `_on_timeline_changed`, `_get_total_trace_samples`.

No new files. No new dependencies (uses `QTimer`, `QWidget`, `QPushButton`, `QSlider`, `QComboBox`, `QLabel`, `QHBoxLayout`, `pyqtSignal` — all already imported at `main.py:37` or trivially addable).

### Error handling & edge cases

- **Empty shot data** — `set_trace` already tolerates missing phases. With all three empty, `_total == 0`, the ReplayBar shows in disabled state ("No data" in the status label).
- **Shot replaced while playing** — `_load_shot_into_replay` calls `self.replay_bar.stop_timer()` before resetting the position, so the timer can't fire against the new shot's data mid-reset.
- **App shutdown / tab switch** — the `QTimer` lives on `ReplayBar` (parented to `tab2`). Qt's parent-child cleanup stops it on destruction. Switching tabs does not auto-stop; playback continues in the background. (Acceptable; the timer is lightweight.)
- **Slider feedback loop** — `ReplayBar.set_position(value)` blocks slider signals with `blockSignals(True/False)`.
- **Play-at-end** — `ReplayBar._on_play_clicked` resets `pos` to 0 if at end before starting the timer.
- **Speed change while paused** — stored, takes effect on next Play.
- **Speed change while playing** — timer is restarted at the new interval.
- **Initial state** — ReplayBar is hidden until a shot is selected.
- **Out-of-range positions** — every setter clamps to `[0, _total]`.
- **In-memory vs historical shots** — `shot_history` (in-memory) uses `ft` as the key; loaded JSON from the History tab uses `recoil`. The existing `_on_shot_selected` reads from `self.shot_history`, so the ReplayBar will work for shots fired in the current session. Pre-existing limitation, out of scope.

### Verification

1. Launch: `python stasys_app/main.py` — Shot Analysis tab starts with ReplayBar hidden.
2. Connect ESP32 / load a session, fire or load a shot, click a shot in `list_history`.
3. **Verify** the trace loads, all 3 phases visible, ReplayBar appears with slider at 0/700, Play enabled.
4. Click **Play** — cursor sweeps left-to-right revealing Hold → Press → Follow-Through; slider tracks; at 700, playback pauses with cursor at end.
5. Drag the slider — cursor jumps to the scrub position; trace updates.
6. Switch to 0.5×, observe slower playback. Switch to 2×, observe faster.
7. Click ⏭ — cursor jumps to 700. Click ⏪ a few times — cursor decrements one sample per click.
8. Scroll wheel while cursor is mid-trace — trace and cursor zoom together.
9. Click another shot — bar resets to 0, new trace loads, no stray timer ticks.
10. Edge case: empty `shot_history` on startup — ReplayBar stays hidden.
11. Close the app mid-playback — no errors.

Also confirm the **fixed total sample count** matches the phase constants: `len(hol_x) == 300`, `len(pre_x) == 100`, `len(ft_x) == 300` for a typical shot. The constants at `main.py:122–125` define the expected window and `_extract_shot_phases` slices exactly those ranges. Add a defensive clamp (`min(700, sum)`) in `set_total_samples` to handle any short arrays gracefully.

### Out of scope (deferred to a future spec)

- All 6 phases (Pre-Shot Routine, Approach, Break) — requires DB save fix, canvas color/phase expansion, frozen-buffer reconstruction fix.
- Session History tab replay.
- `MantisTraceWidget` / pyqtgraph-based renderer.
- `PerShotStatsWidget` score key fixes (`preshot_score` → `preshot_routine_score`, `recoil_score` → `followthrough_score`).
- Clickable phase regions on the timeline slider.

These remain tracked by [2026-05-22-shot-analysis-full-trace-playback-design.md](2026-05-22-shot-analysis-full-trace-playback-design.md); this spec does not supersede it.
