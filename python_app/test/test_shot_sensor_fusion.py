"""Tests for the sensor fusion and telemetry buffering refactor.

These tests verify the new shot detection architecture:
- 5-second circular telemetry buffer
- Piezo as primary T0 interrupt (fires immediately)
- Gyro as informational confirmation (doesn't gate the shot)
- Extended time windows: 3s hold, 200ms execution, 1s follow-through
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'stasys_app'))

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

import math
import pytest

from base import (
    ShotDetector,
    DT,
    HOLD_DURATION_IDX,
    PRESS_DURATION_IDX,
    RECOIL_DURATION_IDX,
    HOLD_GAP_BEFORE_BREAK,
    TOTAL_HISTORY_NEEDED,
    SHOT_PHASE_TOTAL,
    TELEMETRY_BUF_SAMPLES,
    GYRO_RECOIL_THRESHOLD,
)


# ─── Helpers ─────────────────────────────────────────────────────────────────

def make_packet(rot=0.0, piezo=0, accel=(0.0, 0.0, 9.81), battery=80,
                mag=(280, -50, -400)):
    """Build a packet tuple: (ax, ay, az, gx, gy, gz, mag_x, mag_y, mag_z,
    piezo, bat)."""
    s = rot / math.sqrt(3.0)
    return (
        accel[0], accel[1], accel[2],
        s, s, s,
        mag[0], mag[1], mag[2],
        piezo, battery,
    )


def calm_packet(rot=0.0):
    """A non-triggering packet that leaves the detector where it is."""
    return make_packet(rot=rot, piezo=0, accel=(0.0, 0.0, 9.81))


def trigger_packet(mode=0, piezo=2000):
    """A packet that triggers piezo or jerk trigger."""
    accel = (500.0, 0.0, 9.81) if mode == 1 else (0.0, 0.0, 9.81)
    return make_packet(rot=0.0, piezo=piezo, accel=accel)


def force_state(detector, state, stable_under_count=10, prime_buffer=False):
    """Put detector in the desired state with optional buffer priming."""
    detector.state = state
    detector._stable_under_count = stable_under_count
    if prime_buffer:
        needed = HOLD_GAP_BEFORE_BREAK + RECOIL_DURATION_IDX + 50
        for _ in range(needed):
            detector.process(calm_packet(rot=0.0))
        detector._stable_under_count = stable_under_count


def drain_post_gather(detector, packet_factory=None, num_samples=None):
    """Drain POST_GATHER to collect shot result."""
    if num_samples is None:
        num_samples = RECOIL_DURATION_IDX + 10
    result = (None,)
    if packet_factory is None:
        packet_factory = calm_packet
    for _ in range(num_samples):
        result = detector.process(packet_factory())
        if result[0] is not None:
            return result
    return result


# ─── Buffer tests ────────────────────────────────────────────────────────────

def test_buffer_size_is_500_samples():
    """Buffer should hold 5 seconds at 100Hz = 500 samples."""
    assert TELEMETRY_BUF_SAMPLES == 500
    det = ShotDetector()
    assert det.buf_size == TELEMETRY_BUF_SAMPLES
    assert hasattr(det, 'telemetry_buf')


def test_telemetry_buf_stores_13_field_tuples():
    """Each entry should be a 13-tuple: 11 raw + 2 aim coords."""
    det = ShotDetector()
    # Process a few calm packets
    for _ in range(5):
        det.process(calm_packet(rot=0.0))
    assert len(det.telemetry_buf) == 5
    for entry in det.telemetry_buf:
        assert len(entry) == 13


def test_telemetry_buf_overflows_correctly():
    """Buffer should maintain maxlen when full."""
    det = ShotDetector()
    n = TELEMETRY_BUF_SAMPLES + 100
    for _ in range(n):
        det.process(calm_packet(rot=0.0))
    assert len(det.telemetry_buf) == TELEMETRY_BUF_SAMPLES


# ─── Time window constants ──────────────────────────────────────────────────

def test_hold_window_is_3s():
    """HOLD_DURATION_IDX should be 300 samples (3.0s @ 100Hz)."""
    assert HOLD_DURATION_IDX == 300


def test_press_window_is_200ms():
    """PRESS_DURATION_IDX should be 20 samples (0.2s @ 100Hz)."""
    assert PRESS_DURATION_IDX == 20


def test_follow_through_window_is_1s():
    """RECOIL_DURATION_IDX should be 100 samples (1.0s @ 100Hz)."""
    assert RECOIL_DURATION_IDX == 100


def test_hold_gap_is_3s():
    """HOLD_GAP_BEFORE_BREAK should be 300 samples (3.0s)."""
    assert HOLD_GAP_BEFORE_BREAK == 300


def test_shot_phase_total():
    """SHOT_PHASE_TOTAL should equal hold + press + follow-through."""
    assert SHOT_PHASE_TOTAL == HOLD_DURATION_IDX + PRESS_DURATION_IDX + RECOIL_DURATION_IDX
    assert SHOT_PHASE_TOTAL == 420


# ─── Piezo fires T0 immediately ─────────────────────────────────────────────

def test_piezo_captures_t0_index():
    """On piezo trigger, last_shot_t0_idx is set to current buffer position."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=10, prime_buffer=True)

    # Trigger
    det.process(trigger_packet(mode=0, piezo=2000))

    # T0 index should be set
    assert det.last_shot_t0_idx >= 0
    assert det.last_shot_t0_idx < len(det.telemetry_buf)


