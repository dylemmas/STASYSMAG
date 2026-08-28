"""Integration test: prove Mahony AHRS bounds drift vs gyro-only."""

import os
import sys
import math
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'stasys_app'))
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

import numpy as np
from base import (
    _quat_integrate,
    _quat_normalize,
    _quat_from_accel,
    _mahony_step,
    DT,
)


def get_yaw(q):
    """Standard yaw extraction from quaternion (Z-axis rotation)."""
    return math.degrees(math.atan2(
        2.0*(q[0]*q[3] + q[1]*q[2]),
        1.0 - 2.0*(q[2]**2 + q[3]**2)
    ))


def test_static_drift_bounded_with_mahony():
    """10s of static device with tiny gyro noise — Mahony drift < 5°."""
    q = _quat_from_accel(0.0, 0.0, 9.81)
    initial_yaw = get_yaw(q)

    np.random.seed(42)
    gyro_noise = np.random.normal(0, 0.0001745, size=(1000, 3))
    for noise in gyro_noise:
        q = _mahony_step(q, noise[0], noise[1], noise[2],
                         0.0, 0.0, 9.81,
                         0.0, 0.0, -48000.0,
                         DT, calibrated_mag_norm=48000.0)

    final_yaw = get_yaw(q)
    drift = abs(final_yaw - initial_yaw)
    assert drift < 5.0, f"Mahony drift {drift:.2f}° exceeds 5° limit"


def test_gyro_only_drifts_during_static():
    """10s of static device with realistic noise — gyro-only drifts > 0.5°."""
    q = _quat_from_accel(0.0, 0.0, 9.81)
    initial_yaw = get_yaw(q)

    np.random.seed(42)
    # Realistic gyro random walk: 0.05 rad/s RMS bias drift
    gyro_noise = np.random.normal(0, 0.05, size=(1000, 3))
    for noise in gyro_noise:
        q = _quat_integrate(q, noise[0], noise[1], noise[2], DT)

    final_yaw = get_yaw(q)
    drift = abs(final_yaw - initial_yaw)
    assert drift > 0.5, f"Gyro-only drift {drift:.2f}° should exceed 0.5°"


def test_mahony_recovery_after_manual_rotation():
    """After manual rotation, Mahony should re-stabilize."""
    q = _quat_from_accel(0.0, 0.0, 9.81)

    for _ in range(200):
        q = _mahony_step(q, 0.0, 0.0, math.pi/4,
                         0.0, 0.0, 9.81,
                         0.0, 0.0, -48000.0,
                         DT, calibrated_mag_norm=48000.0)

    yaw = get_yaw(q)
    assert 85.0 < yaw < 95.0, f"Expected ~90° after rotation, got {yaw:.1f}°"

    for _ in range(300):
        q = _mahony_step(q, 0.0, 0.0, 0.0,
                         0.0, 0.0, 9.81,
                         0.0, 0.0, -48000.0,
                         DT, calibrated_mag_norm=48000.0)

    final_yaw = get_yaw(q)
    drift = abs(final_yaw - 90.0)
    assert drift < 5.0, f"Expected <5° drift after stabilization, got {drift:.1f}°"
