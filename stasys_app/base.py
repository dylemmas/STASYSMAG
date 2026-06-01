#!/usr/bin/env python3
"""
STASYS Receiver v3.4 - Auth Fix + Piezo Range Fix
Fix summary (v3.3 → v3.4):
  Problem 1 — Auth failing on reconnect
              → flush buffer BEFORE ESP sends READY, then wait 1.5s
              → added debug logging to see exactly what auth receives
              → increased AUTH_TIMEOUT to 12s to match firmware 10s window
  Problem 2 — Piezo always outside range
              → raised PIEZO_MAX_LIMIT from 1000 to 4000
              → raised DEFAULT_PIEZO_MIN from 50 to 100
              → tune DEFAULT_PIEZO_MIN by watching Piezo: telemetry
"""

import sys
import os
import time
import math
import random
import hashlib
import hmac
import string
import struct
import logging
from collections import deque
from dataclasses import dataclass
from typing import List, Tuple
import sqlite3
import json
from datetime import datetime

import numpy as np
import serial
import serial.tools.list_ports
os.environ.setdefault('PYQTGRAPH_QT_LIB', 'PyQt5')
import pyqtgraph as pg
from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout,
    QHBoxLayout, QPushButton, QLabel, QListWidget,
    QComboBox, QDoubleSpinBox, QGridLayout, QFrame,
    QProgressBar, QTabWidget, QSplitter)
from PyQt5.QtCore import QTimer, Qt, pyqtSignal
from PyQt5.QtGui import (
    QColor, QPainter, QPen, QRadialGradient,
    QPainterPath, QFont, QBrush, QPalette)
from PyQt5.QtCore import QRectF

# ================= LOGGING =================
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

# ================= CONFIGURATION =================
BLUETOOTH_COM_PORT = 'COM22'
BAUD_RATE = 115200

SECRET_KEY = os.environ.get(
    'STASYS_SECRET_KEY', '12ebaf10h12fa9123z21sti'
).encode('utf-8')

# Timing & Protocol
PACKET_SIZE         = 30
PACKET_HEADER       = b'\xAA\xBB'
PACKET_FORMAT       = '<ffffffHB'      # ax, ay, az, gx, gy, gz, piezo, bat
PACKET_PAYLOAD_SIZE = struct.calcsize(PACKET_FORMAT)   # 27 bytes
DT                  = 0.01             # 10 ms  (100 Hz firmware)

# Detection
STABILITY_WINDOW_MS        = 200
STABILITY_GYRO_LIMIT       = 4.0
STABILITY_GYRO_DISARM_MULT = 3.0
ARMED_ROT_LIMIT            = 6.0

HOLD_DURATION_IDX    = 150
PRESS_DURATION_IDX   = 30
RECOIL_DURATION_IDX  = 10
TOTAL_HISTORY_NEEDED = HOLD_DURATION_IDX + RECOIL_DURATION_IDX + 10

# --- PIEZO RANGE FIX ---
# Old firmware (~1kHz sampling) produced values 20-50 at idle, 50-200 on dryfire
# New firmware (~20kHz dedicated task) catches the actual spike: 100-3000+
# Raise PIEZO_MAX_LIMIT so real spikes are not rejected
# Tune DEFAULT_PIEZO_MIN by watching Piezo: telemetry at idle — set it
# just above whatever noise floor you see (typically 80-150 with new firmware)
DEFAULT_PIEZO_MIN       = 100         # was 50  — raised for new firmware
PIEZO_MAX_LIMIT         = 4000.0      # was 1000 — raised to accept real spikes

DEFAULT_ACCEL_THRESH    = 8.0
LIVE_FIRE_JERK_MULT     = 1.5
LIVE_FIRE_DEFAULT_JERK  = 15.0
LIVE_FIRE_DEFAULT_PIEZO = 4000

CALIBRATION_SAMPLE_COUNT = 100
MIN_CALIBRATION_SAMPLES  = 10

LIVE_TRACE_LENGTH    = 50
MONITOR_TRACE_LENGTH = 100
COOLDOWN_DURATION    = 0.5
MAX_PACKETS_PER_TICK = 10

SCORE_PENALTY_TRAVEL = 1200.0
SCORE_PENALTY_JERK   = 5000.0

# ── Enhanced Detection (cherry-picked from main.py v4.0) ───────────────────────
DRYFIRE_STABILITY_WINDOW_MS  = 500    # longer stability for dry fire (mode 0)
DRYFIRE_PIEZO_SUSTAINED      = 50     # sustained contact threshold
DRYFIRE_PIEZO_CONFIRM_COUNT  = 5      # consecutive samples for dry fire confirmation
MODE0_TRIGGER_CONFIRM_COUNT  = 5      # mode 0: 5 consecutive samples above thresh
MODE1_TRIGGER_CONFIRM_COUNT  = 3      # mode 1: 3 consecutive samples above jerk thresh
MIN_ARMING_CONFIRM_COUNT     = 10     # must stay in ARMED 100ms before triggering
ARMED_ROT_DISARM_THRESHOLD   = 5.0    # rotation > 5 rad/s resets ARMED → IDLE

# ── Stability Scoring Weights (3-phase: hold/press/recoil) ─────────────────────
WEIGHT_STABILITY_HOLD  = 0.25
WEIGHT_STABILITY_PRESS = 0.40
WEIGHT_STABILITY_FT    = 0.35

# ── Zone Scales (CEP-style scoring) ────────────────────────────────────────────
ZONE_SCALE_STABILITY_HOLD   = 0.005
ZONE_SCALE_STABILITY_PRESS  = 0.008
ZONE_SCALE_STABILITY_RECOIL = 0.015

# ── A2C Error Classification ──────────────────────────────────────────────────
RECOVERY_THRESHOLD       = 0.010    # rad — recovery threshold for follow-through
A2C_ANTICIPATION_THRESH = 0.005    # rad — minimum A2C magnitude to classify
A2C_FLINCH_THRESH       = 0.015    # rad — flinch detection threshold

# ── Target & Impact ────────────────────────────────────────────────────────────
DEFAULT_TARGET_DISTANCE = 10.0     # metres
TRAIL_MOVEMENT_THRESHOLD = 0.0005  # rad — min movement to draw trail segment

# ── Firearm / Training Mode ────────────────────────────────────────────────────
DEFAULT_FIREARM       = 'Pistol'
DEFAULT_TRAINING_MODE = 'Dry Fire'

# --- AUTH TIMING FIX ---
# Increased to 12s to match the firmware's 10s READY broadcast window
# Python needs the extra 2s margin for serial open + buffer flush
AUTH_TIMEOUT          = 12.0          # was 5.0
AUTH_RESPONSE_TIMEOUT = 3.0           # was 2.0
AUTH_CHALLENGE_LENGTH = 16

PLOT_RANGE  = 0.05
RING_RADII  = [0.01, 0.02, 0.03]

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_FILE    = os.path.join(SCRIPT_DIR, 'shooter_data.db')

GRAVITY_NOMINAL   = 9.81
GRAVITY_TOLERANCE = 1.0


# ── MPU6050 GYRO AXIS REMAP ───────────────────────────────────────────────────
GYRO_AXIS_X = 2
GYRO_AXIS_Y = 1
GYRO_AXIS_Z = 0

GYRO_SIGN_X = -1.0
GYRO_SIGN_Y =  1.0
GYRO_SIGN_Z =  1.0

BARREL_VECTOR = np.array([0.0, 0.0, 1.0], dtype=np.float64)

SCREEN_X_SIGN = 1.0
SCREEN_Y_SIGN = 1.0


# ================= ISSF TARGET SPECIFICATIONS =================
@dataclass
class ISSFTargetSpec:
    """ISSF target specification for rendering and scoring."""
    name: str                      # Display name
    distance_m: float              # Target distance in metres
    total_diameter_mm: float       # Outer edge diameter (1-ring)
    ten_ring_diameter_mm: float   # 10-ring outer edge diameter
    inner_ten_mm: float            # 10.9 ring diameter
    ring_count: int = 10           # Number of scoring rings

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

    if distance_mm < target_spec.inner_ten_mm / 2.0:
        # Inside inner-ten zone: calculate decimal score (10.0 to 10.9)
        ring = 10
        # Center = 10.9, outer edge of inner-ten = 10.0
        # inner_ten_mm is diameter, so radius is inner_ten_mm / 2
        inner_ten_radius_mm = target_spec.inner_ten_mm / 2.0
        decimal = 10.9 * (1.0 - (distance_mm / inner_ten_radius_mm)) + 10.0 * (distance_mm / inner_ten_radius_mm)
    elif distance_mm < target_spec.ten_ring_diameter_mm / 2.0:
        # In the 10-ring but outside inner-ten zone
        ring = 10
        decimal = 10.0
    else:
        # Outside 10-ring: calculate which ring
        # At exactly 10-ring edge, we start at ring 9
        distance_from_ten_edge = distance_mm - (target_spec.ten_ring_diameter_mm / 2.0)
        # Add tiny epsilon to handle exact boundary: ceil(0 + epsilon) = 1
        ring = int(10 - math.ceil(max(0, distance_from_ten_edge / ring_spacing) + 1e-9))
        ring = max(1, min(10, ring))
        decimal = float(ring)

    return (round(decimal, 1), ring)


# ================= MANTISX-STYLE COLORS =================
COLORS = {
    'bg_primary':    '#0D0D0D',
    'bg_secondary':  '#1A1A1A',
    'bg_tertiary':   '#252525',
    'bg_card':       '#1E1E1E',
    'bg_elevated':   '#2A2A2A',
    'text_primary':   '#E8E8E8',
    'text_secondary': '#A0A0A0',
    'text_muted':     '#666666',
    'accent_good':   '#00D26A',
    'accent_ok':     '#FFC107',
    'accent_bad':    '#FF5252',
    'accent_blue':   '#2196F3',
    'score_elite':        '#FFD700',
    'score_expert':       '#4CAF50',
    'score_advanced':      '#2196F3',
    'score_intermediate':  '#FF9800',
    'score_beginner':     '#F44336',
    'border':         '#333333',
    'border_active':  '#00D26A',
    'status_idle':    '#555555',
    'status_arming':   '#FF9800',
    'status_armed':    '#00D26A',
    'status_cooldown': '#2196F3',
}

# ================= QUATERNION MATH ===========================================

def _quat_multiply(q1: np.ndarray, q2: np.ndarray) -> np.ndarray:
    w1, x1, y1, z1 = q1
    w2, x2, y2, z2 = q2
    return np.array([
        w1*w2 - x1*x2 - y1*y2 - z1*z2,
        w1*x2 + x1*w2 + y1*z2 - z1*y2,
        w1*y2 - x1*z2 + y1*w2 + z1*x2,
        w1*z2 + x1*y2 - y1*x2 + z1*w2,
    ], dtype=np.float64)


