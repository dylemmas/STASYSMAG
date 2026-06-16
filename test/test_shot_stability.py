"""Tests for the in-arm stability block.

These tests verify the behavior added in Task 4c — a shot can only trigger
once the device has stayed below `rotation_limit` for `_stable_under_needed`
consecutive samples (default 100ms @ 100Hz). One sample over the limit
resets the counter.
"""

import os
import sys
import math

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'stasys_app'))

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

from base import ShotDetector, DEFAULT_SHOT_ROTATION_LIMIT, RECOIL_DURATION_IDX


# ─── helpers ────────────────────────────────────────────────────────────────

def make_packet(rot=0.0, piezo=0, accel=(0.0, 0.0, 9.81), battery=80):
    """Build a packet tuple matching the (ax, ay, az, gx, gy, gz, piezo, bat) shape.

    The accel tuple is left near 1G to avoid disturbing orientation math;
    rot is the desired gyro magnitude, applied equally to all three axes.
    """
    s = rot / math.sqrt(3.0)
    return (
        accel[0], accel[1], accel[2],
        s, s, s,
        piezo, battery,
    )


def force_state(detector, state, state_timer=None, stable_under_count=10):
    """Bypass the IDLE→ARMING→ARMED handshake and put the detector in the
    state we want to test, fully primed as if it had already been stable.

    stable_under_count defaults to `_stable_under_needed` so a single normal
    sample is enough to trip the trigger."""
    detector.state = state
    if state_timer is not None:
        detector.state_timer = state_timer
    detector._stable_under_count = stable_under_count


def calm_packet(rot=0.0):
    """A non-triggering packet that leaves the detector where it is."""
    return make_packet(rot=rot, piezo=0, accel=(0.0, 0.0, 9.81))


def trigger_packet(mode=0, piezo=2000, accel=None):
    """A packet strong enough to fire piezo or jerk trigger.

    Default piezo=2000 is well above DEFAULT_PIEZO_MIN (100) and below
    PIEZO_MAX_LIMIT (4000), so mode 0 trips the piezo threshold cleanly.
    """
    if accel is None:
        accel = (500.0, 0.0, 9.81) if mode == 1 else (0.0, 0.0, 9.81)
    return make_packet(rot=0.0, piezo=piezo, accel=accel)


def drain_post_gather(detector, packet_factory=None, num_samples=None):
    """Pump the detector through the POST_GATHER drain period so that the
    shot result is returned. The detector needs `RECOIL_DURATION_IDX` samples
    of POST_GATHER (gather_counter starts at RECOIL_DURATION_IDX).

    Returns the result tuple when POST_GATHER completes (shot result is set),
    or the last result if no shot was produced. If `num_samples` is None,
    uses RECOIL_DURATION_IDX + 10.
    """
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


# ─── tests ──────────────────────────────────────────────────────────────────

def test_default_rotation_limit_is_four_rad_per_sec():
    """The default value is 4.0 rad/s — matching STABILITY_GYRO_LIMIT."""
    assert DEFAULT_SHOT_ROTATION_LIMIT == 4.0
    det = ShotDetector()
    assert det.rotation_limit == 4.0
    assert det._stable_under_needed == 10
    assert det._stable_under_count == 0


def test_arm_with_rotation_above_limit_does_not_trigger():
    """A strong trigger packet while rotation is above the limit must not fire."""
    det = ShotDetector()
    force_state(det, "ARMED")

    result = det.process(make_packet(rot=10.0, piezo=5000))

    assert result[0] is None, "Shot should NOT trigger with rotation > limit"
    assert det.state == "ARMED", "Should remain ARMED — no disarm on over-limit trigger"