def test_gyro_recoil_is_informational_not_gating():
    """Even with low rotation after piezo, shot still fires."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=10, prime_buffer=True)

    # Trigger with piezo, no gyro recoil (calm packet after trigger)
    det.process(trigger_packet(mode=0, piezo=2000))
    result = drain_post_gather(det)

    # Shot should still be recorded despite no gyro confirmation
    assert result[0] is not None, "Shot should fire even without gyro recoil"
    assert det.state == "COOLDOWN"


def test_gyro_recoil_logged_when_present():
    """When gyro shows recoil, it should be logged as confirmed."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=10, prime_buffer=True)

    # Trigger
    det.process(trigger_packet(mode=0, piezo=2000))

    # Simulate strong gyro motion during POST_GATHER
    for _ in range(5):
        det.process(make_packet(rot=10.0, piezo=0))  # high rotation = recoil

    result = drain_post_gather(det)
    assert result[0] is not None
    assert getattr(det, '_recoil_confirmed', False) is True


# ─── Full shot cycle with telemetry buffer ──────────────────────────────────

def test_analyze_shot_slices_from_telemetry_buf():
    """Full cycle: ARMED -> POST_GATHER -> COOLDOWN yields shot_data
    with correct phase lengths."""
    det = ShotDetector()
    # Prime with enough for hold+press windows. Use only PRESS_DURATION_IDX + 10
    # extra samples so the trigger lands at t0_idx=321, leaving 179 slots for
    # the full RECOIL_DURATION_IDX=100 sample post-trigger drain (total 421 < 500).
    det.state = "ARMED"
    det._stable_under_count = 10
    prime_count = HOLD_GAP_BEFORE_BREAK + PRESS_DURATION_IDX + 10
    for _ in range(prime_count):
        det.process(calm_packet(rot=0.0))
    det._stable_under_count = 10

    det.process(trigger_packet(mode=0, piezo=2000))
    result = drain_post_gather(det)

    assert result[0] is not None
    shot = result[0]

    # Verify phase lengths match new constants
    hold_x, hold_y = shot['hold']
    press_x, press_y = shot['press']
    recoil_x, recoil_y = shot['recoil']

    assert len(hold_x) == HOLD_DURATION_IDX
    # Press range is [t0 - PRESS_DURATION_IDX, t0], so length = PRESS_DURATION_IDX + 1
    assert len(press_x) == PRESS_DURATION_IDX + 1
    assert len(recoil_x) == RECOIL_DURATION_IDX


def test_analyze_shot_normalizes_around_break():
    """Aim traces should be normalized to break point (0, 0)."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=10, prime_buffer=True)

    det.process(trigger_packet(mode=0, piezo=2000))
    result = drain_post_gather(det)

    shot = result[0]
    hold_x, hold_y = shot['hold']
    press_x, press_y = shot['press']
    recoil_x, recoil_y = shot['recoil']

    # Last sample of each phase should be ~0 (normalized to break point)
    assert abs(hold_x[-1]) < 1e-10
    assert abs(hold_y[-1]) < 1e-10
    assert abs(press_x[-1]) < 1e-10
    assert abs(press_y[-1]) < 1e-10
    assert abs(recoil_x[0]) < 1e-10
    assert abs(recoil_y[0]) < 1e-10


def test_analyze_shot_returns_none_without_buffer():
    """analyze_shot should return None if buffer isn't primed."""
    det = ShotDetector()
    # Don't prime buffer, just set state
    force_state(det, "ARMED", stable_under_count=10, prime_buffer=False)

    det.process(trigger_packet(mode=0, piezo=2000))
    result = drain_post_gather(det)

    # analyze_shot should return None because there's not enough history
    # (buffer was not primed)
    assert result[0] is None or det.last_shot_t0_idx < 0


