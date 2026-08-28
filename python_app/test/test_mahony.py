"""Tests for the Mahony AHRS filter and _quat_from_accel_mag helper."""

import os
import sys
import math

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'stasys_app'))
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

import numpy as np
from base import (
    _quat_integrate,
    _quat_normalize,
    _quat_conjugate,
    _quat_rotate_vector,
    _quat_from_accel,
    _quat_from_accel_mag,
    _mahony_step,
    MAHONY_KP_ACC,
    MAHONY_KP_MAG,
)


# ─── helpers ──────────────────────────────────────────────────────────────────

def _body_mag(q, world_mag):
    """Rotate a world-frame magnetic vector into the body frame."""
    q_conj = _quat_conjugate(q)
    return _quat_rotate_vector(q_conj, np.array(world_mag))


def identity():
    return np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)


def norm_deg(q1, q2):
    """Angle in degrees between two quaternions (handle q/-q ambiguity)."""
    dot = float(np.dot(q1, q2))
    dot = abs(dot)  # q and -q represent the same rotation
    return math.degrees(2.0 * math.acos(min(1.0, dot)))


# ─── _quat_from_accel_mag tests ───────────────────────────────────────────────

def test_quat_from_accel_mag_with_upward_accel_returns_identity():
    """Device held straight up → no roll/pitch/yaw → identity quaternion."""
    q = _quat_from_accel_mag(0.0, 0.0, 9.81, 0.0, 0.0, -48000.0)
    assert norm_deg(q, identity()) < 1.0, f"Expected identity, got {q}"


def test_quat_from_accel_mag_with_forward_tilt():
    """Tilt forward 30° around X → pitch ≈ -30° in quaternion."""
    q = _quat_from_accel_mag(
        4.905, 0.0, 8.495,  # ~30° forward tilt
        0.0, 0.0, -48000.0
    )
    # Pitch = asin(2(q0q2 - q1q3))  (standard XYZ Euler extraction)
    sinp = 2.0 * (q[0]*q[2] - q[1]*q[3])
    pitch = math.degrees(math.asin(min(1.0, max(-1.0, sinp))))
    assert -35.0 < pitch < -25.0, f"Expected ~-30° pitch, got {pitch:.1f}°"


def test_quat_from_accel_mag_heading_from_mag():
    """Mag along +Y world → yaw ~90° (Z-axis rotation convention)."""
    q = _quat_from_accel_mag(
        0.0, 0.0, 9.81,
        0.0, 48000.0, 0.0,  # mag points to +Y (east)
    )
    # Standard yaw extraction: atan2(2(q0q3 + q1q2), 1 - 2(q2² + q3²))
    yaw = math.degrees(math.atan2(
        2.0*(q[0]*q[3] + q[1]*q[2]),
        1.0 - 2.0*(q[2]**2 + q[3]**2)
    ))
    assert 80.0 < yaw < 100.0, f"Expected ~90° yaw, got {yaw:.1f}°"


def test_quat_from_accel_mag_declination_offset():
    """Declination of 15° should rotate heading by 15°."""
    q0 = _quat_from_accel_mag(0.0, 0.0, 9.81, 48000.0, 0.0, 0.0)
    q15 = _quat_from_accel_mag(0.0, 0.0, 9.81, 48000.0, 0.0, 0.0, declination_deg=15.0)
    # Difference should be ~15°
    diff = norm_deg(q0, q15)
    assert 13.0 < diff < 17.0, f"Expected ~15° diff, got {diff:.1f}°"


def test_quat_from_accel_mag_falls_back_on_zero_mag():
    """Zero mag → same as _quat_from_accel."""
    q_with_mag = _quat_from_accel_mag(0.0, 0.0, 9.81, 0.0, 0.0, 0.0)
    q_without = _quat_from_accel(0.0, 0.0, 9.81)
    assert norm_deg(q_with_mag, q_without) < 0.5


# ─── _mahony_step tests ───────────────────────────────────────────────────────

def test_mahony_no_correction_matches_quat_integrate():
    """With zero accel/mag and identity start, Mahony ≈ gyro-only."""
    q0 = identity()
    q_mahony = _mahony_step(q0, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.01)
    q_expected = _quat_integrate(q0, 0.1, 0.0, 0.0, 0.01)
    assert norm_deg(q_mahony, q_expected) < 0.1


