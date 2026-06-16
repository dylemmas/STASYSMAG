# Shot Stability Block Design

**Date:** 2026-06-12
**Status:** Draft — pending user approval
**Target file:** `stasys_app/base.py`

## Problem

The shot detector's ARMED state can trigger on piezo/jerk even when the
device is moving too much. The existing ARMED → IDLE disarm threshold
(`STABILITY_GYRO_LIMIT * STABILITY_GYRO_DISARM_MULT = 12.0 rad/s`) is too
permissive — it allows up to 12 rad/s of rotation while still considering the
device "armed". Result: shots can be detected when the gun is still being
swung into position, before the shooter has settled.

## Goal

Block shot detection (piezo or jerk triggers) while the device rotation
exceeds a configurable threshold. Stay in ARMED state so the system remains
ready to trigger the moment the device stabilizes. No UI feedback — silent
blocking.

## Design

### Configuration

Add one new constant near the existing stability constants (around line 73):

```python
DEFAULT_SHOT_ROTATION_LIMIT = 4.0  # rad/s — max rotation allowed for trigger
```

Settings file key: `shot_rotation_limit` (stored in `settings.json`).

### ShotDetector changes

In `ShotDetector.__init__`, add:

```python
self.rotation_limit = DEFAULT_SHOT_ROTATION_LIMIT
self._stable_below_count = 0
self._stable_below_needed = 10  # 100 ms at 100 Hz
```

In `ShotDetector.process()`, inside the ARMED state block (after
`rot_mag` is computed around line 1027), update the smoothing counter and
gate the trigger:

```python
elif self.state == "ARMED":
    triggered = False
    if rot_mag < self.rotation_limit:
        self._stable_below_count += 1
    else:
        self._stable_below_count = 0

    if self._stable_below_count >= self._stable_below_needed:
        # existing trigger logic
        if self.trigger_mode == 1:
            if jerk_mag > (self.accel_thresh * LIVE_FIRE_JERK_MULT):
                triggered = True
        else:
            if self.piezo_thresh <= piezo <= PIEZO_MAX_LIMIT:
                if rot_mag < ARMED_ROT_LIMIT:
                    triggered = True
    # ... rest of ARMED block unchanged
```

When transitioning out of ARMED (to POST_GATHER or back to IDLE), reset
`_stable_below_count = 0` so the next ARMED cycle starts fresh.

### UI changes (Settings tab)

Add a new "Stability Settings" frame to the Settings tab with one
`QDoubleSpinBox`:

- Label: "Max Rotation for Trigger (rad/s)"
- Range: 1.0 – 20.0
- Step: 0.5
- Default: 4.0
- On value change: update `self.detector.rotation_limit` and save to settings.

Wire up in `_load_settings` / a new settings handler.

## What this does NOT change

- The IDLE → ARMING gate (uses existing `STABILITY_GYRO_LIMIT = 4.0`)
- The ARMED → IDLE disarm (uses existing `STABILITY_GYRO_DISARM_MULT = 3.0`)
- The state machine — no new states
- The UI feedback — silent, as requested

## Smoothing rationale

A 100 ms requirement (10 consecutive samples at 100 Hz) prevents a single
spurious high-rotation sample from blocking a legitimate trigger, while
still requiring a brief period of stability before allowing detection.
This matches the existing `STABILITY_WINDOW_MS = 200` for ARMING, but
shorter to keep shot responsiveness.

## Success criteria

1. With `rotation_limit = 4.0`, a device rotating above 4 rad/s while
   ARMED does not trigger a shot even with a piezo spike.
2. After 100 ms of rotation staying below 4 rad/s, the ARMED state
   resumes triggering.
3. The threshold persists across restarts via `settings.json`.
4. Existing trigger/disarm behavior is unchanged when the device is
   already stable.

## Files modified

- `stasys_app/base.py` — `ShotDetector` class, settings handling, Settings tab UI

## Out of scope

- UI feedback when blocked (explicitly excluded by user)
- Mode-specific thresholds (one threshold for both dry and live fire)
- New state in the state machine
- Changes to scoring or analysis logic