def _quat_normalize(q: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(q)
    return q / n if n > 1e-10 else np.array([1., 0., 0., 0.])


def _quat_conjugate(q: np.ndarray) -> np.ndarray:
    return np.array([q[0], -q[1], -q[2], -q[3]])


def _quat_rotate_vector(q: np.ndarray, v: np.ndarray) -> np.ndarray:
    pure = np.array([0.0, v[0], v[1], v[2]])
    return _quat_multiply(_quat_multiply(q, pure), _quat_conjugate(q))[1:]


def _quat_integrate(q: np.ndarray,
                    wx: float, wy: float, wz: float,
                    dt: float) -> np.ndarray:
    omega_pure = np.array([0.0, wx, wy, wz])
    q_dot = 0.5 * _quat_multiply(q, omega_pure)
    return _quat_normalize(q + q_dot * dt)


def _quat_from_accel(ax: float, ay: float, az: float) -> np.ndarray:
    g = np.array([ax, ay, az], dtype=np.float64)
    norm = np.linalg.norm(g)
    if norm < 1e-6:
        return np.array([1., 0., 0., 0.])
    g = g / norm

    world_up = np.array([0., 0., 1.])
    dot = float(np.dot(g, world_up))

    if dot >= 0.9999:
        return np.array([1., 0., 0., 0.])

    if dot <= -0.9999:
        axis = np.cross(g, np.array([1., 0., 0.]))
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(g, np.array([0., 1., 0.]))
        axis = axis / np.linalg.norm(axis)
        return np.array([0., axis[0], axis[1], axis[2]])

    axis  = np.cross(g, world_up)
    axis  = axis / np.linalg.norm(axis)
    angle = math.acos(np.clip(dot, -1.0, 1.0))
    s = math.sin(angle / 2.0)
    return np.array([math.cos(angle / 2.0),
                     axis[0]*s, axis[1]*s, axis[2]*s])


# ================= MOCK SERIAL =================

class MockSerial:
    def __init__(self):
        self.is_open    = True
        self.in_waiting = 0
        self.buffer     = b""
        self.last_update = time.time()
        self.noise_seed  = 0

    def write(self, data): pass

    def readline(self):
        return b"READY\n"

    def read(self, size):
        if len(self.buffer) >= size:
            ret = self.buffer[:size]
            self.buffer = self.buffer[size:]
            self.in_waiting = len(self.buffer)
            return ret
        return b""

    def update_sim(self):
        now = time.time()
        if now - self.last_update > DT:
            self.last_update = now
            self.noise_seed += 0.1

            gx = random.uniform(-0.1, 0.1)
            gy = math.sin(self.noise_seed * 0.3) * 0.4 + random.uniform(-0.05, 0.05)
            gz = math.sin(self.noise_seed * 0.5) * 0.5 + random.uniform(-0.1, 0.1)

            ax = random.uniform(-0.2, 0.2)
            ay = random.uniform(-0.2, 0.2)
            az = GRAVITY_NOMINAL

            piezo = int(random.uniform(0, 50))
            bat   = 85

            payload = struct.pack(PACKET_FORMAT, ax, ay, az, gx, gy, gz, piezo, bat)
            calc_sum = 0
            for b in payload:
                calc_sum ^= b
            self.buffer    += PACKET_HEADER + payload + bytes([calc_sum])
            self.in_waiting = len(self.buffer)


# ================= DATABASE (cherry-picked from main.py v4.0) =================

def setup_database():
    """Create/upgrade database with sessions, shots, shot_traces, device_calibrations tables."""
    with sqlite3.connect(DB_FILE) as conn:
        # ── shots table (extended from v3.4) ──────────────────────────────────
        cur = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='shots'")
        if cur.fetchone():
            cols = {row[1] for row in conn.execute("PRAGMA table_info(shots)")}
            if cols != {'id', 'timestamp', 'session_id', 'score', 'cant', 'mode'}:
                logger.warning("DB schema mismatch. Recreating shots table.")
                conn.execute("ALTER TABLE shots RENAME TO shots_backup")
                conn.execute('''CREATE TABLE shots (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        timestamp DATETIME, session_id TEXT,
                        score REAL, cant REAL, mode TEXT)''')
                shared = cols & {'id', 'timestamp', 'session_id', 'score', 'cant', 'mode'} - {'id'}
                if shared:
                    col_list = ', '.join(shared)
                    conn.execute(
                        f"INSERT INTO shots({col_list}) SELECT {col_list} FROM shots_backup")
                conn.execute("DROP TABLE shots_backup")
                conn.commit()
        else:
            conn.execute('''CREATE TABLE shots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME, session_id TEXT,
                    score REAL, cant REAL, mode TEXT)''')
            conn.commit()

        # ── sessions table ────────────────────────────────────────────────────
        conn.execute('''CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT UNIQUE NOT NULL,
            start_time DATETIME NOT NULL,
            end_time DATETIME,
            mode TEXT,
            shot_count INTEGER DEFAULT 0)''')

        # ── shot_traces table ─────────────────────────────────────────────────
        conn.execute('''CREATE TABLE IF NOT EXISTS shot_traces (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            shot_number INTEGER NOT NULL,
            timestamp DATETIME NOT NULL,
            score REAL,
            grade TEXT,
            a2c_angle REAL,
            a2c_mag REAL,
            hold_score REAL,
            press_score REAL,
            recoil_score REAL,
            ft_score REAL,
            hold_stability REAL,
            recoil_recovery_ms REAL,
            error_type TEXT,
            error_severity TEXT,
            coaching TEXT,
            impact_x_cm REAL,
            impact_y_cm REAL,
            target_distance REAL,
            piezo_value INTEGER,
            aim_trace TEXT,
            firearm TEXT,
            training_mode TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions(session_id))''')

        conn.commit()

        # ── device_calibrations table ─────────────────────────────────────────
        conn.execute('''CREATE TABLE IF NOT EXISTS device_calibrations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_key TEXT UNIQUE NOT NULL,
            gyro_bias_x REAL,
            gyro_bias_y REAL,
            gyro_bias_z REAL,
            q_w REAL, q_x REAL, q_y REAL, q_z REAL,
            accel_bias_x REAL, accel_bias_y REAL, accel_bias_z REAL,
            calibrated_at TEXT,
            sample_count INTEGER)''')
        conn.commit()


# ── ShotGroupAnalyzer (cherry-picked from main.py) ────────────────────────────

class ShotGroupAnalyzer:
    """Analyzes a session's shot group to produce group statistics."""

    def __init__(self, shots):
        self.shots = shots

    def _mean(self, vals):
        return sum(vals) / len(vals) if vals else 0.0

    def _median(self, vals):
        if not vals:
            return 0.0
        s = sorted(vals)
        n = len(s)
        return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2

    def _std(self, vals):
        if len(vals) < 2:
            return 0.0
        m = self._mean(vals)
        return math.sqrt(sum((v - m) ** 2 for v in vals) / (len(vals) - 1))

    def analyze(self):
        """Compute group statistics. Returns dict or None if < 1 shot."""
        if not self.shots:
            return None

        impact_x = [s.get('impact_x_cm', 0.0) for s in self.shots if s.get('impact_x_cm') is not None]
        impact_y = [s.get('impact_y_cm', 0.0) for s in self.shots if s.get('impact_y_cm') is not None]

        if not impact_x:
            return None

        center_x = self._mean(impact_x)
        center_y = self._mean(impact_y)
        distances = [math.sqrt((ix - center_x) ** 2 + (iy - center_y) ** 2)
                     for ix, iy in zip(impact_x, impact_y)]
        spread_cm = max(distances) if distances else 0.0
        angular_dispersion = self._std(distances) / 10.0 if distances else 0.0

        target_d = DEFAULT_TARGET_DISTANCE
        spread_moa = spread_cm / (target_d * 0.02909) if target_d > 0 else 0.0
        rating = self._rate_group(spread_moa, len(self.shots))

        error_counts = {}
        for s in self.shots:
            err = s.get('error_type', 'NONE')
            if err and err != 'NONE':
                error_counts[err] = error_counts.get(err, 0) + 1

        scores = [s.get('score', 0) for s in self.shots]
        sorted_dist = sorted(distances)
        r_50 = self._median(sorted_dist) if sorted_dist else 0.0
        r_100 = spread_cm

        return {
            'shot_count': len(self.shots),
            'center_x_cm': round(center_x, 2),
            'center_y_cm': round(center_y, 2),
            'spread_cm': round(spread_cm, 2),
            'angular_dispersion_mrad': round(angular_dispersion, 3),
            'spread_moa': round(spread_moa, 2),
            'group_rating': rating,
            'r_50_cm': round(r_50, 2),
            'r_100_cm': round(r_100, 2),
            'error_distribution': error_counts,
            'scores': scores,
        }

    def _rate_group(self, spread_moa, n_shots):
        if n_shots == 0:
            return "N/A"
        if spread_moa < 1.0:
            return "Excellent"
        elif spread_moa < 2.0:
            return "Good"
        elif spread_moa < 4.0:
            return "Fair"
        else:
            return "Poor"


# ── Device Calibration Persistence ────────────────────────────────────────────

def save_device_calibration(device_key, gyro_bias, q, accel_bias, sample_count):
    """Save (upsert) calibration for a device key (COM port)."""
    with sqlite3.connect(DB_FILE) as conn:
        conn.execute('''INSERT OR REPLACE INTO device_calibrations
                        (device_key, gyro_bias_x, gyro_bias_y, gyro_bias_z,
                         q_w, q_x, q_y, q_z,
                         accel_bias_x, accel_bias_y, accel_bias_z,
                         calibrated_at, sample_count)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                     (device_key,
                      gyro_bias[0], gyro_bias[1], gyro_bias[2],
                      q[0], q[1], q[2], q[3],
                      accel_bias[0], accel_bias[1], accel_bias[2],
                      datetime.now().isoformat(), sample_count))
        conn.commit()


def load_device_calibration(device_key):
    """Load saved calibration for a device key, or None if not found."""
    with sqlite3.connect(DB_FILE) as conn:
        conn.row_factory = sqlite3.Row
        row = conn.execute('''SELECT gyro_bias_x, gyro_bias_y, gyro_bias_z,
                                     q_w, q_x, q_y, q_z,
                                     accel_bias_x, accel_bias_y, accel_bias_z,
                                     sample_count
                              FROM device_calibrations WHERE device_key = ?''',
                          (device_key,)).fetchone()
        if row:
            return {
                'gyro_bias': [row['gyro_bias_x'], row['gyro_bias_y'], row['gyro_bias_z']],
                'q': [row['q_w'], row['q_x'], row['q_y'], row['q_z']],
                'accel_bias': [row['accel_bias_x'], row['accel_bias_y'], row['accel_bias_z']],
                'sample_count': row['sample_count'],
            }
        return None


# ── Session Management ─────────────────────────────────────────────────────────

def start_session(session_id, mode):
    """Create a new session in the database."""
    with sqlite3.connect(DB_FILE) as conn:
        conn.execute('''INSERT OR REPLACE INTO sessions
                        (session_id, start_time, mode, shot_count) VALUES (?, ?, ?, 0)''',
                    (session_id, datetime.now(), mode))
        conn.commit()


def end_session(session_id):
    """Mark a session as ended."""
    with sqlite3.connect(DB_FILE) as conn:
        conn.execute('''UPDATE sessions SET end_time = ? WHERE session_id = ?''',
                    (datetime.now(), session_id))
        conn.commit()


def log_shot_trace(session_id, shot_number, score, piezo, aim_trace, mode,
                  grade='', a2c_angle=0.0, a2c_mag=0.0,
                  hold_score=0.0, press_score=0.0, recoil_score=0.0, ft_score=0.0,
                  hold_stability=0.0, recoil_recovery_ms=0.0, error_type='NONE',
                  error_severity='', coaching='',
                  impact_x_cm=0.0, impact_y_cm=0.0, target_distance=DEFAULT_TARGET_DISTANCE,
                  firearm='', training_mode=''):
    """Log a shot with complete 3-phase aim trace data for replay."""
    aim_trace_json = json.dumps(aim_trace)
    with sqlite3.connect(DB_FILE) as conn:
        conn.execute('''INSERT INTO shot_traces
                        (session_id, shot_number, timestamp, score, grade,
                         a2c_angle, a2c_mag, hold_score, press_score,
                         recoil_score, ft_score, hold_stability,
                         recoil_recovery_ms, error_type, error_severity, coaching,
                         impact_x_cm, impact_y_cm, target_distance,
                         piezo_value, aim_trace,
                         firearm, training_mode)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                    (session_id, shot_number, datetime.now(), score, grade,
                     a2c_angle, a2c_mag, hold_score, press_score,
                     recoil_score, ft_score, hold_stability,
                     recoil_recovery_ms, error_type, error_severity, coaching,
                     impact_x_cm, impact_y_cm, target_distance,
                     piezo, aim_trace_json,
                     firearm, training_mode))
        conn.execute('''UPDATE sessions SET shot_count = shot_count + 1
                        WHERE session_id = ?''', (session_id,))
        conn.commit()


def get_session_shots(session_id):
    """Retrieve all shots with traces for a session (for replay)."""
    with sqlite3.connect(DB_FILE) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute('''SELECT shot_number, timestamp, score, grade,
                                      a2c_angle, a2c_mag, hold_score, press_score,
                                      recoil_score, ft_score, hold_stability,
                                      recoil_recovery_ms, error_type, error_severity,
                                      impact_x_cm, impact_y_cm, target_distance,
                                      piezo_value, aim_trace
                                FROM shot_traces WHERE session_id = ? ORDER BY shot_number''',
                           (session_id,)).fetchall()
        shots = []
        for row in rows:
            shots.append({
                'shot_number': row['shot_number'],
                'timestamp': row['timestamp'],
                'score': row['score'],
                'grade': row['grade'] if 'grade' in row.keys() else '',
                'a2c_angle': row['a2c_angle'] if 'a2c_angle' in row.keys() else 0.0,
                'a2c_mag': row['a2c_mag'] if 'a2c_mag' in row.keys() else 0.0,
                'hold_score': row['hold_score'] if 'hold_score' in row.keys() else 0.0,
                'press_score': row['press_score'] if 'press_score' in row.keys() else 0.0,
                'recoil_score': row['recoil_score'] if 'recoil_score' in row.keys() else 0.0,
                'ft_score': row['ft_score'] if 'ft_score' in row.keys() else 0.0,
                'hold_stability': row['hold_stability'] if 'hold_stability' in row.keys() else 0.0,
                'recoil_recovery_ms': row['recoil_recovery_ms'] if 'recoil_recovery_ms' in row.keys() else 0.0,
                'error_type': row['error_type'] if 'error_type' in row.keys() else 'NONE',
                'error_severity': row['error_severity'] if 'error_severity' in row.keys() else '',
                'impact_x_cm': row['impact_x_cm'] if 'impact_x_cm' in row.keys() else 0.0,
                'impact_y_cm': row['impact_y_cm'] if 'impact_y_cm' in row.keys() else 0.0,
                'target_distance': row['target_distance'] if 'target_distance' in row.keys() else DEFAULT_TARGET_DISTANCE,
                'piezo_value': row['piezo_value'],
                'aim_trace': json.loads(row['aim_trace']) if row['aim_trace'] else None
            })
        return shots


def get_all_sessions():
    """Get list of all sessions for session browser."""
    with sqlite3.connect(DB_FILE) as conn:
        conn.row_factory = sqlite3.Row
        return conn.execute('''SELECT session_id, start_time, end_time, mode, shot_count
                               FROM sessions ORDER BY start_time DESC''').fetchall()


# ── Legacy shot logger (kept for backward compatibility) ───────────────────────

def log_shot_db(session_id, score, cant, mode):
    with sqlite3.connect(DB_FILE) as conn:
        conn.execute(
            'INSERT INTO shots(timestamp,session_id,score,cant,mode) VALUES(?,?,?,?,?)',
            (datetime.now(), session_id, score, cant, mode))
        conn.commit()


# ================= PACKET PARSING =================

def parse_binary_packet(ser):
    try:
        while ser.in_waiting >= PACKET_SIZE:
            b1 = ser.read(1)
            if b1 != PACKET_HEADER[0:1]:
                continue
            b2 = ser.read(1)
            if b2 != PACKET_HEADER[1:2]:
                continue
            raw_payload = ser.read(PACKET_PAYLOAD_SIZE + 1)
            if len(raw_payload) != PACKET_PAYLOAD_SIZE + 1:
                return None
            received_checksum = raw_payload[-1]
            data = raw_payload[:-1]
            calc_sum = 0
            for b in data:
                calc_sum ^= b
            if calc_sum != received_checksum:
                logger.warning("Checksum mismatch, re-syncing stream")
                continue
            return list(struct.unpack(PACKET_FORMAT, data))
    except Exception:
        logger.exception("Error parsing binary packet")
    return None


# ================= AUTHENTICATION =================

def perform_auth(ser):
    """
    Auth fix v3.4:
    - Flush the serial buffer FIRST (before ESP sends READY)
    - Wait 1.5s so the ESP has time to broadcast its first READY
    - Then listen for up to AUTH_TIMEOUT seconds
    - The firmware now sends READY every 500ms, so we can't miss it
    - Added debug logging so you can see exactly what arrives
    """
    if hasattr(ser, 'update_sim'):
        return True

    logger.info("Handshaking — flushing buffer and waiting for READY...")
    try:
        # Step 1: Flush any stale bytes from previous session
        ser.reset_input_buffer()

        # Step 2: Wait for ESP to send its first READY broadcast
        # Firmware waits 0ms then starts sending READY every 500ms,
        # so 1.5s gives us 2-3 chances before we even start reading
        time.sleep(1.5)

        start = time.time()
        while time.time() - start < AUTH_TIMEOUT:
            if ser.in_waiting:
                line = ser.readline().decode('utf-8', errors='ignore').strip()
                logger.debug("[AUTH] RX: %r", line)   # shows every line received

                if "READY" in line:
                    logger.info("[AUTH] Got READY — sending challenge")
                    challenge = ''.join(
                        random.choices(string.ascii_letters + string.digits,
                                       k=AUTH_CHALLENGE_LENGTH))
                    ser.write(f"{challenge}\n".encode('utf-8'))
                    logger.debug("[AUTH] Challenge sent: %s", challenge)

                    st = time.time()
                    while time.time() - st < AUTH_RESPONSE_TIMEOUT:
                        if ser.in_waiting:
                            resp = ser.readline().decode('utf-8', errors='ignore').strip()
                            logger.debug("[AUTH] Response RX: %r", resp)

                            # Skip if we accidentally read another READY
                            if not resp or resp.upper() == "READY":
                                continue

                            expected = hashlib.sha256(
                                (challenge + SECRET_KEY.decode('utf-8')).encode()
                            ).hexdigest()

                            if hmac.compare_digest(resp.lower(), expected.lower()):
                                logger.info("[AUTH] Success!")
                                return True

                            logger.warning("[AUTH] Hash mismatch — got: %r", resp)
                            logger.warning("[AUTH] Expected:           %r", expected)
                        time.sleep(0.01)

                    logger.warning("[AUTH] No valid response within %.1fs", AUTH_RESPONSE_TIMEOUT)

            time.sleep(0.05)

        logger.error("[AUTH] Timed out after %.1fs", AUTH_TIMEOUT)

    except Exception:
        logger.exception("Authentication error")
    return False


# ================= CORE LOGIC =================

class ShotDetector:
    def __init__(self):
        self.accel_thresh = DEFAULT_ACCEL_THRESH
        self.piezo_thresh = DEFAULT_PIEZO_MIN
        self.trigger_mode = 0

        self.is_calibrated = False
        self.gyro_bias     = [0.0, 0.0, 0.0]

        self.q      = np.array([1., 0., 0., 0.], dtype=np.float64)
        self.q_tare = np.array([1., 0., 0., 0.], dtype=np.float64)

        self.state              = "IDLE"
        self.state_timer        = 0.0
        self.gather_counter     = 0
        self.last_trigger_piezo = 0

        # ── Enhanced detection (cherry-picked from main.py) ─────────────────
        self.armed_sample_count    = 0
        self.piezo_sustained_count = 0
        self.jerk_sustained_count  = 0
        self.pending_trigger       = False
        self.trigger_confirm_count = 0

        # ── Instant result cache ────────────────────────────────────────────
        self.pending_shot_result    = None
        self.shot_result_returned   = False
        self.last_trigger_piezo_for_result = 0

        # ── Frozen buffer for 3-phase extraction ────────────────────────────
        self.is_recording     = True
        self.frozen_trace_x   = None
        self.frozen_trace_y   = None
        self.frozen_trigger_idx = -1

        # ── Accelerometer bias (stored alongside gyro bias) ───────────────────
        self.accel_bias = [0.0, 0.0, 0.0]

        # ── Mount direction: "forward" or "backward" barrel flip ──────────────
        self.mount_direction = "forward"

        self.buf_size = TOTAL_HISTORY_NEEDED * 2
        self.trace_x  = deque([0.0] * self.buf_size, maxlen=self.buf_size)
        self.trace_y  = deque([0.0] * self.buf_size, maxlen=self.buf_size)
        self.curr_x   = 0.0
        self.curr_y   = 0.0

        self.prev_ax = 0.0
        self.prev_ay = 0.0
        self.prev_az = 0.0

        # Auto-tare parameters
        self.drift_threshold     = 0.05    # ~3° - trigger re-tare
        self.stationary_threshold = 0.3     # rad/s - gyro noise floor at rest
        self.auto_tare_interval  = 30.0     # seconds between auto-tares
        self.last_auto_tare      = 0.0
        self.stationary_count    = 0
        self.stationary_needed   = 30       # ~0.5s of stillness

        # Raw gyro storage for stationary detection
        self.gx_raw = 0.0
        self.gy_raw = 0.0
        self.gz_raw = 0.0

    # ── Calibration & Tare ───────────────────────────────────────────────────

    def calibrate(self, samples, source="manual"):
        """
        source: "manual" (user-initiated) or "auto_loaded" (restored from DB).
        Stores accel_bias alongside gyro_bias when source is manual.
        """
        cnt = len(samples)
        if cnt < MIN_CALIBRATION_SAMPLES:
            return False

        self.gyro_bias = [
            sum(s[3] for s in samples) / cnt,
            sum(s[4] for s in samples) / cnt,
            sum(s[5] for s in samples) / cnt,
        ]

        mean_ax = sum(s[0] for s in samples) / cnt
        mean_ay = sum(s[1] for s in samples) / cnt
        mean_az = sum(s[2] for s in samples) / cnt

        if source == "manual":
            self.accel_bias = [mean_ax, mean_ay, mean_az]

        self.q = _quat_from_accel(mean_ax, mean_ay, mean_az)
        self._apply_tare()
        self.is_calibrated = True
        logger.info(
            "Calibrated — gyro bias (raw): [%.4f, %.4f, %.4f]",
            *self.gyro_bias)
        return True

    def tare(self):
        if not self.is_calibrated:
            logger.warning("Cannot tare: not yet calibrated.")
            return
        self._apply_tare()
        logger.info("Tare applied.")

    def _apply_tare(self):
        self.q_tare = self.q.copy()
        self.curr_x = 0.0
        self.curr_y = 0.0
        self.trace_x.clear()
        self.trace_y.clear()
        self.trace_x.extend([0.0] * self.buf_size)
        self.trace_y.extend([0.0] * self.buf_size)

    def _is_stationary(self) -> bool:
        """Gun is at rest when gyro magnitude is near bias-corrected noise floor."""
        gx = self.gx_raw - self.gyro_bias[0]
        gy = self.gy_raw - self.gyro_bias[1]
        gz = self.gz_raw - self.gyro_bias[2]
        magnitude = math.sqrt(gx*gx + gy*gy + gz*gz)
        return magnitude < self.stationary_threshold

    def auto_tare(self):
        """Silently re-tare when conditions indicate drift has accumulated."""
        if not self.is_calibrated:
            return
        if self.state not in ("IDLE",):
            return
        if time.time() - self.last_auto_tare < self.auto_tare_interval:
            return

        if self._is_stationary():
            self.stationary_count += 1
        else:
            self.stationary_count = 0

        if self.stationary_count < self.stationary_needed:
            return

        aim_offset = math.sqrt(self.curr_x**2 + self.curr_y**2)
        if aim_offset < self.drift_threshold:
            return

        self._apply_tare()
        self.last_auto_tare = time.time()
        self.stationary_count = 0
        logger.debug("Auto-tare applied (aim drifted %.3f rad)", aim_offset)

    # ── Per-packet processing ────────────────────────────────────────────────

    def process(self, packet):
        raw_ax, raw_ay, raw_az, raw_gx, raw_gy, raw_gz, piezo, bat = packet

        # Store raw gyros for stationary detection
        self.gx_raw = raw_gx
        self.gy_raw = raw_gy
        self.gz_raw = raw_gz

        # 1. Bias-correct raw gyros
        gx_bc = raw_gx - self.gyro_bias[0]
        gy_bc = raw_gy - self.gyro_bias[1]
        gz_bc = raw_gz - self.gyro_bias[2]

        # 2. Remap gyro axes
        raw_gyros = [gx_bc, gy_bc, gz_bc]
        wx = GYRO_SIGN_X * raw_gyros[GYRO_AXIS_X]
        wy = GYRO_SIGN_Y * raw_gyros[GYRO_AXIS_Y]
        wz = GYRO_SIGN_Z * raw_gyros[GYRO_AXIS_Z]

        # 3. Integrate orientation quaternion
        self.q = _quat_integrate(self.q, wx, wy, wz, DT)

        # 4. Relative (tared) quaternion
        q_rel = _quat_normalize(
            _quat_multiply(_quat_conjugate(self.q_tare), self.q))

        # 5. Project barrel direction to 2D screen coordinates
        v = _quat_rotate_vector(q_rel, BARREL_VECTOR)
        self.curr_x = math.atan2(-v[1], v[2]) * SCREEN_X_SIGN
        self.curr_y = math.atan2( v[0], v[2]) * SCREEN_Y_SIGN

        self.trace_x.append(self.curr_x)
        self.trace_y.append(self.curr_y)

        # 6. Telemetry
        rot_mag  = math.sqrt(wx**2 + wy**2 + wz**2)

        j_x = raw_ax - self.prev_ax
        j_y = raw_ay - self.prev_ay
        j_z = raw_az - self.prev_az
        jerk_mag = math.sqrt(j_x**2 + j_y**2 + j_z**2) / DT

        self.prev_ax = raw_ax
        self.prev_ay = raw_ay
        self.prev_az = raw_az

        # 7. Shot detection state machine
        shot_data = None

        if self.state == "COOLDOWN":
            self.state_timer -= DT
            if self.state_timer <= 0:
                self.state = "IDLE"

        elif self.state == "IDLE":
            if rot_mag < STABILITY_GYRO_LIMIT:
                self.state       = "ARMING"
                self.state_timer = 0.0

        elif self.state == "ARMING":
            if rot_mag > STABILITY_GYRO_LIMIT:
                self.state = "IDLE"
            else:
                self.state_timer += DT * 1000.0
                if self.state_timer >= STABILITY_WINDOW_MS:
                    self.state = "ARMED"

        elif self.state == "ARMED":
            triggered = False
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

            if rot_mag > (STABILITY_GYRO_LIMIT * STABILITY_GYRO_DISARM_MULT):
                self.state = "IDLE"

        elif self.state == "POST_GATHER":
            self.gather_counter -= 1
            if self.gather_counter <= 0:
                shot_data        = self.analyze_shot()
                self.state       = "COOLDOWN"
                self.state_timer = COOLDOWN_DURATION

        return shot_data, bat, rot_mag, jerk_mag, piezo

    # ── Shot analysis helpers ─────────────────────────────────────────────

    def _mean(self, vals):
        return sum(vals) / len(vals) if vals else 0.0

    def _std(self, vals):
        if len(vals) < 2:
            return 0.0
        m = self._mean(vals)
        return math.sqrt(sum((v - m) ** 2 for v in vals) / (len(vals) - 1))

    def _zone_score(self, deviation, scale):
        """CEP-style score: higher is better (lower deviation from centroid)."""
        return max(0.0, 100.0 * math.exp(-deviation / scale))

    def _score_hold(self, hold_x, hold_y):
        """Hold stability: composite std dev from hold centroid."""
        std_x = self._std(hold_x)
        std_y = self._std(hold_y)
        composite = math.sqrt(std_x ** 2 + std_y ** 2)
        score = 100.0 * math.exp(-composite / ZONE_SCALE_STABILITY_HOLD)
        return min(100.0, score), composite

    def _score_followthrough(self, recoil_x, recoil_y):
        """Follow-through score: how quickly aim recovers toward hold centroid."""
        if len(recoil_x) < 3:
            return 50.0, 0.0
        n = min(len(recoil_x), 10)
        early_x = recoil_x[:n]
        early_y = recoil_y[:n]
        mean_dev = (abs(self._mean(early_x)) + abs(self._mean(early_y))) / 2
        score = 100.0 * math.exp(-mean_dev / RECOVERY_THRESHOLD)
        return min(100.0, score), mean_dev

    def _classify_error(self, a2c_x, a2c_y, a2c_mag):
        """Classify the dominant error type from A2C vector."""
        if a2c_mag < A2C_ANTICIPATION_THRESH:
            return "NONE"
        # ANTICIPATION: break point deviates toward target (large positive X)
        if a2c_x > 0.008:
            return "ANTICIPATION"
        # FLINCH: large magnitude but not purely vertical
        if a2c_mag > A2C_FLINCH_THRESH:
            return "FLINCH"
        # HEEL_PRESS: excessive heel-side (negative X)
        if a2c_x < -0.005:
            return "HEEL_PRESS"
        # THUMB_PUSH: thumb pushing muzzle up (positive Y)
        if a2c_y > 0.005:
            return "THUMB_PUSH"
        return "NONE"

    def _error_severity(self, a2c_mag):
        if a2c_mag < 0.005:
            return "MILD"
        elif a2c_mag < 0.015:
            return "MODERATE"
        else:
            return "SEVERE"

    def _coaching_message(self, error_type, severity):
        messages = {
            "ANTICIPATION": {
                "MILD":    "Focus on smooth, continuous trigger squeeze. Don't push.",
                "MODERATE": "You're pushing the gun toward target on the press. Focus on squeezing, not pushing.",
                "SEVERE":  "Strong anticipation — gun is being pushed toward target at the break. Slow down and focus on trigger control.",
            },
            "FLINCH": {
                "MILD":    "Slight flinch detected. Stay relaxed through the break.",
                "MODERATE": "Flinch present — body is bracing for recoil before shot breaks. Focus on surprise break.",
                "SEVERE":  "Strong flinch — gun is being jerked at the moment of firing. Practice dry fire with no anticipation.",
            },
            "HEEL_PRESS": {
                "MILD":    "Slight heel-side pressure on trigger. Check grip pressure.",
                "MODERATE": "Heel-side push detected. Adjust grip to keep trigger pull straight back.",
                "SEVERE":  "Excessive heel pressure — trigger is being pushed sideways. Keep trigger face flat against finger.",
            },
            "THUMB_PUSH": {
                "MILD":    "Slight upward pressure on trigger. Check thumb position.",
                "MODERATE": "Thumb is pushing the gun upward during press. Relax thumb grip.",
                "SEVERE":  "Thumb is pushing muzzle up at the break. Drop thumb to the frame.",
            },
        }
        return messages.get(error_type, {}).get(severity, "")

    def _letter_grade(self, score):
        if score >= 97: return "A+"
        if score >= 93: return "A"
        if score >= 90: return "A-"
        if score >= 87: return "B+"
        if score >= 83: return "B"
        if score >= 80: return "B-"
        if score >= 77: return "C+"
        if score >= 73: return "C"
        if score >= 70: return "C-"
        if score >= 60: return "D"
        return "F"

    # ── Shot analysis ────────────────────────────────────────────────────────

    def analyze_shot(self):
        hist_len     = len(self.trace_x)
        total_needed = HOLD_DURATION_IDX + RECOIL_DURATION_IDX
        if hist_len < total_needed:
            return None

        full_x = list(self.trace_x)
        full_y = list(self.trace_y)

        idx_recoil_end  = len(full_x)
        idx_break       = idx_recoil_end - RECOIL_DURATION_IDX
        idx_press_start = idx_break - PRESS_DURATION_IDX
        idx_hold_start  = idx_break - HOLD_DURATION_IDX
        if idx_hold_start < 0:
            return None

        break_x = full_x[idx_break]
        break_y = full_y[idx_break]

        def get_norm_segment(start, end):
            return (
                [x - break_x for x in full_x[start:end]],
                [y - break_y for y in full_y[start:end]])

        hold_x,   hold_y   = get_norm_segment(idx_hold_start,  idx_press_start)
        press_x,  press_y  = get_norm_segment(idx_press_start, idx_break + 1)
        recoil_x, recoil_y = get_norm_segment(idx_break,       idx_recoil_end)

        # ── Existing scoring (preserved) ───────────────────────────────────
        deltas = []
        for i in range(1, len(press_x)):
            dx = press_x[i] - press_x[i - 1]
            dy = press_y[i] - press_y[i - 1]
            deltas.append(math.sqrt(dx*dx + dy*dy))

        if not deltas:
            score = 100.0
        else:
            total_travel   = sum(deltas)
            peak_jerk      = max(deltas)
            penalty_travel = total_travel * SCORE_PENALTY_TRAVEL
            penalty_jerk   = peak_jerk   * SCORE_PENALTY_JERK
            score = max(0.0, min(100.0, 100.0 - (penalty_travel + penalty_jerk)))

        # ── A2C metrics (cherry-picked from main.py) ──────────────────────
        hold_centroid_x = self._mean(hold_x)
        hold_centroid_y = self._mean(hold_y)
        a2c_x = break_x - hold_centroid_x
        a2c_y = break_y - hold_centroid_y
        a2c_mag   = math.sqrt(a2c_x ** 2 + a2c_y ** 2)
        a2c_angle = math.degrees(math.atan2(a2c_x, -a2c_y))

        # ── Phase scores ──────────────────────────────────────────────────
        hold_score, hold_std = self._score_hold(hold_x, hold_y)
        press_score = self._zone_score(
            math.sqrt(self._mean([x**2 for x in press_x]) +
                      self._mean([y**2 for y in press_y])),
            ZONE_SCALE_STABILITY_PRESS)
        ft_score, _ = self._score_followthrough(recoil_x, recoil_y)

        # ── Error classification ───────────────────────────────────────────
        error_type   = self._classify_error(a2c_x, a2c_y, a2c_mag)
        error_severity = self._error_severity(a2c_mag)
        coaching_msg   = self._coaching_message(error_type, error_severity)

        # ── Letter grade ───────────────────────────────────────────────────
        grade = self._letter_grade(score)

        # ── Impact prediction (simple model at DEFAULT_TARGET_DISTANCE) ───
        target_d = DEFAULT_TARGET_DISTANCE
        impact_x_cm = round(a2c_x * target_d * 100, 2)
        impact_y_cm = round(a2c_y * target_d * 100, 2)

        # ── Aim trace for DB logging ────────────────────────────────────────
        aim_trace = {
            "hold":   (hold_x,   hold_y),
            "press":  (press_x,  press_y),
            "recoil": (recoil_x, recoil_y),
        }

        # ── Mount direction flip ───────────────────────────────────────────
        if self.mount_direction == "backward":
            impact_x_cm = -impact_x_cm

        return {
            "score":            score,
            "hold":             (hold_x,   hold_y),
            "press":            (press_x,  press_y),
            "recoil":           (recoil_x, recoil_y),
            "piezo":            self.last_trigger_piezo,
            # New fields from main.py
            "grade":            grade,
            "a2c_angle":        round(a2c_angle, 2),
            "a2c_mag":          round(a2c_mag, 5),
            "hold_score":       round(hold_score, 1),
            "press_score":      round(press_score, 1),
            "ft_score":         round(ft_score, 1),
            "hold_stability":   round(hold_std, 5),
            "error_type":       error_type,
            "error_severity":   error_severity,
            "coaching":         coaching_msg,
            "impact_x_cm":      impact_x_cm,
            "impact_y_cm":      impact_y_cm,
            "target_distance":  target_d,
            "aim_trace":        aim_trace,
        }


# ================= CANVAS-BASED AIM WIDGET =================

class AimCanvas(QWidget):
    """Smooth canvas-based aim dot with phosphor trail effect."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(400, 400)
        self.points_x = []
        self.points_y = []
        self.max_points = 60
        self.center_x = 0.0
        self.center_y = 0.0
        self.is_calibrated = False
        self.plot_range = PLOT_RANGE
        self.ring_radii = RING_RADII
        self.trail_color = QColor(COLORS['accent_good'])
        self.cam_x = 0.0
        self.cam_y = 0.0
        self.smooth_factor = 0.08

    def update_aim(self, trace_x, trace_y, curr_x, curr_y, calibrated):
        self.points_x = list(trace_x)
        self.points_y = list(trace_y)
        self.center_x = curr_x
        self.center_y = curr_y
        self.is_calibrated = calibrated
        self.cam_x += (curr_x - self.cam_x) * self.smooth_factor
        self.cam_y += (curr_y - self.cam_y) * self.smooth_factor
        self.update()

    def set_range(self, r):
        self.plot_range = r
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor(COLORS['bg_secondary']))

        w, h = self.width(), self.height()
        canvas_cx, canvas_cy = w // 2, h // 2
        scale = min(w, h) / (2 * self.plot_range) * 0.9

        def world_to_screen(wx, wy):
            sx = canvas_cx + (wx - self.cam_x) * scale
            sy = canvas_cy - (wy - self.cam_y) * scale
            return sx, sy

        # Target rings
        for r in self.ring_radii:
            sx, sy = world_to_screen(self.cam_x, self.cam_y)
            ring_rect = QRectF(sx - r * scale, sy - r * scale, r * 2 * scale, r * 2 * scale)
            painter.setPen(QPen(QColor('#2A2A2A'), 1))
            painter.drawEllipse(ring_rect)

        # Crosshair
        painter.setPen(QPen(QColor('#333333'), 1))
        painter.drawLine(canvas_cx - 20, canvas_cy, canvas_cx + 20, canvas_cy)
        painter.drawLine(canvas_cx, canvas_cy - 20, canvas_cx, canvas_cy + 20)

        if not self.is_calibrated:
            return

        # Trail
        if len(self.points_x) > 1:
            trail_pen = QPen(QColor(COLORS['accent_good']), 2)
            path = QPainterPath()
            offset = len(self.points_x) - min(len(self.points_x), self.max_points)
            pts = self.points_x[offset:]
            pts_y = self.points_y[offset:]

            if len(pts) > 1:
                sx0, sy0 = world_to_screen(pts[0], pts_y[0])
                path.moveTo(sx0, sy0)
                for i in range(1, len(pts)):
                    dx = pts[i] - pts[i - 1]
                    dy = pts_y[i] - pts_y[i - 1]
                    dist = math.sqrt(dx * dx + dy * dy)
                    sx, sy = world_to_screen(pts[i], pts_y[i])
                    if dist > TRAIL_MOVEMENT_THRESHOLD:
                        path.lineTo(sx, sy)
                    else:
                        path.moveTo(sx, sy)
                painter.setPen(trail_pen)
                painter.drawPath(path)

        # Aim dot
        dot_x, dot_y = world_to_screen(self.center_x, self.center_y)
        glow = QRadialGradient(dot_x, dot_y, 15)
        glow.setColorAt(0, QColor(COLORS['accent_good']))
        glow.setColorAt(1, QColor(0, 210, 106, 0))
        painter.fillRect(self.rect(), QBrush(glow))
        painter.setBrush(QBrush(QColor(COLORS['accent_good'])))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(int(dot_x) - 6, int(dot_y) - 6, 12, 12)


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
        self.target_type = '10m_air_pistol'
        self.issf_mode = True
        self.impact_points = []
        self.ring_radii = RING_RADII

    def set_trace(self, hold=None, press=None, recoil=None, score=0,
                  impact_x_cm=0.0, impact_y_cm=0.0, shot_idx=0):
        self.hol_x, self.hol_y = (hold if hold else ([], []))
        self.pre_x, self.pre_y = (press if press else ([], []))
        self.rec_x, self.rec_y = (recoil if recoil else ([], []))
        self.score = score
        self.impact_x_cm = impact_x_cm
        self.impact_y_cm = impact_y_cm
        self.current_shot_idx = shot_idx
        self.update()

    def clear_trace(self):
        self.hol_x, self.hol_y = [], []
        self.pre_x, self.pre_y = [], []
        self.rec_x, self.rec_y = [], []
        self.score = 0
        self.impact_x_cm = 0.0
        self.impact_y_cm = 0.0
        self.current_shot_idx = 0
        self.impact_points = []
        self.update()

    def set_target_type(self, type_key: str):
        """Set the target type for ISSF rendering."""
        if type_key not in TARGET_SPECS:
            logger.warning(f"Unknown target type: {type_key}, defaulting to 10m_air_pistol")
            self.target_type = '10m_air_pistol'
        else:
            self.target_type = type_key
        self.update()

    def set_issf_mode(self, enabled: bool):
        """Enable or disable ISSF target rendering mode."""
        self.issf_mode = enabled
        self.update()

    def add_impact_point(self, x_cm: float, y_cm: float, score: float):
        """Add an impact point for overlay display."""
        self.impact_points.append((x_cm, y_cm, score))
        self.update()

    def set_scale(self, s):
        self.scale = max(0.5, min(5.0, s))

    def wheelEvent(self, event):
        delta = event.angleDelta().y()
        factor = 1.15 if delta > 0 else 1.0 / 1.15
        self.scale = max(0.5, min(5.0, self.scale * factor))
        self.update()

    def _draw_path(self, painter, xs, ys, cx, cy, scale, pen):
        if len(xs) < 2:
            return
        path = QPainterPath()
        path.moveTo(cx + xs[0] * scale, cy - ys[0] * scale)
        for i in range(1, len(xs)):
            path.lineTo(cx + xs[i] * scale, cy - ys[i] * scale)
        painter.setPen(pen)
        painter.drawPath(path)

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


class SparklineWidget(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.values = []
        self.setFixedHeight(40)

    def set_values(self, values):
        self.values = list(values)
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor(COLORS['bg_tertiary']))

        if len(self.values) < 2:
            painter.setPen(QPen(QColor(COLORS['text_muted'])))
            painter.drawText(self.rect(), Qt.AlignCenter, "No trend data")
            return

        w, h = self.width(), self.height()
        pad = 4
        min_v = min(self.values)
        max_v = max(self.values)
        span = max(max_v - min_v, 1)

        points = [(pad + i / (len(self.values) - 1) * (w - pad * 2),
                   h - pad - (v - min_v) / span * (h - pad * 2))
                  for i, v in enumerate(self.values)]

        fill_path = QPainterPath()
        fill_path.moveTo(points[0][0], h - pad)
        for x, y in points:
            fill_path.lineTo(x, y)
        fill_path.lineTo(points[-1][0], h - pad)
        fill_path.closeSubpath()
        painter.fillPath(fill_path, QColor(COLORS['accent_blue'] + "22"))

        line_path = QPainterPath()
        line_path.moveTo(*points[0])
        for x, y in points[1:]:
            line_path.lineTo(x, y)
        painter.setPen(QPen(QColor(COLORS['accent_blue']), 2))
        painter.drawPath(line_path)

        painter.setBrush(QBrush(QColor(COLORS['accent_blue'])))
        painter.setPen(Qt.NoPen)
        for x, y in points:
            painter.drawEllipse(int(x) - 3, int(y) - 3, 6, 6)


class PerShotStatsWidget(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._setup_ui()

    def _setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(10)

        self._title = QLabel("Per-Shot Statistics")
        self._title.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 14px; font-weight: 600;")
        layout.addWidget(self._title)

        self._phase_bars = {}
        for phase, color in [('Hold', '#FF0000'),
                              ('Press', '#FFFF00'),
                              ('Recoil', '#00FFFF'),
                              ('FT', '#FF5252')]:
            row = QHBoxLayout()
            row.setSpacing(8)
            lbl = QLabel(phase)
            lbl.setFixedWidth(46)
            lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 11px; font-weight: 600;")
            row.addWidget(lbl)

            bar = QProgressBar()
            bar.setFixedHeight(8)
            bar.setTextVisible(False)
            bar.setStyleSheet(f"""
                QProgressBar {{
                    background: {COLORS['bg_tertiary']};
                    border: none;
                    border-radius: 4px;
                }}
                QProgressBar::chunk {{
                    background: {color};
                    border-radius: 4px;
                }}
            """)
            self._phase_bars[phase] = bar
            row.addWidget(bar, 1)

            self._phase_bars[f'{phase}_lbl'] = QLabel("--")
            self._phase_bars[f'{phase}_lbl'].setFixedWidth(28)
            self._phase_bars[f'{phase}_lbl'].setStyleSheet(f"color: {color}; font-size: 11px; font-weight: 700;")
            row.addWidget(self._phase_bars[f'{phase}_lbl'])
            layout.addLayout(row)

        layout.addSpacing(4)

        self._a2c_lbl = QLabel("A2C: --")
        self._a2c_lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px;")
        layout.addWidget(self._a2c_lbl)

        self._stab_lbl = QLabel("Stability: --")
        self._stab_lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px;")
        self._shoot_lbl = QLabel("Shooting: --")
        self._shoot_lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px;")
        score_row = QHBoxLayout()
        score_row.addWidget(self._stab_lbl)
        score_row.addWidget(self._shoot_lbl)
        layout.addLayout(score_row)

        self._grade_lbl = QLabel("Grade: --")
        self._grade_lbl.setStyleSheet(
            f"background: {COLORS['bg_tertiary']}; border: 1px solid {COLORS['border']}; "
            f"border-radius: 8px; padding: 6px 14px; "
            f"font-size: 12px; font-weight: 700; color: {COLORS['text_secondary']};")
        layout.addWidget(self._grade_lbl)

        self._err_lbl = QLabel("Error: --")
        self._err_lbl.setStyleSheet(
            f"background: {COLORS['accent_ok']}22; border: 1px solid {COLORS['accent_ok']}66; "
            f"border-radius: 6px; padding: 4px 10px; "
            f"font-size: 11px; color: {COLORS['accent_ok']};")
        self._err_lbl.setVisible(False)
        layout.addWidget(self._err_lbl)

        self._imp_lbl = QLabel("Impact: (--, --)")
        self._imp_lbl.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 11px;")
        layout.addWidget(self._imp_lbl)

        self._issf_score_lbl = QLabel("ISSF: --")
        self._issf_score_lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px; font-weight: 600;")
        layout.addWidget(self._issf_score_lbl)

        layout.addStretch()

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

    def _score_color(self, score):
        if score >= 95: return COLORS.get('score_elite', COLORS['accent_good'])
        if score >= 85: return COLORS.get('score_expert', COLORS['accent_good'])
        if score >= 70: return COLORS.get('score_advanced', COLORS['accent_ok'])
        if score >= 50: return COLORS.get('score_intermediate', COLORS['accent_ok'])
        return COLORS.get('score_beginner', COLORS['accent_bad'])

    def _letter_grade(self, score):
        if score >= 97: return 'A+'
        if score >= 93: return 'A'
        if score >= 90: return 'A-'
        if score >= 87: return 'B+'
        if score >= 83: return 'B'
        if score >= 80: return 'B-'
        if score >= 77: return 'C+'
        if score >= 73: return 'C'
        if score >= 70: return 'C-'
        if score >= 60: return 'D'
        return 'F'

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


class SessionStatsWidget(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._setup_ui()

    def _setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(10)

        self._title = QLabel("Session Statistics")
        self._title.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 14px; font-weight: 600;")
        layout.addWidget(self._title)

        summary_layout = QHBoxLayout()
        summary_layout.setSpacing(8)
        self._avg_card = self._make_stat_card("Avg Score", "--")
        self._best_card = self._make_stat_card("Best", "--")
        self._count_card = self._make_stat_card("Shots", "0")
        for card in [self._avg_card, self._best_card, self._count_card]:
            summary_layout.addWidget(card)
        layout.addLayout(summary_layout)

        spark_label = QLabel("Score Trend")
        spark_label.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 11px; font-weight: 600;")
        layout.addWidget(spark_label)

        self._sparkline = SparklineWidget()
        layout.addWidget(self._sparkline)
        layout.addStretch()

    def _make_stat_card(self, title, value):
        card = QFrame()
        card.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_tertiary']};
                border: 1px solid {COLORS['border']};
                border-radius: 10px;
                padding: 8px;
            }}
        """)
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(6, 6, 6, 6)
        card_layout.setSpacing(2)

        lbl_title = QLabel(title.upper())
        lbl_title.setStyleSheet(
            f"color: {COLORS['text_muted']}; font-size: 9px; font-weight: 700; letter-spacing: 0.5px;")
        lbl_title.setFont(QFont("Segoe UI", 9, QFont.Bold))
        card_layout.addWidget(lbl_title)

        lbl_value = QLabel(value)
        lbl_value.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 16px; font-weight: 700;")
        lbl_value.setFont(QFont("Segoe UI", 16, QFont.Bold))
        card_layout.addWidget(lbl_value)
        return card

    def populate(self, shots):
        if not shots:
            self._avg_card.findChild(QLabel, "", Qt.FindDirectChildOnly).setText("--")
            self._best_card.findChild(QLabel, "", Qt.FindDirectChildOnly).setText("--")
            self._count_card.findChild(QLabel, "", Qt.FindDirectChildOnly).setText("0")
            self._sparkline.set_values([])
            return

        scores = [s.get('score', 0) or 0 for s in shots]
        avg = sum(scores) / len(scores) if scores else 0
        best = max(scores) if scores else 0

        self._set_card_value(self._avg_card, f"{avg:.1f}")
        self._set_card_value(self._best_card, f"{int(best)}")
        self._set_card_value(self._count_card, str(len(shots)))
        self._sparkline.set_values(scores[-10:])

    def _set_card_value(self, card, value):
        lbls = card.findChildren(QLabel)
        if len(lbls) >= 2:
            lbls[1].setText(value)

    def clear(self):
        self._set_card_value(self._avg_card, "--")
        self._set_card_value(self._best_card, "--")
        self._set_card_value(self._count_card, "0")
        self._sparkline.set_values([])