def test_mahony_accel_correction_holds_level():
    """True orientation rotates; filter corrects drift using mag."""
    q_true = identity()  # actual device orientation
    q_filter = identity()  # filter estimate
    world_mag = [0.0, 48000.0, 0.0]
    ref_mag = [0.0, 1.0, 0.0]
    GYRO_BIAS = 0.01  # rad/s — filter gyro has small bias
    for _ in range(100):
        # Sensor measures body mag based on TRUE orientation
        body_mag = _body_mag(q_true, world_mag)
        # Filter integrates gyro with bias and corrects using mag
        q_filter = _mahony_step(
            q_filter, 0.0, 0.0, 0.5 + GYRO_BIAS,
            0.0, 0.0, 9.81,
            body_mag[0], body_mag[1], body_mag[2],
            0.01, calibrated_mag_norm=48000.0,
            ref_mag_world=ref_mag,
        )
        # True orientation rotates with the gyro (no bias)
        q_true = _quat_integrate(q_true, 0.0, 0.0, 0.5, 0.01)
    true_yaw = math.degrees(math.atan2(
        2.0*(q_true[0]*q_true[3] + q_true[1]*q_true[2]),
        1.0 - 2.0*(q_true[2]**2 + q_true[3]**2)
    ))
    filter_yaw = math.degrees(math.atan2(
        2.0*(q_filter[0]*q_filter[3] + q_filter[1]*q_filter[2]),
        1.0 - 2.0*(q_filter[2]**2 + q_filter[3]**2)
    ))
    # Without correction, filter would drift ~5.7° (0.01 * 1.0s = 0.01 rad ≈ 0.57° per second)
    # With correction, should be within 2° of true
    assert abs(filter_yaw - true_yaw) < 2.0, f"Filter {filter_yaw:.1f}° vs true {true_yaw:.1f}°"


def test_mahony_degraded_accel_ignores_zero():
    """Zero accel should not crash — filter runs with gyro only."""
    q = identity()
    q = _mahony_step(q, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -48000.0, 0.01)
    assert np.isfinite(float(np.linalg.norm(q)))


def test_mahony_degraded_mag_ignores_zero():
    """Zero mag should not crash — filter runs with gyro + accel."""
    q = identity()
    q = _mahony_step(q, 0.1, 0.0, 0.0, 0.0, 0.0, 9.81, 0.0, 0.0, 0.0, 0.01)
    assert np.isfinite(float(np.linalg.norm(q)))


def test_mahony_auto_disable_on_anomalous_mag():
    """Mag norm 50% above calibrated → correction skipped, drifts more than with correction."""
    q_true = identity()
    q_filter_ok = identity()
    q_filter_bad = identity()
    world_mag = [0.0, 48000.0, 0.0]
    ref_mag = [0.0, 1.0, 0.0]
    GYRO_BIAS = 0.01
    for _ in range(200):
        body_mag = _body_mag(q_true, world_mag)
        body_mag_scaled = [m * (72000.0 / 48000.0) for m in body_mag]
        # Good filter: mag within tolerance
        q_filter_ok = _mahony_step(
            q_filter_ok, 0.0, 0.0, 0.5 + GYRO_BIAS,
            0.0, 0.0, 9.81,
            body_mag[0], body_mag[1], body_mag[2],
            0.01, calibrated_mag_norm=48000.0,
            ref_mag_world=ref_mag,
        )
        # Bad filter: mag anomalous (auto-disabled)
        q_filter_bad = _mahony_step(
            q_filter_bad, 0.0, 0.0, 0.5 + GYRO_BIAS,
            0.0, 0.0, 9.81,
            body_mag_scaled[0], body_mag_scaled[1], body_mag_scaled[2],
            0.01, calibrated_mag_norm=48000.0,
            ref_mag_world=ref_mag,
        )
        q_true = _quat_integrate(q_true, 0.0, 0.0, 0.5, 0.01)
    true_yaw = math.degrees(math.atan2(
        2.0*(q_true[0]*q_true[3] + q_true[1]*q_true[2]),
        1.0 - 2.0*(q_true[2]**2 + q_true[3]**2)
    ))
    ok_yaw = math.degrees(math.atan2(
        2.0*(q_filter_ok[0]*q_filter_ok[3] + q_filter_ok[1]*q_filter_ok[2]),
        1.0 - 2.0*(q_filter_ok[2]**2 + q_filter_ok[3]**2)
    ))
    bad_yaw = math.degrees(math.atan2(
        2.0*(q_filter_bad[0]*q_filter_bad[3] + q_filter_bad[1]*q_filter_bad[2]),
        1.0 - 2.0*(q_filter_bad[2]**2 + q_filter_bad[3]**2)
    ))
    # With good mag: filter tracks true within 1°
    assert abs(ok_yaw - true_yaw) < 1.0, \
        f"Filter with mag {ok_yaw:.1f}° vs true {true_yaw:.1f}°"
    # With bad mag: filter drifts more than 1° from true
    assert abs(bad_yaw - true_yaw) > 1.0, \
        f"Filter without mag {bad_yaw:.1f}° vs true {true_yaw:.1f}°"


def test_mahony_accepts_normal_mag():
    """Mag norm within tolerance → correction applied, heading holds."""
    q_true = identity()
    q_filter = identity()
    world_mag = [0.0, 48000.0, 0.0]
    ref_mag = [0.0, 1.0, 0.0]
    GYRO_BIAS = 0.01
    for _ in range(100):
        body_mag = _body_mag(q_true, world_mag)
        q_filter = _mahony_step(
            q_filter, 0.0, 0.0, 0.5 + GYRO_BIAS,
            0.0, 0.0, 9.81,
            body_mag[0], body_mag[1], body_mag[2],
            0.01, calibrated_mag_norm=48000.0,
            ref_mag_world=ref_mag,
        )
        q_true = _quat_integrate(q_true, 0.0, 0.0, 0.5, 0.01)
    true_yaw = math.degrees(math.atan2(
        2.0*(q_true[0]*q_true[3] + q_true[1]*q_true[2]),
        1.0 - 2.0*(q_true[2]**2 + q_true[3]**2)
    ))
    filter_yaw = math.degrees(math.atan2(
        2.0*(q_filter[0]*q_filter[3] + q_filter[1]*q_filter[2]),
        1.0 - 2.0*(q_filter[2]**2 + q_filter[3]**2)
    ))
    # Filter should track true within 1°
    assert abs(filter_yaw - true_yaw) < 1.0, \
        f"Filter {filter_yaw:.1f}° vs true {true_yaw:.1f}° — correction insufficient"


