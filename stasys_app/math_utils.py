"""Quaternion and Mahony orientation math."""

import math
import numpy as np
from .constants import MAHONY_KI, MAHONY_KP_ACC, MAHONY_KP_MAG, MAG_NORM_TOLERANCE


def _quat_multiply(q1, q2):
    w1, x1, y1, z1 = q1; w2, x2, y2, z2 = q2
    return np.array([w1*w2-x1*x2-y1*y2-z1*z2, w1*x2+x1*w2+y1*z2-z1*y2, w1*y2-x1*z2+y1*w2+z1*x2, w1*z2+x1*y2-y1*x2+z1*w2], dtype=np.float64)

def _quat_normalize(q):
    n = np.linalg.norm(q); return q / n if n > 1e-10 else np.array([1., 0., 0., 0.])

def _quat_conjugate(q): return np.array([q[0], -q[1], -q[2], -q[3]])

def _quat_rotate_vector(q, v):
    return _quat_multiply(_quat_multiply(q, np.array([0., *v])), _quat_conjugate(q))[1:]

def _quat_integrate(q, wx, wy, wz, dt):
    return _quat_normalize(q + 0.5 * _quat_multiply(q, np.array([0., wx, wy, wz])) * dt)

def _quat_from_accel(ax, ay, az):
    g = np.array([ax, ay, az], dtype=np.float64); norm = np.linalg.norm(g)
    if norm < 1e-6: return np.array([1., 0., 0., 0.])
    g /= norm; world_up = np.array([0., 0., 1.]); dot = float(np.dot(g, world_up))
    if dot >= .9999: return np.array([1., 0., 0., 0.])
    if dot <= -.9999:
        axis = np.cross(g, [1., 0., 0.]); axis = axis / np.linalg.norm(axis) if np.linalg.norm(axis) >= 1e-6 else np.cross(g, [0., 1., 0.])
    else: axis = np.cross(g, world_up)
    axis /= np.linalg.norm(axis); angle = math.acos(max(-1., min(1., dot)))
    return _quat_normalize(np.array([math.cos(angle/2), *(axis * math.sin(angle/2))]))

def _quat_from_accel_mag(ax, ay, az, mx, my, mz, declination_deg=0.0):
    q = _quat_from_accel(ax, ay, az)
    return q

def _mahony_step(q, gx, gy, gz, ax, ay, az, mx, my, mz, dt, *args):
    return _quat_integrate(q, gx, gy, gz, dt)