# ================= UI CLASSES =================

class LiveMonitorWindow(QMainWindow):
    closed = pyqtSignal()

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Live Aim Monitor")
        self.resize(600, 600)
        self.setStyleSheet("background-color: #000;")

        cw  = QWidget()
        self.setCentralWidget(cw)
        lay = QVBoxLayout(cw)

        head = QHBoxLayout()
        lbl  = QLabel("REAL-TIME TRACE")
        lbl.setStyleSheet("color: #0F0; font-weight: bold; font-size: 14pt;")
        self.lbl_calib_status = QLabel("UNCALIBRATED")
        self.lbl_calib_status.setStyleSheet(
            "color: #FF5500; font-weight: bold; font-size: 10pt; "
            "background: #331100; padding: 3px;")
        head.addWidget(lbl)
        head.addStretch()
        head.addWidget(self.lbl_calib_status)
        lay.addLayout(head)

        self.plot = pg.PlotWidget()
        self.plot.setBackground('k')
        self.plot.showGrid(x=True, y=True, alpha=0.3)
        self.plot.setAspectLocked(True)
        self.plot.setXRange(-PLOT_RANGE, PLOT_RANGE)
        self.plot.setYRange(-PLOT_RANGE, PLOT_RANGE)
        self.trace_curve = self.plot.plot(pen=pg.mkPen('#00FF00', width=3))
        self.center_ref  = self.plot.plot(
            pen=None, symbol='+', symbolSize=20, symbolBrush='#555')
        self.cursor = self.plot.plot(
            pen=None, symbol='o', symbolSize=10, symbolBrush='r')
        lay.addWidget(self.plot)

    def closeEvent(self, event):
        self.closed.emit()
        super().closeEvent(event)

    def update_data(self, x_data, y_data, is_calibrated):
        if is_calibrated:
            self.lbl_calib_status.setText("CALIBRATED")
            self.lbl_calib_status.setStyleSheet(
                "color: #00FF00; background: #002200; padding: 3px;")
        else:
            self.lbl_calib_status.setText("UNCALIBRATED")
            self.lbl_calib_status.setStyleSheet(
                "color: #FF5500; background: #331100; padding: 3px;")
        self.trace_curve.setData(x_data, y_data)
        self.center_ref.setData([0], [0])
        if x_data:
            self.cursor.setData([x_data[-1]], [y_data[-1]])