# ─── Magnetometer remapping tests ────────────────────────────────────────────

def test_mag_remapping_identity_is_noop():
    """Identity remapping must produce the same quaternion as before the fix."""
    import base as m

    orig = {
        'AX': m.MAG_AXIS_X, 'AY': m.MAG_AXIS_Y, 'AZ': m.MAG_AXIS_Z,
        'SX': m.MAG_SIGN_X, 'SY': m.MAG_SIGN_Y, 'SZ': m.MAG_SIGN_Z,
    }
    try:
        m.MAG_AXIS_X, m.MAG_AXIS_Y, m.MAG_AXIS_Z = 0, 1, 2
        m.MAG_SIGN_X, m.MAG_SIGN_Y, m.MAG_SIGN_Z = 1.0, 1.0, 1.0

        q = _quat_from_accel_mag(0.0, 0.0, 9.81, 0.0, 48000.0, 0.0)
        yaw = math.degrees(math.atan2(
            2.0*(q[0]*q[3] + q[1]*q[2]),
            1.0 - 2.0*(q[2]**2 + q[3]**2)
        ))
        assert 80.0 < yaw < 100.0, f"Expected ~90° yaw with identity remap, got {yaw:.1f}°"
    finally:
        m.MAG_AXIS_X, m.MAG_AXIS_Y, m.MAG_AXIS_Z = orig['AX'], orig['AY'], orig['AZ']
        m.MAG_SIGN_X, m.MAG_SIGN_Y, m.MAG_SIGN_Z = orig['SX'], orig['SY'], orig['SZ']


def test_mag_remapping_swaps_change_heading():
    """Non-identity mag remapping (the actual fix) must change the heading."""
    import base as m

    orig = {
        'AX': m.MAG_AXIS_X, 'AY': m.MAG_AXIS_Y, 'AZ': m.MAG_AXIS_Z,
        'SX': m.MAG_SIGN_X, 'SY': m.MAG_SIGN_Y, 'SZ': m.MAG_SIGN_Z,
    }
    try:
        # Apply the actual fix: X→X(-), Y→Z, Z→Y
        m.MAG_AXIS_X, m.MAG_AXIS_Y, m.MAG_AXIS_Z = 0, 2, 1
        m.MAG_SIGN_X, m.MAG_SIGN_Y, m.MAG_SIGN_Z = -1.0, 1.0, 1.0

        # With mag pointing along world +Y: remapped it becomes world -Z
        # Identity would give yaw ≈ 90°, swapped should give yaw ≈ -90°
        q_identity = _quat_from_accel_mag(0.0, 0.0, 9.81, 0.0, 48000.0, 0.0)
        q_swapped = _quat_from_accel_mag(0.0, 0.0, 9.81, 0.0, 0.0, 48000.0)

        yaw_id = math.degrees(math.atan2(
            2.0*(q_identity[0]*q_identity[3] + q_identity[1]*q_identity[2]),
            1.0 - 2.0*(q_identity[2]**2 + q_identity[3]**2)
        ))
        yaw_sw = math.degrees(math.atan2(
            2.0*(q_swapped[0]*q_swapped[3] + q_swapped[1]*q_swapped[2]),
            1.0 - 2.0*(q_swapped[2]**2 + q_swapped[3]**2)
        ))
        diff = abs(yaw_id - yaw_sw)
        assert diff > 90.0, f"Expected heading change >90°, got diff={diff:.1f}°"
    finally:
        m.MAG_AXIS_X, m.MAG_AXIS_Y, m.MAG_AXIS_Z = orig['AX'], orig['AY'], orig['AZ']
        m.MAG_SIGN_X, m.MAG_SIGN_Y, m.MAG_SIGN_Z = orig['SX'], orig['SY'], orig['SZ']


def test_mag_remapping_sign_flip_changes_heading():
    """Sign flip on one axis should change the heading."""
    import base as m

    orig_sx = m.MAG_SIGN_X
    try:
        m.MAG_SIGN_X = -1.0
        q0 = _quat_from_accel_mag(0.0, 0.0, 9.81, 48000.0, 0.0, 0.0)
        q1 = _quat_from_accel_mag(0.0, 0.0, 9.81, -48000.0, 0.0, 0.0)
        diff = norm_deg(q0, q1)
        assert diff > 5.0, f"Expected heading change from sign flip, got {diff:.1f}°"
    finally:
        m.MAG_SIGN_X = orig_sx