def test_stable_under_counter_resets_on_single_high_rotation_sample():
    """One sample over the limit must reset the smoothing counter."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=9)  # one sample away from triggering

    det.process(make_packet(rot=8.0, piezo=0))  # over limit, not a trigger

    assert det._stable_under_count == 0, "Counter must reset on over-limit sample"


def test_ten_consecutive_calm_samples_allow_trigger():
    """After 100ms (10 samples) of calm, a trigger packet should fire."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=0)

    for _ in range(10):
        result = det.process(calm_packet(rot=0.0))
        assert result[0] is None, "No trigger on calm packet"

    # Counter should now be at threshold
    assert det._stable_under_count == 10

    # Trigger packet on the next sample — transitions to POST_GATHER
    # (returns None until POST_GATHER drains)
    det.process(trigger_packet(mode=0, piezo=2000))
    # Drain POST_GATHER so the shot analysis completes
    result = drain_post_gather(det)
    assert result[0] is not None, "Shot should trigger after 10 calm samples"
    assert "score" in result[0]


def test_already_stable_state_triggers_immediately():
    """A primed ARMED state (counter at threshold) should fire on next trigger packet."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=10)

    det.process(trigger_packet(mode=0))
    result = drain_post_gather(det)

    assert result[0] is not None
    # After drain_post_gather, state is COOLDOWN (POST_GATHER has completed)
    assert det.state == "COOLDOWN", "Should have completed POST_GATHER by now"


def test_intermittent_high_rotation_resets_counter_each_time():
    """High-low-high pattern must keep counter at 0 — never reach threshold."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=0)

    for _ in range(50):
        det.process(calm_packet(rot=0.0))  # calm
        det.process(make_packet(rot=8.0, piezo=0))  # spike — resets counter

    assert det._stable_under_count == 0
    # And it still must not have triggered
    assert det.state == "ARMED"


def test_just_under_limit_samples_count_as_stable():
    """A sample at exactly rotation_limit - epsilon is still 'stable'."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=0)

    just_under = det.rotation_limit - 0.001
    for _ in range(10):
        det.process(calm_packet(rot=just_under))

    assert det._stable_under_count == 10
    # Trigger should fire (drain POST_GATHER to collect the shot result)
    det.process(trigger_packet(mode=0))
    result = drain_post_gather(det)
    assert result[0] is not None


def test_rotation_limit_is_tunable_at_runtime():
    """Changing rotation_limit mid-flight should affect subsequent gating."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=10)

    # With default 4.0, a 5.0 rad/s packet is over the limit
    det.process(make_packet(rot=5.0, piezo=0))
    assert det._stable_under_count == 0

    # Loosen the limit to 6.0
    det.rotation_limit = 6.0
    det._stable_under_count = 10  # re-prime

    det.process(make_packet(rot=5.0, piezo=0))
    # 5.0 < 6.0 — counter should increment, not reset
    assert det._stable_under_count == 11


def test_idle_state_does_not_increment_stability_counter():
    """The counter is a property of ARMED — IDLE state shouldn't touch it."""
    det = ShotDetector()
    det.state = "IDLE"
    det._stable_under_count = 5  # prior value

    det.process(calm_packet(rot=0.0))

    assert det._stable_under_count == 5, "IDLE state must not touch the counter"


def test_high_rotation_disarm_resets_counter():
    """Going from ARMED to IDLE via the disarm path should clear the counter."""
    det = ShotDetector()
    force_state(det, "ARMED", stable_under_count=8)

    # STABILITY_GYRO_DISARM_MULT = 3.0, so > 12.0 rad/s disarms
    det.process(make_packet(rot=15.0, piezo=0))

    assert det.state == "IDLE"
    assert det._stable_under_count == 0


def test_live_fire_jerk_trigger_also_respects_stability_gate():
    """The jerk path (mode 1) must use the same gate as the piezo path."""
    det = ShotDetector()
    det.trigger_mode = 1
    det.accel_thresh = 10.0  # low threshold so the jerk packet trips it
    force_state(det, "ARMED", stable_under_count=0)

    # High rotation — no trigger
    result = det.process(make_packet(rot=8.0, piezo=0, accel=(500.0, 0.0, 9.81)))
    assert result[0] is None
    assert det._stable_under_count == 0

    # Calm for 10 samples
    for _ in range(10):
        det.process(calm_packet(rot=0.0))

    # Now the jerk packet should fire (drain POST_GATHER to collect the shot result)
    det.process(make_packet(rot=0.0, piezo=0, accel=(500.0, 0.0, 9.81)))
    result = drain_post_gather(det)
    assert result[0] is not None