# ─── Sensor fusion roles ────────────────────────────────────────────────────

def test_piezo_is_primary_interrupt():
    """Piezo triggers T0 immediately without needing gyro confirmation."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=10, prime_buffer=True)

    # Trigger with piezo
    det.process(trigger_packet(mode=0, piezo=2000))

    # State should have transitioned to POST_GATHER (not stuck in ARMED)
    assert det.state == "POST_GATHER"
    assert det.last_shot_t0_idx >= 0


def test_jerk_mode_uses_same_t0_capture():
    """In live-fire mode, jerk trigger also captures T0 correctly."""
    det = ShotDetector()
    det.trigger_mode = 1
    det.accel_thresh = 10.0
    force_state(det, "ARMED", stable_under_count=10, prime_buffer=True)

    det.process(trigger_packet(mode=1, piezo=0))
    result = drain_post_gather(det)

    assert result[0] is not None
    assert det.state == "COOLDOWN"


def test_telemetry_buf_contains_raw_and_aim_data():
    """Telemetry buffer should contain both raw sensor data and computed aim."""
    det = ShotDetector()
    # Prime the buffer
    for _ in range(TELEMETRY_BUF_SAMPLES):
        det.process(calm_packet(rot=0.0))

    # Check a few entries
    for entry in list(det.telemetry_buf)[-3:]:
        assert len(entry) == 13
        # Raw fields (0-10)
        assert isinstance(entry[0], float)  # ax
        assert isinstance(entry[3], float)  # gx
        assert isinstance(entry[9], int)    # piezo
        # Computed aim (11-12)
        assert isinstance(entry[11], float)  # curr_x
        assert isinstance(entry[12], float)  # curr_y


def test_process_applies_mag_remapping():
    """ShotDetector.process() must remap magnetometer axes before feeding Mahony."""
    import base as m

    orig = {
        'AX': m.MAG_AXIS_X, 'AY': m.MAG_AXIS_Y, 'AZ': m.MAG_AXIS_Z,
        'SX': m.MAG_SIGN_X, 'SY': m.MAG_SIGN_Y, 'SZ': m.MAG_SIGN_Z,
    }
    det = ShotDetector()
    det.is_calibrated = True
    det.mag_bias = [0.0, 0.0, 0.0]
    det.calibrated_mag_norm = 48000.0
    det.ref_mag_world = [0.0, 1.0, 0.0]

    try:
        # Set non-identity remapping: swap Y↔Z
        m.MAG_AXIS_X, m.MAG_AXIS_Y, m.MAG_AXIS_Z = 0, 2, 1
        m.MAG_SIGN_X, m.MAG_SIGN_Y, m.MAG_SIGN_Z = 1.0, 1.0, 1.0

        # Calibrate with mag along sensor +Y
        cal_samples = [(0.0, 0.0, 9.81, 0.0, 0.0, 0.0, 0, 48000, 0, 0, 80)] * 100
        det.calibrate(cal_samples)

        # Process a packet with mag along sensor +Z
        # With identity: mag=(0,0,48000) → after bias → (0,0,48000) mG
        # With swap Y↔Z: mag becomes (0, 48000, 0) in filter frame
        # This should produce a different aim point than identity
        sample = (0.0, 0.0, 9.81, 0.0, 0.0, 0.0, 0, 0, 48000, 0, 80)
        for _ in range(20):
            det.process(sample)

        # The aim should not be zero — remapping is active
        assert det.curr_x != 0.0 or det.curr_y != 0.0, \
            "Aim should be non-zero with non-identity mag remapping"
    finally:
        m.MAG_AXIS_X, m.MAG_AXIS_Y, m.MAG_AXIS_Z = orig['AX'], orig['AY'], orig['AZ']
        m.MAG_SIGN_X, m.MAG_SIGN_Y, m.MAG_SIGN_Z = orig['SX'], orig['SY'], orig['SZ']