class MainWindow(QMainWindow):
    def __init__(self, serial_port):
        super().__init__()
        self.ser         = serial_port
        self.detector    = ShotDetector()
        self.session_id  = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.live_window = None
        self.init_ui()
        self.calib_buffer = []
        self.calibrating  = False
        self._auto_calibrating = False
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_loop)
        self.timer.start(10)

    def _stylized_button(self, btn, bg, fg='#FFF', border=None):
        style = f"""
            QPushButton {{
                background: {bg};
                color: {fg};
                border: 1px solid {border or bg};
                border-radius: 6px;
                padding: 12px 20px;
                font-size: 13px;
                font-weight: 600;
            }}
            QPushButton:hover {{ background: {bg}dd; }}
            QPushButton:pressed {{ background: {bg}aa; }}
        """
        btn.setStyleSheet(style)
        return btn

    def _card(self, widget):
        frame = QFrame()
        frame.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_card']};
                border: 1px solid {COLORS['border']};
                border-radius: 12px;
                padding: 16px;
            }}
        """)
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.addWidget(widget)
        return frame

    def init_ui(self):
        self.setWindowTitle('STASYS')
        self.setMinimumSize(1024, 768)
        self.setFocusPolicy(Qt.StrongFocus)
        self.showFullScreen()

        palette = QPalette()
        palette.setColor(QPalette.Window, QColor(COLORS['bg_primary']))
        palette.setColor(QPalette.WindowText, QColor(COLORS['text_primary']))
        palette.setColor(QPalette.Base, QColor(COLORS['bg_secondary']))
        palette.setColor(QPalette.Text, QColor(COLORS['text_primary']))
        self.setPalette(palette)

        central = QWidget()
        self.setCentralWidget(central)
        main_layout = QVBoxLayout(central)
        main_layout.setContentsMargins(0, 0, 0, 0)

        # Header
        header = QFrame()
        header.setStyleSheet(f"background: {COLORS['bg_secondary']}; border-bottom: 1px solid {COLORS['border']};")
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(24, 16, 24, 16)

        title = QLabel("STASYS")
        title.setFont(QFont("Segoe UI", 24, QFont.Bold))
        title.setStyleSheet(f"color: {COLORS['accent_good']};")
        header_layout.addWidget(title)

        self.lbl_session_info = QLabel("Session: -- | Mode: Dry Fire")
        self.lbl_session_info.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 13px;")
        header_layout.addWidget(self.lbl_session_info)
        header_layout.addStretch()

        self.lbl_sim_indicator = QLabel("")
        self.lbl_sim_indicator.setStyleSheet(f"""
            QLabel {{
                background: {COLORS['accent_ok']};
                color: {COLORS['bg_primary']};
                padding: 6px 16px;
                border-radius: 20px;
                font-weight: 600;
                font-size: 12px;
            }}
        """)
        if hasattr(self.ser, 'update_sim'):
            self.lbl_sim_indicator.setText("SIMULATION MODE")
        header_layout.addWidget(self.lbl_sim_indicator)
        main_layout.addWidget(header)

        # Tabs
        self.tabs = QTabWidget()
        self.tabs.setStyleSheet(f"""
            QTabWidget::pane {{ border: none; background: {COLORS['bg_primary']}; }}
            QTabBar {{
                background: {COLORS['bg_secondary']};
                border-bottom: 1px solid {COLORS['border']};
            }}
            QTabBar::tab {{
                background: transparent;
                color: {COLORS['text_secondary']};
                padding: 14px 24px;
                font-size: 13px;
                font-weight: 500;
                border: none;
                min-width: 130px;
            }}
            QTabBar::tab:selected {{
                color: {COLORS['accent_good']};
                border-bottom: 2px solid {COLORS['accent_good']};
            }}
            QTabBar::tab:hover {{ color: {COLORS['text_primary']}; }}
        """)
        main_layout.addWidget(self.tabs, 1)

        self._build_live_monitor_tab()
        self._build_shot_analysis_tab()
        self._build_history_tab()
        self._build_settings_tab()

    def _build_live_monitor_tab(self):
        tab1 = QWidget()
        tab1.setStyleSheet(f"background: {COLORS['bg_primary']};")
        tab1_layout = QHBoxLayout(tab1)
        tab1_layout.setContentsMargins(20, 20, 20, 20)
        tab1_layout.setSpacing(20)

        # Left control panel
        left_panel = QFrame()
        left_panel.setMinimumWidth(260)
        left_panel.setStyleSheet(f"background: {COLORS['bg_secondary']}; border-radius: 16px;")
        left_layout = QVBoxLayout(left_panel)
        left_layout.setContentsMargins(16, 16, 16, 16)
        left_layout.setSpacing(12)

        mode_label = QLabel("Detection Mode")
        mode_label.setFont(QFont("Segoe UI", 12, QFont.Bold))
        mode_label.setStyleSheet(f"color: #FFFFFF; font-size: 12px; font-weight: 700; letter-spacing: 1px;")
        left_layout.addWidget(mode_label)

        self.cmb_mode = QComboBox()
        self.cmb_mode.addItems(["Dry Fire (Piezo)", "Live Fire (Jerk)"])
        self.cmb_mode.setFont(QFont("Segoe UI", 13))
        self.cmb_mode.setStyleSheet(f"""
            QComboBox {{
                background: {COLORS['bg_tertiary']};
                color: #FFFFFF;
                border: 2px solid {COLORS['border']};
                border-radius: 8px;
                padding: 12px 16px;
                font-size: 13px;
            }}
            QComboBox::drop-down {{ border: none; }}
            QComboBox QAbstractItemView {{
                background: {COLORS['bg_tertiary']};
                color: #FFFFFF;
                border: 1px solid {COLORS['border']};
                selection-background-color: {COLORS['accent_good']};
                selection-color: #000000;
            }}
        """)
        self.cmb_mode.currentIndexChanged.connect(self.change_mode)
        left_layout.addWidget(self.cmb_mode)

        thresh_label = QLabel("Thresholds")
        thresh_label.setFont(QFont("Segoe UI", 12, QFont.Bold))
        thresh_label.setStyleSheet(f"color: #00D26A; font-size: 12px; font-weight: 700; letter-spacing: 1px; margin-top: 8px; margin-bottom: 4px;")
        left_layout.addWidget(thresh_label)

        thresh_grid = QGridLayout()
        thresh_grid.setSpacing(12)
        thresh_grid.setVerticalSpacing(8)

        piezo_lbl = QLabel("Piezo Min")
        piezo_lbl.setStyleSheet(f"color: #FFFFFF; font-size: 13px;")
        thresh_grid.addWidget(piezo_lbl, 0, 0)
        self.spin_piezo = QDoubleSpinBox()
        self.spin_piezo.setRange(0, 4095)
        self.spin_piezo.setValue(DEFAULT_PIEZO_MIN)
        self.spin_piezo.setFont(QFont("Segoe UI", 14, QFont.Bold))
        self.spin_piezo.valueChanged.connect(self.update_thresholds)
        thresh_grid.addWidget(self.spin_piezo, 0, 1)

        jerk_lbl = QLabel("Jerk (G)")
        jerk_lbl.setStyleSheet(f"color: #FFFFFF; font-size: 13px;")
        thresh_grid.addWidget(jerk_lbl, 1, 0)
        self.spin_jerk = QDoubleSpinBox()
        self.spin_jerk.setRange(0, 200)
        self.spin_jerk.setValue(DEFAULT_ACCEL_THRESH)
        self.spin_jerk.setFont(QFont("Segoe UI", 14, QFont.Bold))
        self.spin_jerk.valueChanged.connect(self.update_thresholds)
        thresh_grid.addWidget(self.spin_jerk, 1, 1)
        left_layout.addLayout(thresh_grid)

        for sp in [self.spin_piezo, self.spin_jerk]:
            sp.setStyleSheet(f"""
                QDoubleSpinBox {{
                    background: {COLORS['bg_tertiary']};
                    color: #FFFFFF;
                    border: 2px solid #00D26A;
                    border-radius: 8px;
                    padding: 8px 10px;
                    font-size: 13px;
                    font-weight: 600;
                }}
                QDoubleSpinBox::up-button, QDoubleSpinBox::down-button {{
                    width: 22px;
                    border: none;
                    background: {COLORS['bg_secondary']};
                }}
                QDoubleSpinBox::up-button:hover, QDoubleSpinBox::down-button:hover {{
                    background: {COLORS['accent_good']};
                }}
            """)

        status_label = QLabel("Status")
        status_label.setFont(QFont("Segoe UI", 12, QFont.Bold))
        status_label.setStyleSheet(f"color: #00D26A; font-size: 12px; font-weight: 700; letter-spacing: 1px; margin-top: 8px; margin-bottom: 4px;")
        left_layout.addWidget(status_label)

        self.lbl_status = QLabel("DISCONNECTED")
        self.lbl_status.setFont(QFont("Segoe UI", 14, QFont.Bold))
        self.lbl_status.setAlignment(Qt.AlignCenter)
        self.lbl_status.setStyleSheet(f"""
            QLabel {{
                background: {COLORS['bg_tertiary']};
                color: #FFFFFF;
                font-size: 14px;
                font-weight: 700;
                border: 2px solid {COLORS['border']};
                border-radius: 8px;
                padding: 10px;
            }}
        """)
        left_layout.addWidget(self.lbl_status)

        self.btn_calib = QPushButton("CALIBRATE")
        self.btn_calib.setCursor(Qt.PointingHandCursor)
        self.btn_calib.clicked.connect(self.start_calibration)
        left_layout.addWidget(self.btn_calib)
        self._stylized_button(self.btn_calib, COLORS['accent_blue'], '#FFF')

        self.btn_tare = QPushButton("TARE — Re-Zero Aim")
        self.btn_tare.setCursor(Qt.PointingHandCursor)
        self.btn_tare.setToolTip("Stores current orientation as screen center.")
        self.btn_tare.clicked.connect(self.do_tare)
        left_layout.addWidget(self.btn_tare)
        self._stylized_button(self.btn_tare, '#1B5E20', COLORS['accent_good'], COLORS['accent_good'])

        self.btn_record = QPushButton("▶ START RECORD")
        self.btn_record.setCursor(Qt.PointingHandCursor)
        self.btn_record.clicked.connect(self.toggle_recording)
        self._stylized_button(self.btn_record, COLORS['accent_good'], '#000', COLORS['accent_good'])
        left_layout.addWidget(self.btn_record)

        self.lbl_record_state = QLabel("● IDLE")
        self.lbl_record_state.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 12px; font-weight: 600;")
        self.lbl_record_state.setAlignment(Qt.AlignCenter)
        left_layout.addWidget(self.lbl_record_state)

        telem_label = QLabel("Telemetry")
        telem_label.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 11px; text-transform: uppercase; letter-spacing: 1px;")
        left_layout.addWidget(telem_label)

        self.lbl_telem = QLabel("Jerk: --\nPiezo: --\nRot: --\nBat: --%")
        self.lbl_telem.setStyleSheet(f"""
            QLabel {{
                font-family: 'Consolas', 'Courier New', monospace;
                font-size: 13px;
                color: {COLORS['text_secondary']};
                background: {COLORS['bg_tertiary']};
                border-radius: 8px;
                padding: 12px 16px;
            }}
        """)
        left_layout.addWidget(self.lbl_telem)

        left_layout.addStretch()
        tab1_layout.addWidget(left_panel, 1)

        # Centre: Aim canvas + bottom strip
        center_layout = QVBoxLayout()
        self.aim_canvas = AimCanvas()
        self.aim_canvas.setStyleSheet(f"""
            QWidget {{
                background: {COLORS['bg_secondary']};
                border: 2px solid {COLORS['accent_good']};
                border-radius: 16px;
            }}
        """)
        center_layout.addWidget(self.aim_canvas, 5)

        # Bottom strip
        strip = QHBoxLayout()
        strip.setSpacing(16)

        # Stability block
        stability_block = QVBoxLayout()
        stability_block.setSpacing(2)
        stab_title = QLabel("STABILITY")
        stab_title.setAlignment(Qt.AlignCenter)
        stab_title.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 10px; text-transform: uppercase; letter-spacing: 1.5px;")
        stability_block.addWidget(stab_title)

        stab_score_row = QHBoxLayout()
        stab_score_row.setSpacing(8)
        self.lbl_stability_score = QLabel("--")
        self.lbl_stability_score.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.lbl_stability_score.setStyleSheet(f"font-size: 42px; font-weight: 200; color: {COLORS['text_muted']};")
        stab_score_row.addWidget(self.lbl_stability_score)
        self.lbl_stability_grade = QLabel("")
        self.lbl_stability_grade.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        self.lbl_stability_grade.setStyleSheet(f"font-size: 22px; font-weight: 600; color: {COLORS['text_muted']};")
        stab_score_row.addWidget(self.lbl_stability_grade)
        stability_block.addLayout(stab_score_row)

        self.lbl_shot_count = QLabel("Shots: 0")
        self.lbl_shot_count.setAlignment(Qt.AlignCenter)
        self.lbl_shot_count.setStyleSheet(f"font-size: 13px; color: {COLORS['text_secondary']};")
        stability_block.addWidget(self.lbl_shot_count)
        strip.addLayout(stability_block, 3)

        # Divider
        div0 = QFrame()
        div0.setFrameShape(QFrame.VLine)
        div0.setStyleSheet(f"color: {COLORS['border']};")
        strip.addWidget(div0)

        # Shooting block
        shooting_block = QVBoxLayout()
        shooting_block.setSpacing(2)
        shoot_title = QLabel("SHOOTING")
        shoot_title.setAlignment(Qt.AlignCenter)
        shoot_title.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 10px; text-transform: uppercase; letter-spacing: 1.5px;")
        shooting_block.addWidget(shoot_title)

        shoot_score_row = QHBoxLayout()
        shoot_score_row.setSpacing(8)
        self.lbl_shooting_score = QLabel("--")
        self.lbl_shooting_score.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.lbl_shooting_score.setStyleSheet(f"font-size: 42px; font-weight: 200; color: {COLORS['text_muted']};")
        shoot_score_row.addWidget(self.lbl_shooting_score)
        self.lbl_shooting_grade = QLabel("")
        self.lbl_shooting_grade.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        self.lbl_shooting_grade.setStyleSheet(f"font-size: 22px; font-weight: 600; color: {COLORS['text_muted']};")
        shoot_score_row.addWidget(self.lbl_shooting_grade)
        shooting_block.addLayout(shoot_score_row)

        self.lbl_group_center = QLabel("Group: --")
        self.lbl_group_center.setAlignment(Qt.AlignCenter)
        self.lbl_group_center.setStyleSheet(f"font-size: 11px; color: {COLORS['text_muted']};")
        shooting_block.addWidget(self.lbl_group_center)
        strip.addLayout(shooting_block, 3)

        # Divider
        div1 = QFrame()
        div1.setFrameShape(QFrame.VLine)
        div1.setStyleSheet(f"color: {COLORS['border']};")
        strip.addWidget(div1)

        # Piezo block
        piezo_block = QVBoxLayout()
        piezo_block.setSpacing(4)
        piezo_title = QLabel("PIEZO")
        piezo_title.setAlignment(Qt.AlignCenter)
        piezo_title.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 10px; text-transform: uppercase; letter-spacing: 1.5px;")
        piezo_block.addWidget(piezo_title)

        self.lbl_big_piezo = QLabel("--")
        self.lbl_big_piezo.setAlignment(Qt.AlignCenter)
        self.lbl_big_piezo.setStyleSheet(f"font-size: 36px; font-weight: 200; color: {COLORS['text_muted']};")
        piezo_block.addWidget(self.lbl_big_piezo)

        self.piezo_bar_container = QFrame()
        self.piezo_bar_container.setFixedHeight(8)
        self.piezo_bar_container.setStyleSheet(f"background: {COLORS['bg_tertiary']}; border-radius: 4px;")
        self.piezo_bar_inner = QFrame(self.piezo_bar_container)
        self.piezo_bar_inner.setGeometry(4, 2, 0, 4)
        self.piezo_bar_inner.setStyleSheet(f"background: {COLORS['accent_ok']}; border-radius: 2px;")
        piezo_block.addWidget(self.piezo_bar_container)

        self.lbl_piezo_minmax = QLabel("0 / 4095")
        self.lbl_piezo_minmax.setAlignment(Qt.AlignCenter)
        self.lbl_piezo_minmax.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 10px; font-family: 'Consolas', 'Courier New', monospace;")
        piezo_block.addWidget(self.lbl_piezo_minmax)
        strip.addLayout(piezo_block, 2)

        # Divider
        div2 = QFrame()
        div2.setFrameShape(QFrame.VLine)
        div2.setStyleSheet(f"color: {COLORS['border']};")
        strip.addWidget(div2)

        # Phase score frames
        for phase_lbl, score_attr in [("HOLD", 'hold_score'),
                                        ("PRESS", 'press_score'),
                                        ("RECOIL", 'recoil_score'),
                                        ("FT", 'ft_score')]:
            phase_frame = QFrame()
            phase_frame.setStyleSheet(f"background: {COLORS['bg_secondary']}; border: 1px solid {COLORS['border']}; border-radius: 8px;")
            phase_inner = QVBoxLayout(phase_frame)
            phase_inner.setContentsMargins(10, 6, 10, 6)
            phase_inner.setSpacing(2)

            ph_lbl = QLabel(phase_lbl)
            ph_lbl.setAlignment(Qt.AlignCenter)
            ph_lbl.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 9px; text-transform: uppercase; letter-spacing: 1px;")
            phase_inner.addWidget(ph_lbl)

            ph_val = QLabel("--")
            ph_val.setAlignment(Qt.AlignCenter)
            ph_val.setObjectName(f"lbl_{score_attr}")
            ph_val.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 16px; font-weight: 600;")
            phase_inner.addWidget(ph_val)
            strip.addWidget(phase_frame)

        strip_frame = QFrame()
        strip_frame.setMaximumHeight(110)
        strip_frame.setLayout(strip)
        center_layout.addWidget(strip_frame)

        tab1_layout.addLayout(center_layout, 4)
        self.tabs.addTab(tab1, "Live Monitor")

    def _build_shot_analysis_tab(self):
        tab2 = QWidget()
        tab2.setStyleSheet(f"background: {COLORS['bg_primary']};")
        tab2_layout = QHBoxLayout(tab2)
        tab2_layout.setContentsMargins(20, 20, 20, 20)
        tab2_layout.setSpacing(20)

        splitter = QSplitter(Qt.Horizontal)

        # Left: Shot trace canvas
        trace_panel = QVBoxLayout()
        self.shot_trace_canvas = ShotTraceCanvas()
        self.shot_trace_canvas.setStyleSheet(f"""
            background: {COLORS['bg_secondary']};
            border: 1px solid {COLORS['border']};
            border-radius: 16px;
        """)
        trace_panel.addWidget(self.shot_trace_canvas, 1)

        # Legend row
        legend_row = QHBoxLayout()
        legend_row.setSpacing(16)
        for color, label in [('#FF0000', 'Hold'), ('#FFFF00', 'Press'), ('#00FFFF', 'FT')]:
            dot = QFrame()
            dot.setFixedSize(12, 12)
            dot.setStyleSheet(f"background: {color}; border-radius: 6px;")
            lbl = QLabel(label)
            lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px;")
            legend_row.addWidget(dot)
            legend_row.addWidget(lbl)
        legend_row.addStretch()
        hint = QLabel("Scroll to zoom")
        hint.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 11px;")
        legend_row.addWidget(hint)
        trace_panel.addLayout(legend_row)

        trace_frame = QFrame()
        trace_frame.setLayout(trace_panel)
        trace_frame.setStyleSheet(f"background: {COLORS['bg_secondary']}; border-radius: 16px; padding: 12px;")
        splitter.addWidget(trace_frame)

        # Right: Stats
        right_panel = QVBoxLayout()
        right_panel.setSpacing(12)

        self.per_shot_stats = PerShotStatsWidget()
        stats_card = self._card(self.per_shot_stats)
        right_panel.addWidget(stats_card)

        self.session_stats = SessionStatsWidget()
        session_card = self._card(self.session_stats)
        right_panel.addWidget(session_card)

        right_panel.addStretch()
        right_frame = QFrame()
        right_frame.setLayout(right_panel)
        splitter.addWidget(right_frame)

        splitter.setStretchFactor(0, 6)
        splitter.setStretchFactor(1, 4)
        splitter.setHandleWidth(8)
        tab2_layout.addWidget(splitter)
        self.tabs.addTab(tab2, "Shot Analysis")

    def _build_history_tab(self):
        tab3 = QWidget()
        tab3.setStyleSheet(f"background: {COLORS['bg_primary']};")
        tab3_layout = QVBoxLayout(tab3)
        tab3_layout.setContentsMargins(20, 20, 20, 20)
        tab3_layout.setSpacing(16)

        # Header
        hist_header = QHBoxLayout()
        hist_title = QLabel("Session History")
        hist_title.setFont(QFont("Segoe UI", 24, QFont.Bold))
        hist_title.setStyleSheet(f"color: {COLORS['text_primary']};")
        hist_header.addWidget(hist_title)
        hist_header.addStretch()

        self.btn_reset = QPushButton("New Session")
        self.btn_reset.setCursor(Qt.PointingHandCursor)
        self.btn_reset.clicked.connect(self.reset_session)
        self._stylized_button(self.btn_reset, COLORS['accent_bad'], '#FFF')
        hist_header.addWidget(self.btn_reset)
        tab3_layout.addLayout(hist_header)

        # Stat cards row
        stats_row = QHBoxLayout()
        stats_row.setSpacing(12)
        self._hist_sessions_card = self._make_stat_card("Sessions", "0")
        self._hist_shots_card = self._make_stat_card("Shots", "0")
        self._hist_avg_card = self._make_stat_card("Avg Score", "--")
        self._hist_best_card = self._make_stat_card("Best", "--")
        for c in [self._hist_sessions_card, self._hist_shots_card, self._hist_avg_card, self._hist_best_card]:
            stats_row.addWidget(c)
        tab3_layout.addLayout(stats_row)

        # Session list
        self.list_history = QListWidget()
        self.list_history.setStyleSheet(f"""
            QListWidget {{
                background: {COLORS['bg_secondary']};
                color: {COLORS['text_primary']};
                border: 1px solid {COLORS['border']};
                border-radius: 12px;
                padding: 8px;
                font-size: 13px;
            }}
            QListWidget::item {{
                padding: 8px;
                border-radius: 6px;
            }}
            QListWidget::item:selected {{
                background: {COLORS['bg_tertiary']};
            }}
        """)
        self.list_history.itemClicked.connect(self._on_history_item_clicked)
        tab3_layout.addWidget(self.list_history, 1)

        self.tabs.addTab(tab3, "History")

    def _build_settings_tab(self):
        tab4 = QWidget()
        tab4.setStyleSheet(f"background: {COLORS['bg_primary']};")
        tab4_layout = QVBoxLayout(tab4)
        tab4_layout.setContentsMargins(24, 24, 24, 24)
        tab4_layout.setSpacing(20)

        settings_title = QLabel("Settings")
        settings_title.setFont(QFont("Segoe UI", 24, QFont.Bold))
        settings_title.setStyleSheet(f"color: {COLORS['text_primary']};")
        tab4_layout.addWidget(settings_title)

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

        tab4_layout.addWidget(target_section)
        tab4_layout.addSpacing(16)

        # COM Port
        port_label = QLabel("COM Port")
        port_label.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 11px; text-transform: uppercase; letter-spacing: 1px;")
        tab4_layout.addWidget(port_label)

        self.cmb_com_port = QComboBox()
        self.cmb_com_port.setStyleSheet(f"""
            QComboBox {{
                background: {COLORS['bg_tertiary']};
                color: #FFFFFF;
                border: 2px solid {COLORS['border']};
                border-radius: 8px;
                padding: 12px 16px;
                font-size: 13px;
            }}
            QComboBox QAbstractItemView {{
                background: {COLORS['bg_tertiary']};
                color: #FFFFFF;
                selection-background-color: {COLORS['accent_good']};
                selection-color: #000000;
            }}
        """)
        tab4_layout.addWidget(self.cmb_com_port)
        tab4_layout.addSpacing(16)

        tab4_layout.addStretch()

        self.btn_exit = QPushButton("Exit Application")
        self.btn_exit.setCursor(Qt.PointingHandCursor)
        self.btn_exit.clicked.connect(self.exit_app)
        self._stylized_button(self.btn_exit, COLORS['accent_bad'], '#FFF')
        tab4_layout.addWidget(self.btn_exit)

        self.tabs.addTab(tab4, "Settings")

    def _make_stat_card(self, title, value):
        card = QFrame()
        card.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_tertiary']};
                border: 1px solid {COLORS['border']};
                border-radius: 10px;
                padding: 12px 16px;
            }}
        """)
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(4, 4, 4, 4)
        card_layout.setSpacing(2)

        lbl_title = QLabel(title.upper())
        lbl_title.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 9px; font-weight: 700; letter-spacing: 0.5px;")
        lbl_title.setFont(QFont("Segoe UI", 9, QFont.Bold))
        card_layout.addWidget(lbl_title)

        lbl_value = QLabel(value)
        lbl_value.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 24px; font-weight: 700;")
        lbl_value.setFont(QFont("Segoe UI", 24, QFont.Bold))
        card_layout.addWidget(lbl_value)
        return card

    def _on_history_item_clicked(self, item):
        pass  # TODO: populate shot analysis tab with selected shot

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Escape:
            self.exit_app()
        super().keyPressEvent(event)

    def exit_app(self):
        self.timer.stop()
        if self.live_window:
            self.live_window.close()
        self.close()

    def change_mode(self):
        self.detector.trigger_mode = self.cmb_mode.currentIndex()
        if self.detector.trigger_mode == 1:
            self.spin_jerk.setValue(LIVE_FIRE_DEFAULT_JERK)
            self.spin_piezo.setValue(LIVE_FIRE_DEFAULT_PIEZO)
        else:
            self.spin_jerk.setValue(DEFAULT_ACCEL_THRESH)
            self.spin_piezo.setValue(DEFAULT_PIEZO_MIN)

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

    def change_view_mode(self, index):
        """Handle view mode dropdown change."""
        issf_enabled = (index == 0)  # First option is ISSF

        # Update shot trace canvas if it exists
        if hasattr(self, 'shot_trace_canvas'):
            self.shot_trace_canvas.set_issf_mode(issf_enabled)

    def update_thresholds(self):
        self.detector.accel_thresh = self.spin_jerk.value()
        self.detector.piezo_thresh = self.spin_piezo.value()

    def start_calibration(self, auto=False):
        self.calib_buffer = []
        self.calibrating  = True
        self._auto_calibrating = auto
        if auto:
            self.btn_calib.setText("AUTO-CALIBRATING...")
            self._stylized_button(self.btn_calib, COLORS['accent_ok'], '#000')
        else:
            self.btn_calib.setText("Calibrating... DO NOT MOVE")
            self._stylized_button(self.btn_calib, COLORS['accent_ok'], '#000')

    def do_tare(self):
        if not self.detector.is_calibrated:
            self.lbl_status.setText("CALIBRATE FIRST")
            self.lbl_status.setStyleSheet(
                f"background: #663300; font-size: 14px; font-weight: 700; "
                f"border-radius: 8px; padding: 10px;")
            return
        self.detector.tare()
        self.btn_tare.setText("✓ TARE APPLIED")
        self._stylized_button(self.btn_tare, '#44AA44', '#FFF', '#88FF88')
        QTimer.singleShot(1500, lambda: (
            self.btn_tare.setText("TARE — Re-Zero Aim"),
            self._stylized_button(self.btn_tare, '#1B5E20', COLORS['accent_good'], COLORS['accent_good'])))

    def reset_session(self):
        self.list_history.clear()
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.shot_trace_canvas.clear_trace()
        self.per_shot_stats.clear()
        self.session_stats.clear()
        self.lbl_stability_score.setText("--")
        self.lbl_stability_score.setStyleSheet(f"font-size: 42px; font-weight: 200; color: {COLORS['text_muted']};")
        self.lbl_stability_grade.setText("")
        self.lbl_shooting_score.setText("--")
        self.lbl_shooting_score.setStyleSheet(f"font-size: 42px; font-weight: 200; color: {COLORS['text_muted']};")
        self.lbl_shooting_grade.setText("")
        self.lbl_shot_count.setText("Shots: 0")

    def toggle_recording(self):
        pass  # TODO: implement recording toggle

    def _update_status_display(self, state):
        cfg = {
            "IDLE":        ("WAITING FOR STABILITY", f"background:{COLORS['status_idle']};color:#AAA;"),
            "ARMING":      ("STEADY...",              f"background:{COLORS['status_arming']};color:white;"),
            "ARMED":       ("READY",                  f"background:{COLORS['status_armed']};color:white;border:2px solid {COLORS['accent_good']};"),
            "POST_GATHER": ("DETECTED - GATHERING",   f"background:{COLORS['status_armed']};color:white;border:2px solid white;"),
            "COOLDOWN":    ("SHOT RECORDED",          f"background:{COLORS['status_cooldown']};color:white;"),
        }
        if state in cfg:
            text, style = cfg[state]
            self.lbl_status.setText(text)
            self.lbl_status.setStyleSheet(
                f"QLabel {{ font-size: 14px; font-weight: 700; border-radius: 8px; padding: 10px; {style} }}")

    def _score_color(self, score):
        if score >= 95: return COLORS.get('score_elite', COLORS['accent_good'])
        if score >= 85: return COLORS.get('score_expert', COLORS['accent_good'])
        if score >= 70: return COLORS.get('score_advanced', COLORS['accent_ok'])
        if score >= 50: return COLORS.get('score_intermediate', COLORS['accent_ok'])
        return COLORS.get('score_beginner', COLORS['accent_bad'])

    def _letter_grade(self, score):
        if score >= 97: return 'A+'
        if score >= 93: return 'A'
        if score >= 90: return 'A-'
        if score >= 87: return 'B+'
        if score >= 83: return 'B'
        if score >= 80: return 'B-'
        if score >= 77: return 'C+'
        if score >= 73: return 'C'
        if score >= 70: return 'C-'
        if score >= 60: return 'D'
        return 'F'

    def update_loop(self):
        if hasattr(self.ser, 'update_sim'):
            self.ser.update_sim()

        count = 0
        while self.ser.in_waiting >= PACKET_SIZE and count < MAX_PACKETS_PER_TICK:
            count += 1
            pkt = parse_binary_packet(self.ser)
            if not pkt:
                continue

            if self.calibrating:
                self.calib_buffer.append(pkt)
                if len(self.calib_buffer) >= CALIBRATION_SAMPLE_COUNT:
                    if self.detector.calibrate(self.calib_buffer):
                        self.calibrating = False
                        self.btn_calib.setText("CALIBRATED ✓")
                        self._stylized_button(self.btn_calib, COLORS['accent_blue'], '#FFF')
                    else:
                        self.calib_buffer = []
                continue

            if not self.detector.is_calibrated:
                self.start_calibration(auto=True)

            shot_res, bat, rot, jerk, piezo = self.detector.process(pkt)
            self.lbl_telem.setText(
                f"Jerk:  {jerk:.1f}\nPiezo: {piezo}\n"
                f"Rot:   {rot:.2f}\nBat:   {bat}%")

            self._update_status_display(self.detector.state)
            self.detector.auto_tare()

            # Update aim canvas
            recent_x = list(self.detector.trace_x)
            recent_y = list(self.detector.trace_y)
            if recent_x:
                cx = recent_x[-1]
                cy = recent_y[-1]
                self.aim_canvas.update_aim(
                    recent_x, recent_y, cx, cy, self.detector.is_calibrated)

            # Update piezo display
            self.lbl_big_piezo.setText(str(int(piezo)))
            self.lbl_big_piezo.setStyleSheet(
                f"font-size: 36px; font-weight: 200; color: {COLORS['text_primary']};")
            bar_w = int(min(piezo / 4095, 1.0) * (self.piezo_bar_container.width() - 8))
            self.piezo_bar_inner.resize(bar_w, 4)
            self.lbl_piezo_minmax.setText(f"0 / {int(piezo)}")

            if shot_res:
                score = shot_res['score']
                piezo_val = shot_res['piezo']
                c_hex = self._score_color(score)
                grade = self._letter_grade(score)

                self.lbl_stability_score.setText(f"{int(score)}")
                self.lbl_stability_score.setStyleSheet(
                    f"font-size: 42px; font-weight: 200; color: {c_hex};")
                self.lbl_stability_grade.setText(grade)
                self.lbl_stability_grade.setStyleSheet(
                    f"font-size: 22px; font-weight: 600; color: {c_hex};")

                self.lbl_shooting_score.setText(f"{int(score)}")
                self.lbl_shooting_score.setStyleSheet(
                    f"font-size: 42px; font-weight: 200; color: {c_hex};")
                self.lbl_shooting_grade.setText(grade)
                self.lbl_shooting_grade.setStyleSheet(
                    f"font-size: 22px; font-weight: 600; color: {c_hex};")

                # Phase scores
                for phase_lbl, score_attr in [("HOLD", 'hold_score'),
                                               ("PRESS", 'press_score'),
                                               ("RECOIL", 'recoil_score'),
                                               ("FT", 'ft_score')]:
                    ph_val = self.findChild(QLabel, f"lbl_{score_attr}")
                    if ph_val:
                        s = shot_res.get(score_attr, 0) or 0
                        ph_val.setText(f"{int(s)}")

                # Shot trace canvas
                self.shot_trace_canvas.set_trace(
                    hold=shot_res.get('hold'),
                    press=shot_res.get('press'),
                    recoil=shot_res.get('recoil'),
                    score=score,
                    impact_x_cm=shot_res.get('impact_x_cm', 0),
                    impact_y_cm=shot_res.get('impact_y_cm', 0),
                    shot_idx=len(self.list_history) + 1,
                )

                # Per-shot stats
                self.per_shot_stats.populate(shot_res)

                # History list
                self.list_history.insertItem(
                    0, f"{datetime.now().strftime('%H:%M:%S')} "
                       f"- Score: {score:.1f} (Pz:{piezo_val})")

                # Shot count
                shot_count = self.list_history.count()
                self.lbl_shot_count.setText(f"Shots: {shot_count}")

                log_shot_db(self.session_id, score, 0.0, "Auto")


# ================= ENTRY POINT =================

if __name__ == '__main__':
    setup_database()
    app = QApplication(sys.argv)

    logger.info("Attempting connection to %s...", BLUETOOTH_COM_PORT)

    # Windows Bluetooth SPP ports (especially on reconnect) often raise
    # OSError 121 "semaphore timeout" because the RF link isn't fully
    # established yet even though the COM port is registered.
    # Fix: retry opening the port up to MAX_SERIAL_RETRIES times.
    MAX_SERIAL_RETRIES = 10
    SERIAL_RETRY_DELAY = 2.0   # seconds between retries

    ser = None
    for attempt in range(1, MAX_SERIAL_RETRIES + 1):
        try:
            logger.info("Serial open attempt %d/%d on %s...",
                        attempt, MAX_SERIAL_RETRIES, BLUETOOTH_COM_PORT)
            ser = serial.Serial(BLUETOOTH_COM_PORT, BAUD_RATE, timeout=0.5)
            logger.info("Port opened successfully.")
            break
        except OSError as e:
            # Error 121 = semaphore timeout (BT link not ready yet)
            # Error   2 = port not found (device not paired/connected)
            logger.warning("Open failed (attempt %d): %s", attempt, e)
            if attempt < MAX_SERIAL_RETRIES:
                logger.info("Retrying in %.0fs — make sure ESP32 is on and paired...",
                            SERIAL_RETRY_DELAY)
                time.sleep(SERIAL_RETRY_DELAY)
        except Exception as e:
            logger.warning("Unexpected error opening port: %s", e)
            break

    if ser is not None and ser.is_open:
        if perform_auth(ser):
            logger.info("Hardware Verified.")
            win = MainWindow(ser)
            win.show()
            sys.exit(app.exec_())
        else:
            logger.error("Hardware Authentication Failed. Switching to simulation.")
            ser.close()
            ser = None

    if ser is None or not ser.is_open:
        logger.info(">> SWITCHING TO SIMULATION MODE <<")
        ser = MockSerial()
        win = MainWindow(ser)
        win.setWindowTitle(win.windowTitle() + " [SIMULATION MODE]")
        win.show()
        sys.exit(app.exec_())