#!/usr/bin/env python3
"""
STASYS Receiver v4.0 - Professional UI Polish
Polished to match MantisX quality:
  - Modern dark color scheme with premium feel
  - Refined tab structure
  - Canvas-based live monitor with smooth animations
  - Better typography and spacing
  - Session summary analytics
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
    QHBoxLayout, QPushButton, QLabel, QListWidget, QListWidgetItem,
    QCheckBox, QComboBox, QDoubleSpinBox, QGridLayout, QFrame, QTabWidget,
    QScrollArea, QSlider, QProgressBar, QFileDialog, QMessageBox, QSplitter)
from PyQt5.QtCore import QTimer, Qt, QRectF, QPointF, QSize
from PyQt5.QtGui import QFont, QPainter, QColor, QPen, QBrush, QLinearGradient, QPalette, QPainterPath, QRadialGradient

# ================= MANTISX-STYLE MODERN COLORS =================
COLORS = {
    # Base
    'bg_primary': '#0D0D0D',
    'bg_secondary': '#1A1A1A',
    'bg_tertiary': '#252525',
    'bg_card': '#1E1E1E',
    'bg_elevated': '#2A2A2A',

    # Text
    'text_primary': '#E8E8E8',
    'text_secondary': '#A0A0A0',
    'text_muted': '#666666',

    # Accents
    'accent_good': '#00D26A',    # 90+ score
    'accent_ok': '#FFC107',      # 70-89 score
    'accent_bad': '#FF5252',     # <70 score
    'accent_blue': '#2196F3',
    'accent_purple': '#9C27B0',

    # Score tier colors
    'score_elite':        '#FFD700',    # 95+ (Gold)
    'score_expert':        '#4CAF50',    # 85-94 (Green)
    'score_advanced':      '#2196F3',    # 70-84 (Blue)
    'score_intermediate':   '#FF9800',    # 50-69 (Orange)
    'score_beginner':      '#F44336',    # <50 (Red)

    # UI Elements
    'border': '#333333',
    'border_active': '#00D26A',
    'tab_active': '#00D26A',

    # Status
    'status_idle': '#555555',
    'status_arming': '#FF9800',
    'status_armed': '#00D26A',
    'status_cooldown': '#2196F3',
}

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
STABILITY_GYRO_LIMIT       = 2.0
STABILITY_GYRO_DISARM_MULT = 5.0
ARMED_ROT_LIMIT            = 15.0

# ── New 6-Phase Timeline (T = trigger break at index 2000) ─────────────────
# Total: 40s circular buffer, extract 23s window on trigger
# Trigger index = 2000 (20s into the 40s buffer)
#
# Phase          | Time Window    | Samples | Color  | Style
# ---------------|----------------|---------|--------|------
# Pre-Shot Rtn   | T-20 to T-12s  | 800     | Blue   | Dashed
# Approach      | T-12 to T-4s   | 800     | Cyan   | Solid
# Hold          | T-4 to T-1s    | 300     | Green  | Solid
# Press         | T-1 to T-0     | 100     | Yellow | Solid
# Break         | T-0 (instant)  | 1       | Orange | Dot
# Follow-Through | T-0 to T+3s    | 300     | Red    | Solid

PRESHOT_ROUTINE_DURATION_IDX = 800    # 8s at 100Hz
APPROACH_SETTLE_DURATION_IDX = 800    # 8s at 100Hz
HOLD_DURATION_IDX = 300              # 3s at 100Hz (was 400 = 4s)
PRESS_DURATION_IDX = 100             # 1s at 100Hz (unchanged)
BREAK_DURATION_IDX = 1              # T-0 marker (single sample)
FOLLOWTHROUGH_DURATION_IDX = 300   # 3s at 100Hz (was 1600 = 16s)
TRIGGER_INDEX = 2000                # Fixed trigger position in 40s buffer
TOTAL_HISTORY_NEEDED = 4000        # 40s circular buffer (was 6710)

# --- PIEZO RANGE FIX ---
# Firmware oversamples at 1kHz (10 reads/packet) and picks the PEAK piezo.
# Feinwerkbau piezo typically produces 20-80 idle noise, 100-3000+ on click.
# Tune DEFAULT_PIEZO_MIN above the idle noise floor you observe in telemetry.
DEFAULT_PIEZO_MIN       = 20          # was 100 — lowered for Feinwerkbau (may need 10-20)
PIEZO_MAX_LIMIT         = 4095.0      # was 4000 — matches uint16_t max

# --- Dry Fire Shot Detection ---
DRYFIRE_STABILITY_WINDOW_MS  = 500    # longer stability for dry fire (mode 0)
DRYFIRE_PIEZO_SUSTAINED      = 50     # sustained contact threshold (above noise floor)
DRYFIRE_PIEZO_CONFIRM_COUNT  = 5      # consecutive samples (50ms at 100Hz)
MODE0_TRIGGER_CONFIRM_COUNT  = 5      # mode 0: 5 consecutive samples above thresh
MODE1_TRIGGER_CONFIRM_COUNT  = 3      # mode 1: 3 consecutive samples above jerk thresh
MIN_ARMING_CONFIRM_COUNT     = 10     # must stay in ARMED 100ms before triggering
ARMED_ROT_DISARM_THRESHOLD   = 5.0     # rotation > 5 rad/s resets ARMED → IDLE

DEFAULT_ACCEL_THRESH    = 8.0
LIVE_FIRE_JERK_MULT     = 1.5
LIVE_FIRE_DEFAULT_JERK  = 15.0
LIVE_FIRE_DEFAULT_PIEZO = 4095

CALIBRATION_SAMPLE_COUNT = 100
MIN_CALIBRATION_SAMPLES  = 10

LIVE_TRACE_LENGTH    = 50
MONITOR_TRACE_LENGTH = 100
COOLDOWN_DURATION    = 0.5
TRAIL_MOVEMENT_THRESHOLD = 0.0005  # rad — min movement to draw a trail segment; suppresses gyro noise tail at rest
MAX_PACKETS_PER_TICK = 10

SCORE_PENALTY_TRAVEL = 1200.0
SCORE_PENALTY_JERK   = 5000.0

FIREARM_MULTIPLIERS       = {'Pistol':1.0,'Rifle':0.7,'Archery':1.3,'Shotgun':0.9}
TRAINING_MODE_MULTIPLIERS = {'Dry Fire':1.0,'Live Fire':0.8}
DEFAULT_FIREARM           = 'Pistol'
DEFAULT_TRAINING_MODE     = 'Dry Fire'

# ── STABILITY SCORE (MantisX-style) ───────────────────────────────────────────
# Stability = how steady the shooter is across all phases (0–100)
# Components weighted: preshot (10%) + hold (25%) + press (30%) + recoil (20%) + ft (15%)
#   Pre-Shot: NPA setup / breathing rhythm (looser scale since it's wider aim)
#   Hold:     stability window — tightest zone scale
#   Press:    trigger squeeze
#   Recoil:   peak displacement during recoil
#   FT:       recovery toward aim center
# Lock Time is NOT scored — mechanical latency, not technique-dependent.

WEIGHT_STABILITY_PRESHOT   = 0.10
WEIGHT_STABILITY_APPROACH  = 0.20
WEIGHT_STABILITY_HOLD      = 0.25
WEIGHT_STABILITY_PRESS     = 0.30
WEIGHT_STABILITY_FT        = 0.15

# Zone-based scoring (CEP model): score = 100 * exp(-deviation / ZONE_SCALE)
ZONE_SCALE_STABILITY_HOLD  = 0.005    # rad — ≈0.29°
ZONE_SCALE_STABILITY_PRESS = 0.008    # rad
ZONE_SCALE_STABILITY_RECOIL = 0.015   # rad
ZONE_SCALE_STABILITY_FT    = 0.012    # rad

# Letter grade thresholds
STABILITY_GRADE_THRESHOLDS = {
    'A+': 97, 'A': 93, 'A-': 90,
    'B+': 87, 'B': 83, 'B-': 80,
    'C+': 77, 'C': 73, 'C-': 70,
    'D': 60
}

# ── SHOOTING SCORE (SCATT-style) ─────────────────────────────────────────────
R_SCATT = 0.015  # characteristic radius in radians (≈0.86°)

# Hold stability thresholds (in radians)
HOLD_STD_EXCELLENT = 0.003
HOLD_STD_GOOD      = 0.007
HOLD_STD_OK        = 0.015
HOLD_STD_POOR      = 0.030

# Recoil recovery threshold (radians)
RECOVERY_THRESHOLD    = 0.010
RECOVERY_TIME_EXCELLENT = 40
RECOVERY_TIME_GOOD    = 80
RECOVERY_TIME_OK      = 120
RECOVERY_TIME_POOR    = 180

# A2C error classification thresholds (radians)
A2C_ANTICIPATION_THRESH  = 0.005
A2C_FLINCH_THRESH        = 0.015
A2C_HEEL_LIMIT           = -0.005
A2C_THUMB_LIMIT          =  0.005

# --- AUTH TIMING FIX ---
# Increased to 12s to match the firmware's 10s READY broadcast window
# Python needs the extra 2s margin for serial open + buffer flush
AUTH_TIMEOUT          = 20.0          # was 5.0
AUTH_RESPONSE_TIMEOUT = 3.0           # was 2.0
AUTH_CHALLENGE_LENGTH = 16

PLOT_RANGE  = 0.05
RING_RADII  = [0.01, 0.02, 0.03]

# ── Target & Impact ─────────────────────────────────────────────────────────
DEFAULT_TARGET_DISTANCE = 10.0   # metres — user-configurable in Shot Analysis tab

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


# ================= DATABASE =================

def setup_database():
    """Create/upgrade database with sessions and shot_traces tables."""
    with sqlite3.connect(DB_FILE) as conn:
        cur = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='shots'")
        if cur.fetchone():
            cols = {row[1] for row in conn.execute("PRAGMA table_info(shots)")}
            if cols != {'id', 'timestamp', 'session_id', 'score', 'cant', 'mode'}:
                logger.warning("DB schema mismatch. Recreating table.")
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

        # Create sessions table
        conn.execute('''CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT UNIQUE NOT NULL,
            start_time DATETIME NOT NULL,
            end_time DATETIME,
            mode TEXT,
            shot_count INTEGER DEFAULT 0)''')

        # Create shot_traces table for storing aim traces
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

        # Add new columns if they don't exist (migration for existing DBs)
        existing_cols = {row[1] for row in conn.execute("PRAGMA table_info(shot_traces)")}
        new_cols = {'error_severity', 'coaching', 'impact_x_cm', 'impact_y_cm',
                    'target_distance', 'stability_score', 'shooting_score',
                    'stability_grade', 'shooting_grade', 'firearm', 'training_mode'}
        for col in new_cols:
            if col not in existing_cols:
                try:
                    conn.execute(f"ALTER TABLE shot_traces ADD COLUMN {col} TEXT")
                except Exception:
                    pass

        conn.commit()

        # Create device_calibrations table for persistent per-device calibration
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


# ── Shot Group Analyzer ─────────────────────────────────────────────────────

class ShotGroupAnalyzer:
    """
    Analyzes a session's shot group to produce MantisX-level group statistics.
    Operates on a list of shot result dicts (from shot_history or DB rows).
    """

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

        # Group center
        center_x = self._mean(impact_x)
        center_y = self._mean(impact_y)

        # Distances from group center
        distances = [math.sqrt((ix - center_x) ** 2 + (iy - center_y) ** 2)
                     for ix, iy in zip(impact_x, impact_y)]

        # Spread radius (max distance from group center)
        spread_cm = max(distances) if distances else 0.0

        # Angular dispersion (std dev of shots from group center, in mrad)
        angular_dispersion = self._std(distances) / 10.0 if distances else 0.0  # cm → mm → /10

        # MOA at default target distance (1 MOA ≈ 2.91 cm at 10m, 5.25cm at 25m)
        # Convert spread (cm) to MOA: MOA = spread_cm / (distance_m * 0.02909)
        target_d = DEFAULT_TARGET_DISTANCE
        spread_moa = spread_cm / (target_d * 0.02909) if target_d > 0 else 0.0

        # Group rating based on spread MOA per shot count
        rating = self._rate_group(spread_moa, len(self.shots))

        # Error distribution
        error_counts = {}
        for s in self.shots:
            err = s.get('error_type', 'NONE')
            if err and err != 'NONE':
                error_counts[err] = error_counts.get(err, 0) + 1

        # Score trend (list of scores)
        stability_scores = [s.get('stability_score', 0) for s in self.shots if s.get('stability_score')]
        shooting_scores  = [s.get('shooting_score',  0) for s in self.shots if s.get('shooting_score')]
        scores = [s.get('score', 0) for s in self.shots]

        # SCATT-style R_50 (median spread) and R_100 (extreme spread)
        sorted_dist = sorted(distances)
        r_50 = self._median(sorted_dist) if sorted_dist else 0.0
        r_100 = spread_cm
        # Group consistency score: 100 * exp(-R_50 / R_scatt)
        group_consistency_score = min(100.0, 100.0 * math.exp(-r_50 / (R_SCATT * 100.0 * target_d))) if target_d > 0 else 0.0

        return {
            'shot_count': len(self.shots),
            'center_x_cm': round(center_x, 2),
            'center_y_cm': round(center_y, 2),
            'spread_cm': round(spread_cm, 2),
            'angular_dispersion_mrad': round(angular_dispersion, 3),
            'spread_moa': round(spread_moa, 2),
            'group_rating': rating,
            # SCATT metrics
            'r_50_cm': round(r_50, 2),
            'r_100_cm': round(r_100, 2),
            'group_consistency_score': round(group_consistency_score, 1),
            # Score aggregates
            'stability_score_avg': round(self._mean(stability_scores), 1) if stability_scores else 0.0,
            'shooting_score_avg':  round(self._mean(shooting_scores),  1) if shooting_scores  else 0.0,
            'error_distribution': error_counts,
            'scores': scores,
        }

    def _rate_group(self, spread_moa, n_shots):
        """Rate group quality based on spread MOA.

        For groups of 5 shots:
          Excellent: < 1 MOA, Good: 1-2, Fair: 2-4, Poor: > 4
        Scale adjusts for smaller/larger groups.
        """
        if n_shots == 0:
            return "N/A"
        # Normalize threshold: tight groups stay tight regardless of size
        threshold = spread_moa
        if threshold < 1.0:
            return "Excellent"
        elif threshold < 2.0:
            return "Good"
        elif threshold < 4.0:
            return "Fair"
        else:
            return "Poor"


# ── Device Calibration Persistence ────────────────────────────────────────

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
                  stability_score=0.0, shooting_score=0.0,
                  stability_grade='', shooting_grade='',
                  firearm='', training_mode=''):
    """Log a shot with complete 4-phase aim trace data for replay."""
    aim_trace_json = json.dumps(aim_trace)
    with sqlite3.connect(DB_FILE) as conn:
        conn.execute('''INSERT INTO shot_traces
                        (session_id, shot_number, timestamp, score, grade,
                         a2c_angle, a2c_mag, hold_score, press_score,
                         recoil_score, ft_score, hold_stability,
                         recoil_recovery_ms, error_type, error_severity, coaching,
                         impact_x_cm, impact_y_cm, target_distance,
                         piezo_value, aim_trace,
                         stability_score, shooting_score,
                         stability_grade, shooting_grade,
                         firearm, training_mode)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                    (session_id, shot_number, datetime.now(), score, grade,
                     a2c_angle, a2c_mag, hold_score, press_score,
                     recoil_score, ft_score, hold_stability,
                     recoil_recovery_ms, error_type, error_severity, coaching,
                     impact_x_cm, impact_y_cm, target_distance,
                     piezo, aim_trace_json,
                     stability_score, shooting_score,
                     stability_grade, shooting_grade,
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
                                      piezo_value, aim_trace,
                                      stability_score, shooting_score,
                                      stability_grade, shooting_grade
                                FROM shot_traces WHERE session_id = ? ORDER BY shot_number''',
                           (session_id,)).fetchall()
        shots = []
        for row in rows:
            shots.append({
                'shot_number': row['shot_number'],
                'timestamp': row['timestamp'],
                'score': row['score'],
                'grade': row['grade'] if 'grade' in row.keys() else '',
                'stability_score': row['stability_score'] if 'stability_score' in row.keys() else 0.0,
                'shooting_score': row['shooting_score'] if 'shooting_score' in row.keys() else 0.0,
                'stability_grade': row['stability_grade'] if 'stability_grade' in row.keys() else '',
                'shooting_grade': row['shooting_grade'] if 'shooting_grade' in row.keys() else '',
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

                            # ESP32 uses raw SHA-256(challenge || SECRET_KEY), NOT HMAC.
                            # Matches the exact same construction as main2.py.
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
        self.dry_fire_mode = True  # enhanced filtering for dry fire (mode 0)

        self.is_calibrated = False
        self.gyro_bias     = [0.0, 0.0, 0.0]
        self.accel_bias    = [0.0, 0.0, 0.0]

        self.q      = np.array([1., 0., 0., 0.], dtype=np.float64)
        self.q_tare = np.array([1., 0., 0., 0.], dtype=np.float64)

        self.state              = "IDLE"
        self.state_timer        = 0.0
        self.gather_counter     = 0
        self.last_trigger_piezo = 0
        self.pending_shot_result = None   # populated by _commit_trigger for instant display
        self.shot_result_returned = False  # prevent returning same result on every packet
        self.last_trigger_piezo_for_result = 0

        # Index of the sample AT the moment the shot triggered (ARMED→POST_GATHER)
        self.trigger_break_idx  = -1

        # Continuous recording buffer state
        self.is_recording = True   # Always recording when calibrated
        self.frozen_trace_x = None  # Snapshot on trigger
        self.frozen_trace_y = None  # Snapshot on trigger
        self.frozen_trigger_idx = -1  # Index of trigger break in frozen buffer

        # Trace buffer: hold + press + recoil + follow-through
        self.trace_x  = deque([0.0] * TOTAL_HISTORY_NEEDED, maxlen=TOTAL_HISTORY_NEEDED)
        self.trace_y  = deque([0.0] * TOTAL_HISTORY_NEEDED, maxlen=TOTAL_HISTORY_NEEDED)
        self.curr_x   = 0.0
        self.curr_y   = 0.0

        # Mount direction: "forward" (default) or "backward" (flip barrel)
        self.mount_direction = "forward"

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

        # Dry Fire Shot Detection Tracking
        self.armed_sample_count     = 0    # samples spent in ARMED state without triggering
        self.piezo_sustained_count  = 0    # consecutive samples above sustained threshold (mode 0)
        self.jerk_sustained_count   = 0    # consecutive samples above jerk threshold (mode 1)
        self.pending_trigger        = False # trigger condition met but not yet confirmed
        self.trigger_confirm_count  = 0    # countdown for trigger confirmation

    # ── Calibration & Tare ───────────────────────────────────────────────────

    def calibrate(self, samples, source="manual"):
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

        self.q = _quat_from_accel(mean_ax, mean_ay, mean_az)
        self._apply_tare()
        self.is_calibrated = True

        self.accel_bias = [mean_ax, mean_ay, mean_az]

        if source == "auto_loaded":
            logger.info("Calibration loaded from DB for device: %.3f, %.3f, %.3f",
                        *self.gyro_bias)
        else:
            logger.info("Calibrated (source=%s) — gyro bias: [%.4f, %.4f, %.4f]",
                        source, *self.gyro_bias)
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
        self.trace_x = deque([0.0] * TOTAL_HISTORY_NEEDED, maxlen=TOTAL_HISTORY_NEEDED)
        self.trace_y = deque([0.0] * TOTAL_HISTORY_NEEDED, maxlen=TOTAL_HISTORY_NEEDED)
        self.is_recording = True

    def freeze_buffer(self):
        """Called when trigger fires — copies current circular buffer for phase extraction.
        The buffer always holds the last 40s (4000 samples at 100Hz).
        Trigger break is always at index TRIGGER_INDEX (2000) in the frozen copy."""
        self.is_recording = False
        self.frozen_trace_x = list(self.trace_x)
        self.frozen_trace_y = list(self.trace_y)
        self.frozen_trigger_idx = TRIGGER_INDEX  # Always 2000 in the 40s buffer

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

        # Check if stationary
        if self._is_stationary():
            self.stationary_count += 1
        else:
            self.stationary_count = 0

        if self.stationary_count < self.stationary_needed:
            return

        # Check if drift is significant
        aim_offset = math.sqrt(self.curr_x**2 + self.curr_y**2)
        if aim_offset < self.drift_threshold:
            return

        # Apply auto-tare silently
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
        direction_sign = -1.0 if self.mount_direction == "backward" else 1.0
        self.curr_x = math.atan2(-v[1], v[2]) * SCREEN_X_SIGN * direction_sign
        self.curr_y = math.atan2( v[0], v[2]) * SCREEN_Y_SIGN * direction_sign

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
                self.is_recording = True  # Resume continuous recording

        elif self.state == "IDLE":
            if rot_mag < STABILITY_GYRO_LIMIT:
                self.state       = "ARMING"
                self.state_timer = 0.0
                self.armed_sample_count    = 0
                self.piezo_sustained_count = 0
                self.jerk_sustained_count  = 0
                self.pending_trigger        = False
                self.trigger_confirm_count = 0

        elif self.state == "ARMING":
            if rot_mag > STABILITY_GYRO_LIMIT:
                self.state = "IDLE"
            else:
                self.state_timer += DT * 1000.0
                stability_window = DRYFIRE_STABILITY_WINDOW_MS if (self.dry_fire_mode and self.trigger_mode == 0) else STABILITY_WINDOW_MS
                if self.state_timer >= stability_window:
                    self.state = "ARMED"
                    self.armed_sample_count    = 0
                    self.piezo_sustained_count = 0
                    self.jerk_sustained_count  = 0
                    self.pending_trigger        = False
                    self.trigger_confirm_count = 0

        elif self.state == "ARMED":
            self.armed_sample_count += 1

            # Disarm if rotation spikes — return to IDLE and reset tracking
            if rot_mag > ARMED_ROT_DISARM_THRESHOLD:
                self.state = "IDLE"
                self.armed_sample_count = 0
                self.piezo_sustained_count = 0
                self.jerk_sustained_count = 0
                self.pending_trigger = False
                self.trigger_confirm_count = 0
                logger.debug("ARMED disarmed — rotation too high (%.2f)", rot_mag)
            elif self.armed_sample_count >= MIN_ARMING_CONFIRM_COUNT:
                # Build-up phase: count consecutive samples meeting trigger condition
                if self.trigger_mode == 1:
                    jerk_thresh = self.accel_thresh * LIVE_FIRE_JERK_MULT
                    if jerk_mag > jerk_thresh:
                        self.jerk_sustained_count += 1
                        if not self.pending_trigger:
                            self.pending_trigger = True
                            self.trigger_confirm_count = MODE1_TRIGGER_CONFIRM_COUNT
                        self.trigger_confirm_count -= 1
                        if self.trigger_confirm_count <= 0:
                            self._commit_trigger(piezo)
                    else:
                        self.jerk_sustained_count = 0
                        if self.pending_trigger and self.trigger_confirm_count > 0:
                            self.trigger_confirm_count -= 1
                        if self.trigger_confirm_count <= 0:
                            self.pending_trigger = False
                            self.trigger_confirm_count = 0
                else:
                    # Mode 0: dual-threshold piezo filtering (dry_fire_mode only)
                    if self.piezo_thresh <= piezo <= PIEZO_MAX_LIMIT:
                        self.piezo_sustained_count += 1
                        if self.dry_fire_mode:
                            confirm_needed = DRYFIRE_PIEZO_CONFIRM_COUNT
                        else:
                            confirm_needed = MODE0_TRIGGER_CONFIRM_COUNT
                        if not self.pending_trigger:
                            self.pending_trigger = True
                            self.trigger_confirm_count = confirm_needed
                        self.trigger_confirm_count -= 1
                        if self.trigger_confirm_count <= 0:
                            if rot_mag < ARMED_ROT_LIMIT:
                                self._commit_trigger(piezo)
                            else:
                                logger.debug(
                                    "Piezo confirmed but rotation too high (%.2f > %.1f)",
                                    rot_mag, ARMED_ROT_LIMIT)
                                self.pending_trigger = False
                                self.trigger_confirm_count = 0
                                self.piezo_sustained_count = 0
                    elif piezo > 0:
                        if self.pending_trigger and self.trigger_confirm_count > 0:
                            self.trigger_confirm_count -= 1
                        if self.trigger_confirm_count <= 0:
                            self.pending_trigger = False
                            self.trigger_confirm_count = 0
                        self.piezo_sustained_count = 0

        elif self.state == "POST_GATHER":
            self.gather_counter -= 1
            # Return cached instant result on the very next packet after trigger
            if not self.shot_result_returned and self.pending_shot_result is not None:
                shot_data              = self.pending_shot_result
                self.shot_result_returned = True
            # After 20s of gathering, finalize and clean up (no longer needed for display)
            if self.gather_counter <= 0:
                self.state       = "COOLDOWN"
                self.state_timer = COOLDOWN_DURATION
                self.pending_shot_result    = None
                self.shot_result_returned   = False

        return shot_data, bat, rot_mag, jerk_mag, piezo

    # ── Shot analysis ────────────────────────────────────────────────────────

    def _extract_shot_phases(self):
        """Extract 6-phase shot data from frozen circular buffer.

        Returns dict with phase names as keys, (x_list, y_list) tuples as values.
        Returns None if frozen buffer is invalid or too short.

        Phases extracted from 40s frozen buffer (trigger at index 2000):
          - preshot_routine: [0:800] (T-20s to T-12s)
          - approach_settle: [800:1600] (T-12s to T-4s)
          - hold: [1600:1900] (T-4s to T-1s)
          - press: [1900:2000] (T-1s to T-0)
          - break: [2000] (T-0, single point)
          - followthrough: [2000:2300] (T-0 to T+3s)
        """
        # Verify frozen buffer exists
        if self.frozen_trace_x is None or self.frozen_trace_y is None:
            return None

        # Verify buffer has enough samples for full 23s window
        min_samples = TRIGGER_INDEX + FOLLOWTHROUGH_DURATION_IDX  # 2000 + 300 = 2300
        if len(self.frozen_trace_x) < min_samples or len(self.frozen_trace_y) < min_samples:
            return None

        # Extract phases using fixed indices relative to trigger at index 2000
        preshot_routine_x = self.frozen_trace_x[0:PRESHOT_ROUTINE_DURATION_IDX]
        preshot_routine_y = self.frozen_trace_y[0:PRESHOT_ROUTINE_DURATION_IDX]

        approach_start = PRESHOT_ROUTINE_DURATION_IDX
        approach_end = approach_start + APPROACH_SETTLE_DURATION_IDX
        approach_settle_x = self.frozen_trace_x[approach_start:approach_end]
        approach_settle_y = self.frozen_trace_y[approach_start:approach_end]

        hold_start = approach_end
        hold_end = hold_start + HOLD_DURATION_IDX
        hold_x = self.frozen_trace_x[hold_start:hold_end]
        hold_y = self.frozen_trace_y[hold_start:hold_end]

        press_start = hold_end
        press_end = TRIGGER_INDEX
        press_x = self.frozen_trace_x[press_start:press_end]
        press_y = self.frozen_trace_y[press_start:press_end]

        break_x = self.frozen_trace_x[TRIGGER_INDEX]
        break_y = self.frozen_trace_y[TRIGGER_INDEX]

        followthrough_start = TRIGGER_INDEX
        followthrough_end = followthrough_start + FOLLOWTHROUGH_DURATION_IDX
        followthrough_x = self.frozen_trace_x[followthrough_start:followthrough_end]
        followthrough_y = self.frozen_trace_y[followthrough_start:followthrough_end]

        return {
            'preshot_routine': (preshot_routine_x, preshot_routine_y),
            'approach_settle': (approach_settle_x, approach_settle_y),
            'hold': (hold_x, hold_y),
            'press': (press_x, press_y),
            'break': (break_x, break_y),
            'followthrough': (followthrough_x, followthrough_y),
        }

    def _mean(self, vals):
        return sum(vals) / len(vals) if vals else 0.0

    def _std(self, vals):
        if len(vals) < 2:
            return 0.0
        m = self._mean(vals)
        return math.sqrt(sum((v - m) ** 2 for v in vals) / (len(vals) - 1))

    def _zone_score(self, deviation, zone_scale):
        """CEP-style scoring: score = 100 * exp(-deviation / scale).
        Returns 0–100. Tighter deviation → higher score."""
        if zone_scale <= 0:
            return 0.0
        return min(100.0, 100.0 * math.exp(-deviation / zone_scale))

    def _score_phase(self, xs, ys, zone_scale=None):
        """Score a phase by mean radial deviation from its own centroid."""
        if not xs:
            return 0.0, 0.0, 0.0
        cx = self._mean(xs)
        cy = self._mean(ys)
        devs = [math.sqrt((x - cx) ** 2 + (y - cy) ** 2) for x, y in zip(xs, ys)]
        mean_dev = self._mean(devs)
        peak_dev = max(devs) if devs else 0.0
        scale = zone_scale if zone_scale is not None else ZONE_SCALE_STABILITY_PRESS
        score = self._zone_score(mean_dev, scale)
        return score, mean_dev, peak_dev

    def _score_hold(self, hold_x, hold_y):
        """Hold stability: measure dispersion (std dev) of aim during hold phase."""
        if not hold_x:
            return 0.0, 0.0, 0.0
        std_x = self._std(hold_x)
        std_y = self._std(hold_y)
        # Composite dispersion as Euclidean std
        composite_std = math.sqrt(std_x ** 2 + std_y ** 2)
        score = 100.0 * math.exp(-composite_std / ZONE_SCALE_STABILITY_HOLD)
        return min(100.0, score), std_x, std_y

    def _score_followthrough(self, ft_x, ft_y):
        """Follow-through: how well does the shooter recover toward aim center?
        Measure mean radial deviation from the hold centroid during recovery."""
        if not ft_x:
            return 0.0, 0.0, 0.0
        cx = self._mean(ft_x)
        cy = self._mean(ft_y)
        devs = [math.sqrt((x - cx) ** 2 + (y - cy) ** 2) for x, y in zip(ft_x, ft_y)]
        mean_dev = self._mean(devs)
        # Find recovery time: first sample where deviation stays below threshold
        recovery_samples = len(devs)
        for i, d in enumerate(devs):
            if d <= RECOVERY_THRESHOLD:
                # Check if stays below threshold for at least 10 consecutive samples
                if all(devs[j] <= RECOVERY_THRESHOLD for j in range(i, min(i + 10, len(devs)))):
                    recovery_samples = i
                    break
        score = self._zone_score(mean_dev, ZONE_SCALE_STABILITY_FT)
        return min(100.0, score), recovery_samples, mean_dev

    def _classify_error(self, hold_x, hold_y, press_x, press_y,
                        ft_x, ft_y, break_x, break_y, hold_cx, hold_cy):
        """Classify the dominant shooting error based on direction and timing.

        Returns one of:
          'ANTICIPATION' — pushing toward target during press
          'FLINCH'       — large jerk spike before/during shot
          'HEEL_PRESS'  — excessive heel-side pressure (low hand)
          'THUMB_PUSH'  — thumb pushing muzzle up during press
          'FOLLOWTHROUGH'— poor recovery after recoil
          'BREATH'      — slow sinusoidal drift in hold phase
          'GUNNY'       — diagonal push (both X and Y deviate together)
          'NONE'         — no clear dominant error
        """
        if not press_x or not hold_x:
            return 'NONE'

        # A2C vector: direction from hold centroid to trigger-break point
        a2c_x = break_x - hold_cx
        a2c_y = break_y - hold_cy
        a2c_mag = math.sqrt(a2c_x ** 2 + a2c_y ** 2)

        if a2c_mag < A2C_ANTICIPATION_THRESH:
            return 'NONE'

        # ── Breath control detection ─────────────────────────────────────────
        # Check for slow sinusoidal drift in hold phase (slow X drift)
        if len(hold_x) >= 30:
            # Compute autocorr at lag ~15 samples (≈150ms at 100Hz)
            # If slow oscillation exists, X values will correlate across a ~150ms window
            hold_x_arr = np.array(hold_x)
            n = len(hold_x_arr)
            if n >= 30:
                lag = min(15, n // 2)
                mean_h = np.mean(hold_x_arr)
                var_h = np.var(hold_x_arr)
                if var_h > 1e-10:
                    autocorr = np.mean((hold_x_arr[:-lag] - mean_h) * (hold_x_arr[lag:] - mean_h)) / var_h
                    if autocorr > 0.6:
                        return 'BREATH'

        # ── GUNNY: diagonal push (both X and Y deviate together) ─────────────
        if abs(a2c_x) > A2C_FLINCH_THRESH and abs(a2c_y) > A2C_FLINCH_THRESH:
            return 'GUNNY'

        # ── Determine dominant direction ─────────────────────────────────────
        # X axis: negative = heel (left), positive = toe (right) on screen
        # Y axis: positive = thumb up, negative = heel down
        dominant_x = abs(a2c_x) > abs(a2c_y)

        if dominant_x:
            if a2c_x < 0:
                primary = 'HEEL_PRESS'
            else:
                primary = 'FOLLOWTHROUGH'
        else:
            if a2c_y > 0:
                primary = 'THUMB_PUSH'
            else:
                primary = 'ANTICIPATION'

        # Flinch detection: check for large acceleration spike before shot
        press_devs = [math.sqrt((x - hold_cx) ** 2 + (y - hold_cy) ** 2)
                      for x, y in zip(press_x, press_y)]
        hold_devs = [math.sqrt((x - hold_cx) ** 2 + (y - hold_cy) ** 2)
                     for x, y in zip(hold_x, hold_y)]
        mean_press_dev = self._mean(press_devs) if press_devs else 0.0
        mean_hold_dev = self._mean(hold_devs) if hold_devs else 0.0

        if mean_press_dev > 3 * mean_hold_dev and a2c_mag > A2C_FLINCH_THRESH:
            return 'FLINCH'

        # Anticipation if deviation spikes during press
        if mean_press_dev > 2 * mean_hold_dev:
            return 'ANTICIPATION'

        return primary

    def _error_severity(self, a2c_mag):
        """Return severity level: 'MILD', 'MODERATE', or 'SEVERE'."""
        if a2c_mag < 0.005:
            return 'MILD'
        elif a2c_mag < 0.015:
            return 'MODERATE'
        else:
            return 'SEVERE'

    def _coaching_message(self, error_type, severity):
        """Return actionable coaching text based on error type and severity."""
        messages = {
            'ANTICIPATION': {
                'MILD': "Minor push noticed. Focus on a smooth, continuous squeeze.",
                'MODERATE': "Anticipation detected. Practice surprise breaks.",
                'SEVERE': "Strong anticipation. Work on trigger control — avoid rushing the break.",
            },
            'FLINCH': {
                'MILD': "Slight flinch. Ensure finger is positioned correctly on trigger.",
                'MODERATE': "Flinch detected. Practice dry fire to desensitize.",
                'SEVERE': "Severe flinch. Focus on relaxed grip and breath control.",
            },
            'HEEL_PRESS': {
                'MILD': "Slight heel pressure. Ensure web of hand is high on grip.",
                'MODERATE': "Heel pressure detected. Adjust grip — thumb should be on top.",
                'SEVERE': "Significant heel press. Check grip position and support hand.",
            },
            'THUMB_PUSH': {
                'MILD': "Minor thumb push. Relax thumb grip.",
                'MODERATE': "Thumb pushing muzzle up. Focus on keeping thumb neutral.",
                'SEVERE': "Thumb push causing POI shift. Practice relaxed grip.",
            },
            'FOLLOWTHROUGH': {
                'MILD': "Minor follow-through issue. Maintain focus after the shot.",
                'MODERATE': "Follow-through needs work. Don't drop the gun after the break.",
                'SEVERE': "Poor follow-through. Maintain sight picture through recoil.",
            },
            'BREATH': {
                'MILD': "Slight breathing sway. Practice controlled breathing.",
                'MODERATE': "Breathing causing drift. Exhale partially before trigger break.",
                'SEVERE': "Significant breath sway. Master breath control before squeezing.",
            },
            'GUNNY': {
                'MILD': "Diagonal push. Ensure consistent grip pressure.",
                'MODERATE': "Gunny detected — check both hands have even pressure.",
                'SEVERE': "Severe gunny motion. Practice isometric tension exercises.",
            },
        }
        return messages.get(error_type, {}).get(severity, "Focus on consistent trigger technique.")

    def _letter_grade(self, score):
        """Convert numeric score to letter grade."""
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

    def _stability_letter_grade(self, score):
        """Convert numeric score (stability or shooting) to letter grade."""
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

    def _commit_trigger(self, piezo):
        """Commit a shot trigger — analyzes immediately, keeps gathering in background."""
        logger.info("SHOT TRIGGERED — Piezo: %d", piezo)
        self.last_trigger_piezo = piezo
        self.last_trigger_piezo_for_result = piezo
        self.trigger_break_idx = len(self.trace_x) - 1
        self.freeze_buffer()  # Capture 40s circular buffer for phase extraction
        # Analyze shot after buffer is frozen
        shot_result = self.analyze_shot()
        if shot_result:
            shot_result['piezo'] = piezo  # ensure correct piezo in cached result
        self.pending_shot_result = shot_result
        self.shot_result_returned = False
        self.state              = "POST_GATHER"
        self.gather_counter     = FOLLOWTHROUGH_DURATION_IDX  # 3s of post-shot follow-through
        self.armed_sample_count    = 0
        self.piezo_sustained_count = 0
        self.jerk_sustained_count  = 0
        self.pending_trigger        = False
        self.trigger_confirm_count = 0

    def analyze_shot(self):
        """6-phase shot analysis using frozen circular buffer.

        Phases extracted from 40s frozen buffer (trigger at index 2000):
          Pre-Shot Routine  — T-20s to T-12s (8s, 800 samples) blue dashed
          Approach & Settle — T-12s to T-4s (8s, 800 samples) cyan solid
          Hold             — T-4s to T-1s (3s, 300 samples) green solid
          Trigger Press    — T-1s to T-0 (1s, 100 samples) yellow solid
          Break            — T-0 (instant, 1 sample) orange dot
          Follow-Through   — T-0 to T+3s (3s, 300 samples) red solid

        Returns dict with:
          6-phase scores (preshot_routine, approach_settle, hold, press, followthrough),
          A2C metrics, bullet impact prediction, error classification,
          per-phase traces normalized to hold centroid.
        """
        phases = self._extract_shot_phases()
        if phases is None:
            return None

        # Extract phases from frozen buffer
        psr_x, psr_y = phases['preshot_routine']
        apr_x, apr_y = phases['approach_settle']
        hol_x, hol_y = phases['hold']
        pre_x, pre_y = phases['press']
        brk_x, brk_y = phases['break']
        ft_x,  ft_y  = phases['followthrough']

        if not hol_x:
            return None

        # Flip traces if mount direction is backward
        if self.mount_direction == "backward":
            psr_x = [x * -1.0 for x in psr_x]
            psr_y = [y * -1.0 for y in psr_y]
            apr_x = [x * -1.0 for x in apr_x]
            apr_y = [y * -1.0 for y in apr_y]
            hol_x = [x * -1.0 for x in hol_x]
            hol_y = [y * -1.0 for y in hol_y]
            pre_x = [x * -1.0 for x in pre_x]
            pre_y = [y * -1.0 for y in pre_y]
            ft_x  = [x * -1.0 for x in ft_x]
            ft_y  = [y * -1.0 for y in ft_y]
            brk_x = brk_x * -1.0
            brk_y = brk_y * -1.0

        # Hold centroid as A2C reference (MantisX-style)
        hold_cx = self._mean(hol_x)
        hold_cy = self._mean(hol_y)

        # Normalized traces (relative to hold centroid)
        norm_psr_x = [x - hold_cx for x in psr_x]
        norm_psr_y = [y - hold_cy for y in psr_y]
        norm_apr_x = [x - hold_cx for x in apr_x]
        norm_apr_y = [y - hold_cy for y in apr_y]
        norm_hol_x = [x - hold_cx for x in hol_x]
        norm_hol_y = [y - hold_cy for y in hol_y]
        norm_pre_x = [x - hold_cx for x in pre_x]
        norm_pre_y = [y - hold_cy for y in pre_y]
        norm_ft_x  = [x - hold_cx for x in ft_x]
        norm_ft_y  = [y - hold_cy for y in ft_y]
        norm_brk_x = brk_x - hold_cx
        norm_brk_y = brk_y - hold_cy

        # A2C: vector from hold centroid to trigger-break point
        a2c_x = norm_brk_x
        a2c_y = norm_brk_y
        a2c_mag = math.sqrt(a2c_x ** 2 + a2c_y ** 2)
        a2c_angle = math.atan2(a2c_x, -a2c_y)  # azimuth from vertical

        # ── Phase Scores ───────────────────────────────────────────────────────
        # Pre-Shot Routine: score preparation stability (NPA establishment)
        psr_score = 0.0
        if norm_psr_x:
            psr_score, _, _ = self._score_phase(
                norm_psr_x, norm_psr_y, ZONE_SCALE_STABILITY_PRESS * 2.5)

        # Approach & Settle: score convergence toward aim center
        apr_score = 0.0
        if norm_apr_x:
            apr_score, _, _ = self._score_phase(
                norm_apr_x, norm_apr_y, ZONE_SCALE_STABILITY_PRESS * 2.0)

        # Hold: score aim stability (tightest phase)
        hold_score, hold_std_x, hold_std_y = self._score_hold(norm_hol_x, norm_hol_y)

        # Trigger Press: score minimal disturbance during press
        press_score, _, _ = self._score_phase(
            norm_pre_x, norm_pre_y, ZONE_SCALE_STABILITY_PRESS)

        # Break & Lock Time: instantaneous, scored as part of A2C accuracy
        # No separate score — included in overall shot quality

        # Follow-Through: score recovery / maintained stability post-shot
        ft_score, recovery_samples, ft_mean_dev = self._score_followthrough(norm_ft_x, norm_ft_y)

        # Composite stability score (Break is instantaneous, not scored separately)
        stability_score = (psr_score * WEIGHT_STABILITY_PRESHOT
                          + apr_score * WEIGHT_STABILITY_APPROACH
                          + hold_score * WEIGHT_STABILITY_HOLD
                          + press_score * WEIGHT_STABILITY_PRESS
                          + ft_score * WEIGHT_STABILITY_FT)

        # ── Shooting Score (SCATT-style) ──────────────────────────────────────
        group_cx = getattr(self, '_group_center_x', 0.0)
        group_cy = getattr(self, '_group_center_y', 0.0)
        dist_from_group_rad = math.sqrt(
            (a2c_x - group_cx) ** 2 + (a2c_y - group_cy) ** 2)
        shooting_score = min(100.0, 100.0 * math.exp(-dist_from_group_rad / R_SCATT))

        # Directional error classification
        error_type = self._classify_error(
            hol_x, hol_y, pre_x, pre_y,
            ft_x, ft_y, brk_x, brk_y, hold_cx, hold_cy)
        error_severity = self._error_severity(a2c_mag)
        coaching = self._coaching_message(error_type, error_severity)

        # ── Bullet Impact Prediction ──────────────────────────────────────────
        target_d = getattr(self, 'target_distance', DEFAULT_TARGET_DISTANCE)
        impact_x_cm = target_d * 100.0 * math.tan(a2c_x)  # cm
        impact_y_cm = target_d * 100.0 * math.tan(a2c_y)  # cm
        impact_conf_radius = (math.sqrt(hold_std_x**2 + hold_std_y**2)
                              * target_d * 100.0 * 1.5)  # cm

        return {
            # 6-phase stability scores (0–100)
            "stability_score": round(stability_score, 1),
            "stability_grade": self._stability_letter_grade(stability_score),
            "preshot_routine_score": round(psr_score, 1),
            "approach_settle_score": round(apr_score, 1),
            "hold_score": round(hold_score, 1),
            "press_score": round(press_score, 1),
            "followthrough_score": round(ft_score, 1),
            # Backward-compatible aliases for existing UI
            "preshot_score": round(psr_score, 1),
            "ft_score": round(ft_score, 1),
            "hold_stability": round(math.sqrt(hold_std_x ** 2 + hold_std_y ** 2), 5),
            "recoil_recovery_samples": recovery_samples,
            "recoil_recovery_ms": round(recovery_samples * DT * 1000, 0),

            # Shooting score (SCATT-style, 0–100)
            "shooting_score": round(shooting_score, 1),
            "shooting_grade": self._stability_letter_grade(shooting_score),
            "dist_from_group_rad": round(dist_from_group_rad, 5),

            # A2C / error data
            "a2c_angle": round(math.degrees(a2c_angle), 1),
            "a2c_mag": round(a2c_mag, 5),
            "error_type": error_type,
            "error_severity": error_severity,
            "coaching": coaching,

            # Bullet impact prediction (cm from center at target_distance)
            "impact_x_cm": round(impact_x_cm, 2),
            "impact_y_cm": round(impact_y_cm, 2),
            "impact_conf_radius_cm": round(impact_conf_radius, 2),
            "target_distance": round(target_d, 1),

            # 6-phase traces (normalized to hold centroid)
            "preshot_routine": (norm_psr_x, norm_psr_y),
            "approach_settle": (norm_apr_x, norm_apr_y),
            "hold": (norm_hol_x, norm_hol_y),
            "press": (norm_pre_x, norm_pre_y),
            "break": (norm_brk_x, norm_brk_y),
            "followthrough": (norm_ft_x, norm_ft_y),
            # Backward-compatible aliases
            "preshot": (norm_psr_x, norm_psr_y),
            "norm_hold": (norm_hol_x, norm_hol_y),
            "norm_press": (norm_pre_x, norm_pre_y),
            "hold_raw": (hol_x, hol_y),
            "press_raw": (pre_x, pre_y),
            "ft_raw": (ft_x, ft_y),
            "piezo": self.last_trigger_piezo,
        }


# ================= CANVAS-BASED AIM WIDGET =================

class AimCanvas(QWidget):
    """Smooth, canvas-based aim dot with phosphor trail effect."""

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
        """Update aim data and trigger repaint."""
        self.points_x = list(trace_x)
        self.points_y = list(trace_y)
        self.center_x = curr_x
        self.center_y = curr_y
        self.is_calibrated = calibrated
        # Smooth camera follow via lerp
        self.cam_x += (curr_x - self.cam_x) * self.smooth_factor
        self.cam_y += (curr_y - self.cam_y) * self.smooth_factor
        self.update()

    def set_range(self, r):
        self.plot_range = r
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        # Background
        painter.fillRect(self.rect(), QColor(COLORS['bg_secondary']))

        w, h = self.width(), self.height()
        canvas_cx, canvas_cy = w // 2, h // 2
        scale = min(w, h) / (2 * self.plot_range) * 0.9

        # World-to-screen: converts world coords to screen pixels relative to camera
        def world_to_screen(wx, wy):
            sx = canvas_cx + (wx - self.cam_x) * scale
            sy = canvas_cy - (wy - self.cam_y) * scale
            return sx, sy

        # Draw target rings centered on camera position
        for r in self.ring_radii:
            sx, sy = world_to_screen(self.cam_x, self.cam_y)
            ring_rect = QRectF(sx - r * scale, sy - r * scale, r * 2 * scale, r * 2 * scale)
            painter.setPen(QPen(QColor('#2A2A2A'), 1))
            painter.drawEllipse(ring_rect)

        # Draw crosshair at screen center
        painter.setPen(QPen(QColor('#333333'), 1))
        painter.drawLine(canvas_cx - 20, canvas_cy, canvas_cx + 20, canvas_cy)
        painter.drawLine(canvas_cx, canvas_cy - 20, canvas_cx, canvas_cy + 20)

        if not self.is_calibrated:
            return

        # Draw trail (phosphor display style) relative to camera
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
                    dx = pts[i] - pts[i-1]
                    dy = pts_y[i] - pts_y[i-1]
                    dist = math.sqrt(dx*dx + dy*dy)
                    sx, sy = world_to_screen(pts[i], pts_y[i])
                    if dist > TRAIL_MOVEMENT_THRESHOLD:
                        path.lineTo(sx, sy)
                    else:
                        path.moveTo(sx, sy)
                painter.setPen(trail_pen)
                painter.drawPath(path)

        # Draw current position dot
        dot_x, dot_y = world_to_screen(self.center_x, self.center_y)

        # Glow effect
        glow = QRadialGradient(dot_x, dot_y, 15)
        glow.setColorAt(0, QColor(COLORS['accent_good']))
        glow.setColorAt(1, QColor(0, 210, 106, 0))
        painter.fillRect(self.rect(), QBrush(glow))

        # Main dot
        painter.setBrush(QBrush(QColor(COLORS['accent_good'])))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(int(dot_x) - 6, int(dot_y) - 6, 12, 12)


class ShotTraceCanvas(QWidget):
    """Shot trace with 5 phases:
    1. Pre-Shot (blue, dashed)  — NPA setup / breathing rhythm
    2. Hold (green)             — stability window (respiratory pause)
    3. Press (yellow)           — trigger squeeze
    4. Lock Time (orange dot)    — sear break moment
    5. Recoil + Follow-through (red)"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(400, 400)
        self.preshot_x = []
        self.preshot_y = []
        self.hold_x = []
        self.hold_y = []
        self.press_x = []
        self.press_y = []
        self.recoil_x = []
        self.recoil_y = []
        self.ft_x = []
        self.ft_y = []
        self.break_x = 0.0  # world coords of trigger break
        self.break_y = 0.0
        self.playback_pos = 0
        self.scale = 1.0
        self.plot_range = PLOT_RANGE
        # Bullet impact data
        self.impact_x_cm = 0.0
        self.impact_y_cm = 0.0
        # Phase boundaries in sample indices (total trace length)
        # {'preshot_end': n_preshot, 'hold_end': n_preshot+n_hold, ...}
        self.phase_boundaries = {}
        self.current_shot_idx = 0    # 1-based shot number for overlay

    # 6-phase colours (trigger at T-0, T-20s to T+3s = 23s window)
    COL_PRESHOT_ROUTINE = '#1E88E5'  # Blue   — T-20s to T-12s, dashed
    COL_APPROACH_SETTLE = '#00BCD4'  # Cyan   — T-12s to T-4s, solid
    COL_HOLD            = '#00D26A'  # Green  — T-4s to T-1s, solid
    COL_PRESS           = '#FFEB3B'  # Yellow — T-1s to T-0, solid
    COL_BREAK           = '#FF9800'  # Orange — T-0 (instant dot)
    COL_FT              = '#FF5252'  # Red    — T-0 to T+3s, solid

    def set_trace(self, preshot_routine=None, approach_settle=None, hold=None,
                  press=None, break_pt=None, ft=None,
                  impact_x_cm=0.0, impact_y_cm=0.0,
                  # Backward-compatible 5-phase params (for loading DB traces)
                  preshot=None, recoil=None):
        """Load trace data for rendering.

        Accepts either:
          - 6-phase new format: preshot_routine, approach_settle, hold, press, break_pt, ft
          - 5-phase old format: preshot, hold, press, recoil, ft (DB backward compat)
        """
        # 6-phase new format: preshot_routine + approach_settle are the new keys
        if preshot_routine is not None or approach_settle is not None:
            self.psr_x, self.psr_y = (preshot_routine if preshot_routine else ([], []))
            self.apr_x, self.apr_y = (approach_settle if approach_settle else ([], []))
            self.hol_x, self.hol_y = (hold if hold else ([], []))
            self.pre_x, self.pre_y = (press if press else ([], []))
            self.brk_x, self.brk_y = (break_pt if break_pt else (0.0, 0.0))
            self.ft_x,  self.ft_y  = (ft if ft else ([], []))
        # 5-phase old format: preshot, hold, press, recoil, ft (DB compat)
        elif preshot is not None or hold is not None or recoil is not None:
            self.psr_x, self.psr_y = (preshot if preshot else ([], []))
            self.apr_x, self.apr_y = ([], [])  # no approach phase in old format
            self.hol_x, self.hol_y = (hold if hold else ([], []))
            self.pre_x, self.pre_y = (press if press else ([], []))
            # Break is the last point of press
            self.brk_x = self.pre_x[-1] if self.pre_x else 0.0
            self.brk_y = self.pre_y[-1] if self.pre_y else 0.0
            # old "recoil" maps to nothing; FT is follow-through
            self.ft_x, self.ft_y = (ft if ft else ([], []))
        else:
            # No data provided — clear
            self.psr_x = self.psr_y = []
            self.apr_x = self.apr_y = []
            self.hol_x = self.hol_y = []
            self.pre_x = self.pre_y = []
            self.brk_x = self.brk_y = 0.0
            self.ft_x  = self.ft_y  = []

        self.impact_x_cm = impact_x_cm
        self.impact_y_cm = impact_y_cm
        self.playback_pos = 0

        # Build phase_boundaries for timeline scrubber (backward compat)
        n_psr = len(self.psr_x)
        n_apr = len(self.apr_x)
        n_hol = len(self.hol_x)
        n_pre = len(self.pre_x)
        n_ft  = len(self.ft_x)
        self.phase_boundaries = {
            'preshot_end':  n_psr,
            'hold_end':     n_psr + n_apr + n_hol,
            'press_end':    n_psr + n_apr + n_hol + n_pre,
            'recoil_end':   n_psr + n_apr + n_hol + n_pre,  # no recoil phase
            'ft_end':       n_psr + n_apr + n_hol + n_pre + n_ft,
        }

        self.update()

    def clear_trace(self):
        self.psr_x = self.psr_y = []
        self.apr_x = self.apr_y = []
        self.hol_x = self.hol_y = []
        self.pre_x = self.pre_y = []
        self.brk_x = self.brk_y = 0.0
        self.ft_x  = self.ft_y  = []
        self.impact_x_cm = 0.0
        self.impact_y_cm = 0.0
        self.playback_pos = 0
        self.current_shot_idx = 0
        self.update()

    def set_scale(self, s):
        self.scale = max(0.5, min(5.0, s))

    def wheelEvent(self, event):
        """Scroll to zoom, centered on cursor."""
        delta = event.angleDelta().y()
        factor = 1.15 if delta > 0 else 1.0 / 1.15
        self.scale = max(0.5, min(5.0, self.scale * factor))
        self.update()

    def _draw_path(self, painter, xs, ys, cx, cy, scale, pen):
        """Draw a smooth path from coordinate lists."""
        if len(xs) < 2:
            return
        path = QPainterPath()
        path.moveTo(cx + xs[0] * scale, cy - ys[0] * scale)
        for i in range(1, len(xs)):
            path.lineTo(cx + xs[i] * scale, cy - ys[i] * scale)
        painter.setPen(pen)
        painter.drawPath(path)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor(COLORS['bg_secondary']))

        w, h = self.width(), self.height()
        cx, cy = w // 2, h // 2
        base_scale = min(w, h) / (2 * self.plot_range) * 0.9 * self.scale

        # Phase sample counts for boundary calculations
        n_psr = len(self.psr_x)
        n_apr = len(self.apr_x)
        n_hol = len(self.hol_x)
        n_pre = len(self.pre_x)
        n_ft  = len(self.ft_x)

        # Playback position relative to post-trigger portion
        # playback_pos counts samples from trigger (T-0) forward
        # vis_pos >= 0 means post-trigger phases are visible
        vis_pos = max(0, self.playback_pos)

        # ── Phase 1: Pre-Shot Routine (blue dashed) — always fully visible ──────
        psr_pen = QPen(QColor(self.COL_PRESHOT_ROUTINE), 1.5)
        psr_pen.setStyle(Qt.DashLine)
        self._draw_path(painter, self.psr_x, self.psr_y,
                        cx, cy, base_scale, psr_pen)

        # ── Phase 2: Approach & Settle (cyan solid) — always fully visible ───────
        self._draw_path(painter, self.apr_x, self.apr_y,
                        cx, cy, base_scale,
                        QPen(QColor(self.COL_APPROACH_SETTLE), 2))

        # ── Phase 3: Hold (green solid) — always fully visible ──────────────────
        self._draw_path(painter, self.hol_x, self.hol_y,
                        cx, cy, base_scale,
                        QPen(QColor(self.COL_HOLD), 2))

        # ── Phase 4: Trigger Press (yellow solid) — stepped by playback ──────────
        if self.pre_x:
            press_draw = min(vis_pos, n_pre)
            if press_draw > 0:
                self._draw_path(painter,
                                self.pre_x[:press_draw], self.pre_y[:press_draw],
                                cx, cy, base_scale,
                                QPen(QColor(self.COL_PRESS), 3))

        # ── Phase 5: Break (orange dot at T-0) — always fully visible ───────────
        if self.brk_x != 0.0 or self.brk_y != 0.0:
            bx = cx + self.brk_x * base_scale
            by = cy - self.brk_y * base_scale
            painter.setBrush(QBrush(QColor(self.COL_BREAK)))
            painter.setPen(Qt.NoPen)
            painter.drawEllipse(int(bx) - 6, int(by) - 6, 12, 12)
            painter.setBrush(QBrush(QColor('#FFFFFF')))
            painter.drawEllipse(int(bx) - 3, int(by) - 3, 6, 6)

        # ── Phase 6: Follow-Through (red solid) — stepped by playback ────────────
        if self.ft_x:
            # vis_pos counts from T-0 forward; subtract n_pre to get FT position
            ft_start = n_pre  # follow-through starts after press phase
            ft_draw = min(max(0, vis_pos - ft_start), n_ft)
            if ft_draw > 0:
                self._draw_path(painter,
                                self.ft_x[:ft_draw], self.ft_y[:ft_draw],
                                cx, cy, base_scale,
                                QPen(QColor(self.COL_FT), 2))

        # ── Bullet impact dot (cyan) ────────────────────────────────────────────
        if abs(self.impact_x_cm) > 0.01 or abs(self.impact_y_cm) > 0.01:
            impact_scale = base_scale / self.plot_range
            imp_pix_x = cx + self.impact_x_cm * 0.01 * impact_scale
            imp_pix_y = cy - self.impact_y_cm * 0.01 * impact_scale
            painter.setBrush(QBrush(QColor('#00E5FF')))
            painter.setPen(Qt.NoPen)
            painter.drawEllipse(int(imp_pix_x) - 5, int(imp_pix_y) - 5, 10, 10)

        # ── Shot number overlay (top-left) ──────────────────────────────────────
        if self.current_shot_idx > 0:
            painter.setPen(QPen(QColor(COLORS['text_secondary'])))
            painter.setFont(QFont("Segoe UI", 14, QFont.Bold))
            painter.drawText(20, 30, f"Shot #{self.current_shot_idx}")


# ================ NEW SHOT ANALYSIS WIDGETS ================

class PlaybackControlsWidget(QWidget):
    """Playback controls strip: skip-back, step-back, play/pause, step-fwd, skip-fwd + speed selector."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._speed = 1.0
        self._is_playing = False
        self._setup_ui()

    def _setup_ui(self):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 8, 0, 0)
        layout.setSpacing(8)

        # Navigation buttons
        self.btn_skip_start = QPushButton("◀◀")
        self.btn_skip_start.setFixedWidth(40)
        self.btn_skip_start.setCursor(Qt.PointingHandCursor)
        self.btn_skip_start.setToolTip("Skip to start")

        self.btn_step_back = QPushButton("◀")
        self.btn_step_back.setFixedWidth(36)
        self.btn_step_back.setCursor(Qt.PointingHandCursor)
        self.btn_step_back.setToolTip("Step back 50ms")

        self.btn_play = QPushButton("▶")
        self.btn_play.setFixedWidth(44)
        self.btn_play.setCursor(Qt.PointingHandCursor)
        self.btn_play.setToolTip("Play / Pause")

        self.btn_step_fwd = QPushButton("▶")
        self.btn_step_fwd.setFixedWidth(36)
        self.btn_step_fwd.setCursor(Qt.PointingHandCursor)
        self.btn_step_fwd.setToolTip("Step forward 50ms")

        self.btn_skip_end = QPushButton("▶▶")
        self.btn_skip_end.setFixedWidth(40)
        self.btn_skip_end.setCursor(Qt.PointingHandCursor)
        self.btn_skip_end.setToolTip("Skip to end")

        nav_layout = QHBoxLayout()
        nav_layout.setSpacing(6)
        for btn in [self.btn_skip_start, self.btn_step_back,
                    self.btn_play, self.btn_step_fwd, self.btn_skip_end]:
            btn.setStyleSheet(self._btn_style())
            nav_layout.addWidget(btn)

        layout.addLayout(nav_layout)
        layout.addStretch()

        # Speed selector
        speed_label = QLabel("Speed:")
        speed_label.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px;")
        layout.addWidget(speed_label)

        self._speed_btns = {}
        for speed, label in [(0.5, "0.5×"), (1.0, "1×"), (2.0, "2×")]:
            btn = QPushButton(label)
            btn.setFixedWidth(44)
            btn.setCursor(Qt.PointingHandCursor)
            is_default = (speed == 1.0)
            btn.setStyleSheet(self._speed_btn_style(active=is_default))
            self._speed_btns[speed] = btn
            layout.addWidget(btn)

        layout.addSpacing(4)

    def _btn_style(self, bg=None):
        bg = bg or COLORS['bg_tertiary']
        return f"""
            QPushButton {{
                background: {bg};
                color: {COLORS['text_primary']};
                border: 1px solid {COLORS['border']};
                border-radius: 6px;
                padding: 8px 4px;
                font-size: 14px;
                font-weight: 700;
            }}
            QPushButton:hover {{ background: {COLORS['bg_elevated']}; }}
            QPushButton:pressed {{ background: {COLORS['accent_blue']}; }}
        """

    def _speed_btn_style(self, active=False):
        bg = COLORS['accent_blue'] if active else COLORS['bg_tertiary']
        fg = "#FFF" if active else COLORS['text_primary']
        return f"""
            QPushButton {{
                background: {bg};
                color: {fg};
                border: 1px solid {COLORS['border']};
                border-radius: 6px;
                padding: 6px 4px;
                font-size: 12px;
                font-weight: 600;
            }}
            QPushButton:hover {{ background: {COLORS['bg_elevated']}; }}
        """

    def set_playing(self, is_playing):
        self._is_playing = is_playing
        icon = "⏸" if is_playing else "▶"
        self.btn_play.setText(icon)
        self.btn_play.setStyleSheet(
            self._btn_style(bg=COLORS['accent_good'] if is_playing else COLORS['bg_tertiary']))

    def set_speed(self, speed):
        self._speed = speed
        for s, btn in self._speed_btns.items():
            btn.setStyleSheet(self._speed_btn_style(active=(s == speed)))


class TimelineSlider(QSlider):
    """QSlider with painted phase bands (green/yellow/red) and time labels."""

    def __init__(self, parent=None):
        super().__init__(Qt.Horizontal, parent)
        self.phase_boundaries = {}   # {'hold_end': n, 'press_end': n, ...}
        self.total_samples = 0
        self.setMinimum(0)
        self.setMaximum(1000)
        self._dragging = False
        self.sliderPressed.connect(lambda: setattr(self, '_dragging', True))
        self.sliderReleased.connect(lambda: setattr(self, '_dragging', False))

    def set_trace_info(self, phase_boundaries, total_samples):
        self.phase_boundaries = phase_boundaries
        self.total_samples = max(total_samples, 1)
        self.setMaximum(self.total_samples)
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        # Draw track background
        track_h = self.height()
        groove_h = max(track_h - 16, 8)
        groove_y = (track_h - groove_h) // 2
        groove_rect = self.rect().adjusted(8, groove_y, -8, -(track_h - groove_y - groove_h))

        # Phase colours matching ShotTraceCanvas
        COL_PRESHOT  = '#2196F3'
        COL_HOLD     = '#00D26A'
        COL_PRESS    = '#FFEB3B'
        COL_RECOIL   = '#FF5252'
        COL_FT       = '#FF5252'

        if self.total_samples > 0:
            # 5 phase bands: pre-shot, hold, press, recoil, follow-through
            preshot_end = self.phase_boundaries.get('preshot_end', 0)
            hold_end    = self.phase_boundaries.get('hold_end', 0)
            press_end   = self.phase_boundaries.get('press_end', 0)
            recoil_end  = self.phase_boundaries.get('recoil_end', 0)
            ft_end      = self.phase_boundaries.get('ft_end', self.total_samples)

            band_colors = [
                (0,              preshot_end, COL_PRESHOT),
                (preshot_end,    hold_end,    COL_HOLD),
                (hold_end,       press_end,   COL_PRESS),
                (press_end,      recoil_end,  COL_RECOIL),
                (recoil_end,     ft_end,      COL_FT),
            ]

            for start, end, color in band_colors:
                x1 = int(groove_rect.left() + start / self.total_samples * groove_rect.width())
                x2 = int(groove_rect.left() + end / self.total_samples * groove_rect.width())
                if x2 > x1:
                    band_rect = QRectF(x1, groove_rect.top(), x2 - x1, groove_rect.height())
                    painter.fillRect(band_rect, QColor(color + "33"))  # 20% opacity

        # Draw groove line
        painter.setPen(QPen(QColor(COLORS['border']), 2))
        painter.drawLine(int(groove_rect.left()), track_h // 2,
                         int(groove_rect.right()), track_h // 2)

        # Playhead
        pos_ratio = self.value() / max(self.maximum(), 1)
        thumb_x = groove_rect.left() + pos_ratio * groove_rect.width()
        thumb_y = track_h // 2
        r = 8
        painter.setBrush(QBrush(QColor(COLORS['accent_blue'])))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(int(thumb_x) - r, thumb_y - r, r * 2, r * 2)

        # Time labels
        painter.setFont(QFont("Segoe UI", 9))
        painter.setPen(QPen(QColor(COLORS['text_muted'])))
        total_ms = self.total_samples * 10  # 100Hz = 10ms/sample
        # Pick nice label interval
        if total_ms <= 2000:
            step_ms = 500
        elif total_ms <= 5000:
            step_ms = 1000
        else:
            step_ms = 2000
        for t in range(0, int(total_ms) + 1, step_ms):
            ratio = t / total_ms
            x = int(groove_rect.left() + ratio * groove_rect.width())
            painter.drawText(x - 10, track_h - 2, f"{t}ms")


class SparklineWidget(QWidget):
    """Minimal line-chart sparkline showing last N score values."""

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

        # Draw fill
        fill_path = QPainterPath()
        fill_path.moveTo(points[0][0], h - pad)
        for x, y in points:
            fill_path.lineTo(x, y)
        fill_path.lineTo(points[-1][0], h - pad)
        fill_path.closeSubpath()
        painter.fillPath(fill_path, QColor(COLORS['accent_blue'] + "22"))

        # Draw line
        line_path = QPainterPath()
        line_path.moveTo(*points[0])
        for x, y in points[1:]:
            line_path.lineTo(x, y)
        painter.setPen(QPen(QColor(COLORS['accent_blue']), 2))
        painter.drawPath(line_path)

        # Draw dots at each point
        painter.setBrush(QBrush(QColor(COLORS['accent_blue'])))
        painter.setPen(Qt.NoPen)
        for x, y in points:
            painter.drawEllipse(int(x) - 3, int(y) - 3, 6, 6)


class PerShotStatsWidget(QWidget):
    """Per-shot stats panel: phase bars, A2C, scores, grade, error, impact."""

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

        # Phase score bars
        self._phase_bars = {}
        for phase, color in [('Pre-Shot', '#2196F3'),
                              ('Hold', '#00D26A'),
                              ('Press', '#FFEB3B'),
                              ('Recoil', '#FF5252'),
                              ('FT', '#FF5252')]:
            row = QHBoxLayout()
            row.setSpacing(8)
            lbl = QLabel(phase)
            lbl.setFixedWidth(52)
            lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 11px; font-weight: 600;")
            row.addWidget(lbl)

            bar = QProgressBar()
            bar.setFixedHeight(8)
            bar.setTextVisible(False)
            bar.setStyleSheet(self._bar_style(color))
            self._phase_bars[phase] = bar
            row.addWidget(bar, 1)

            self._phase_bars[f'{phase}_lbl'] = QLabel("--")
            self._phase_bars[f'{phase}_lbl'].setFixedWidth(28)
            self._phase_bars[f'{phase}_lbl'].setStyleSheet(
                f"color: {color}; font-size: 11px; font-weight: 700;")
            row.addWidget(self._phase_bars[f'{phase}_lbl'])

            layout.addLayout(row)

        layout.addSpacing(4)

        # A2C row
        self._a2c_lbl = QLabel("A2C: --")
        self._a2c_lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px;")
        layout.addWidget(self._a2c_lbl)

        # Scores row
        self._stab_lbl = QLabel("Stability: --")
        self._stab_lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px;")
        self._shoot_lbl = QLabel("Shooting: --")
        self._shoot_lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px;")
        score_row = QHBoxLayout()
        score_row.addWidget(self._stab_lbl)
        score_row.addWidget(self._shoot_lbl)
        layout.addLayout(score_row)

        # Grade badge
        self._grade_lbl = QLabel("Grade: --")
        self._grade_lbl.setStyleSheet(
            f"background: {COLORS['bg_tertiary']}; border: 1px solid {COLORS['border']}; "
            f"border-radius: 8px; padding: 6px 14px; "
            f"font-size: 12px; font-weight: 700; color: {COLORS['text_secondary']};")
        layout.addWidget(self._grade_lbl)

        # Error type
        self._err_lbl = QLabel("Error: --")
        self._err_lbl.setStyleSheet(
            f"background: {COLORS['accent_ok']}22; border: 1px solid {COLORS['accent_ok']}66; "
            f"border-radius: 6px; padding: 4px 10px; "
            f"font-size: 11px; color: {COLORS['accent_ok']};")
        layout.addWidget(self._err_lbl)

        # Impact coords
        self._imp_lbl = QLabel("Impact: (--, --)")
        self._imp_lbl.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 11px;")
        layout.addWidget(self._imp_lbl)

        layout.addStretch()

    def _bar_style(self, color):
        return f"""
            QProgressBar {{
                background: {COLORS['bg_tertiary']};
                border: none;
                border-radius: 4px;
            }}
            QProgressBar::chunk {{
                background: {color};
                border-radius: 4px;
            }}
        """

    def populate(self, shot):
        """Fill stats from a shot dict."""
        # Phase scores — 5 phases: Pre-Shot, Hold, Press, Recoil, FT
        for phase, key in [('Pre-Shot', 'preshot_score'),
                            ('Hold', 'hold_score'),
                            ('Press', 'press_score'),
                            ('Recoil', 'recoil_score'),
                            ('FT', 'ft_score')]:
            score = shot.get(key, 0) or 0
            self._phase_bars[phase].setValue(int(score))
            self._phase_bars[f'{phase}_lbl'].setText(f"{int(score)}")

        # A2C
        a2c_angle = shot.get('a2c_angle_deg', 0) or 0
        a2c_mag = shot.get('a2c_mag_mrad', 0) or 0
        self._a2c_lbl.setText(f"A2C: {a2c_angle:+.1f}° / {a2c_mag:.1f}mrad")

        # Scores
        stab = shot.get('stability_score', 0) or 0
        shoot = shot.get('shooting_score', 0) or 0
        self._stab_lbl.setText(f"Stability: {int(stab)}")
        self._shoot_lbl.setText(f"Shooting: {int(shoot)}")

        # Grade
        grade = shot.get('stability_grade', '') or ''
        score_val = shot.get('score', 0) or 0
        grade_color = self._score_color(score_val)
        self._grade_lbl.setText(f"Grade: {grade or '--'}")
        self._grade_lbl.setStyleSheet(
            f"background: {grade_color}33; border: 1px solid {grade_color}88; "
            f"border-radius: 8px; padding: 6px 14px; "
            f"font-size: 12px; font-weight: 700; color: {grade_color};")

        # Error type
        err = shot.get('error_type', '') or ''
        if err and err not in ('NONE', 'none', ''):
            self._err_lbl.setText(f"Error: {err}")
            self._err_lbl.setVisible(True)
        else:
            self._err_lbl.setVisible(False)

        # Impact
        ix = shot.get('impact_x_cm', 0) or 0
        iy = shot.get('impact_y_cm', 0) or 0
        self._imp_lbl.setText(f"Impact: ({ix:+.1f}, {iy:+.1f}) cm")

    def _score_color(self, score):
        if score >= 95: return COLORS.get('score_elite', COLORS['accent_good'])
        if score >= 85: return COLORS.get('score_expert', COLORS['accent_good'])
        if score >= 70: return COLORS.get('score_advanced', COLORS['accent_ok'])
        if score >= 50: return COLORS.get('score_intermediate', COLORS['accent_ok'])
        return COLORS.get('score_beginner', COLORS['accent_bad'])

    def clear(self):
        for phase in ['Pre-Shot', 'Hold', 'Press', 'Recoil', 'FT']:
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


class SessionStatsWidget(QWidget):
    """Session-level statistics: avg/best/count, spread/MOA, sparkline."""

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

        # Summary row: Avg / Best / Count
        summary_layout = QHBoxLayout()
        summary_layout.setSpacing(8)
        self._avg_card = self._make_stat_card("Avg Score", "--")
        self._best_card = self._make_stat_card("Best", "--")
        self._count_card = self._make_stat_card("Shots", "0")
        for card in [self._avg_card, self._best_card, self._count_card]:
            summary_layout.addWidget(card)
        layout.addLayout(summary_layout)

        # Group analysis
        group_layout = QHBoxLayout()
        group_layout.setSpacing(8)
        self._spread_card = self._make_stat_card("Spread", "--")
        self._moa_card = self._make_stat_card("MOA", "--")
        self._group_card = self._make_stat_card("Group", "--")
        for card in [self._spread_card, self._moa_card, self._group_card]:
            group_layout.addWidget(card)
        layout.addLayout(group_layout)

        # Sparkline
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
        layout = QVBoxLayout(card)
        layout.setContentsMargins(6, 6, 6, 6)
        layout.setSpacing(2)

        lbl_title = QLabel(title.upper())
        lbl_title.setStyleSheet(
            f"color: {COLORS['text_muted']}; font-size: 9px; font-weight: 700; letter-spacing: 0.5px;")
        lbl_title.setFont(QFont("Segoe UI", 9, QFont.Bold))
        layout.addWidget(lbl_title)

        lbl_value = QLabel(value)
        lbl_value.setStyleSheet(
            f"color: {COLORS['text_primary']}; font-size: 16px; font-weight: 700;")
        lbl_value.setFont(QFont("Segoe UI", 16, QFont.Bold))
        layout.addWidget(lbl_value)
        return card

    def populate(self, shots):
        """Recalculate session stats from a list of shot dicts."""
        if not shots:
            self._avg_card.findChild(QLabel, "", Qt.FindDirectChildOnly).setText("--")
            self._best_card.findChild(QLabel, "", Qt.FindDirectChildOnly).setText("--")
            self._count_card.findChild(QLabel, "", Qt.FindDirectChildOnly).setText("0")
            self._spread_card.findChild(QLabel, "", Qt.FindDirectChildOnly).setText("--")
            self._moa_card.findChild(QLabel, "", Qt.FindDirectChildOnly).setText("--")
            self._group_card.findChild(QLabel, "", Qt.FindDirectChildOnly).setText("--")
            self._sparkline.set_values([])
            return

        scores = [s.get('score', 0) or 0 for s in shots]
        avg = sum(scores) / len(scores) if scores else 0
        best = max(scores) if scores else 0

        self._set_card_value(self._avg_card, f"{avg:.1f}")
        self._set_card_value(self._best_card, f"{int(best)}")
        self._set_card_value(self._count_card, str(len(shots)))

        # Spread / MOA from ShotGroupAnalyzer
        try:
            coords = [(s.get('impact_x_cm', 0) or 0,
                       s.get('impact_y_cm', 0) or 0) for s in shots]
            coords = [(x, y) for x, y in coords if abs(x) > 0.01 or abs(y) > 0.01]
            if len(coords) >= 2:
                result = ShotGroupAnalyzer.analyze(coords)
                spread = result.get('spread_cm', 0)
                moa = result.get('moa', 0)
                self._set_card_value(self._spread_card, f"{spread:.1f}cm")
                self._set_card_value(self._moa_card, f"{moa:.1f}")
                self._set_card_value(self._group_card, f"{len(coords)} shots")
            else:
                self._set_card_value(self._spread_card, "N/A")
                self._set_card_value(self._moa_card, "N/A")
                self._set_card_value(self._group_card, f"{len(coords)} shot")
        except Exception:
            self._set_card_value(self._spread_card, "--")
            self._set_card_value(self._moa_card, "--")
            self._set_card_value(self._group_card, "--")

        # Sparkline — last 10 scores
        self._sparkline.set_values(scores[-10:])

    def _set_card_value(self, card, value):
        # Find the value label (second child after title)
        lbls = card.findChildren(QLabel)
        if len(lbls) >= 2:
            lbls[1].setText(value)

    def clear(self):
        self._set_card_value(self._avg_card, "--")
        self._set_card_value(self._best_card, "--")
        self._set_card_value(self._count_card, "0")
        self._set_card_value(self._spread_card, "--")
        self._set_card_value(self._moa_card, "--")
        self._set_card_value(self._group_card, "--")
        self._sparkline.set_values([])


# ================= MANTISX-STYLE UI =================

class MainWindow(QMainWindow):
    def __init__(self, serial_port, device_key="SIM"):
        super().__init__()
        self.ser = serial_port
        self.detector = ShotDetector()
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.session_mode = "Dry Fire"
        self.shot_count = 0
        self.shot_history = []
        self._shot_impacts = []
        self._recording       = False
        self._countdown_value = 0
        self._session_saved  = False   # True only after START RECORD pressed — session will be saved to DB
        self._load_settings()
        self.init_ui()
        # Apply loaded firearm/mode/mount_direction to chip buttons and detector
        self._select_firearm(self.current_firearm)
        self._select_training_mode(self.current_training_mode)
        self._set_mount_direction(self.current_mount_direction)
        # Sync threshold spinboxes to loaded values
        if hasattr(self, 'spin_piezo'):
            self.spin_piezo.setValue(self._settings.get('piezo_min', DEFAULT_PIEZO_MIN))
        if hasattr(self, 'spin_jerk'):
            self.spin_jerk.setValue(self._settings.get('jerk_thresh', DEFAULT_ACCEL_THRESH))
        if hasattr(self, 'cmb_com_port'):
            port = self._settings.get('com_port', BLUETOOTH_COM_PORT)
            idx = self.cmb_com_port.findText(port)
            if idx >= 0:
                self.cmb_com_port.setCurrentIndex(idx)
        self.calib_buffer = []
        self.calibrating = False
        self._auto_calibrating = False
        self._device_key = device_key
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_loop)
        self.timer.start(10)
        self._load_or_auto_calibrate()

    def _stylized_button(self, btn, bg, fg='#FFF', border=None):
        """Apply MantisX-style button styling."""
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
        """Wrap widget in a MantisX-style card."""
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
        self.showFullScreen()

        # Set modern dark palette
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

        # ========== HEADER ==========
        header = QFrame()
        header.setStyleSheet(f"background: {COLORS['bg_secondary']}; border-bottom: 1px solid {COLORS['border']};")
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(24, 16, 24, 16)

        # Logo / Title
        title = QLabel("STASYS")
        title_font = QFont("Segoe UI", 24, QFont.Bold)
        title.setFont(title_font)
        title.setStyleSheet(f"color: {COLORS['accent_good']};")
        header_layout.addWidget(title)

        # Session info
        self.lbl_session_info = QLabel("Session: -- | Mode: Dry Fire")
        self.lbl_session_info.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 13px;")
        header_layout.addWidget(self.lbl_session_info)

        header_layout.addStretch()

        # Sim mode indicator
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

        # ========== TABS ==========
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
        self.tabs.tabBar().setMinimumWidth(130)
        main_layout.addWidget(self.tabs, 1)

        # Tab 1: Live Monitor
        self._build_live_monitor_tab()

        # Tab 2: Shot Analysis
        self._build_shot_analysis_tab()

        # Tab 3: Session History
        self._build_history_tab()

        # Tab 4: Settings
        self._build_settings_tab()

    def _build_live_monitor_tab(self):
        """Build the main live monitoring tab with canvas-based aim display."""
        tab1 = QWidget()
        tab1.setStyleSheet(f"background: {COLORS['bg_primary']};")
        tab1_layout = QHBoxLayout(tab1)
        tab1_layout.setContentsMargins(20, 20, 20, 20)
        tab1_layout.setSpacing(20)

        # ===== LEFT CONTROL PANEL =====
        left_panel = QFrame()
        left_panel.setMinimumWidth(260)   # FIX BUG 1: panel kiri tidak terpotong
        left_panel.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_secondary']};
                border-radius: 16px;
            }}
        """)
        left_layout = QVBoxLayout(left_panel)
        left_layout.setContentsMargins(16, 16, 16, 16)  # FIX BUG 1: kurangi margin agar konten muat
        left_layout.setSpacing(12)

        # Mode selector
        mode_label = QLabel("Detection Mode")
        mode_label.setFont(QFont("Segoe UI", 12, QFont.Bold))
        mode_label.setStyleSheet(f"color: #FFFFFF; font-size: 12px; font-weight: 700; letter-spacing: 1px;")
        left_layout.addWidget(mode_label)

        self.cmb_mode = QComboBox()
        self.cmb_mode.addItems(["Dry Fire (Piezo)", "Live Fire (Jerk)"])
        self.cmb_mode.setFont(QFont("Segoe UI", 13, QFont.Normal))
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

        # Thresholds
        thresh_label = QLabel("Thresholds")
        thresh_label.setFont(QFont("Segoe UI", 12, QFont.Bold))
        thresh_label.setStyleSheet(f"color: #00D26A; font-size: 12px; font-weight: 700; letter-spacing: 1px; margin-top: 8px; margin-bottom: 4px;")
        left_layout.addWidget(thresh_label)

        thresh_grid = QGridLayout()
        thresh_grid.setSpacing(12)
        thresh_grid.setVerticalSpacing(8)

        piezo_lbl = QLabel("Piezo Min")
        piezo_lbl.setFont(QFont("Segoe UI", 13, QFont.Medium))
        piezo_lbl.setStyleSheet(f"color: #FFFFFF; font-size: 13px; font-weight: 500;")
        thresh_grid.addWidget(piezo_lbl, 0, 0)
        self.spin_piezo = QDoubleSpinBox()
        self.spin_piezo.setRange(0, 4095)
        self.spin_piezo.setValue(DEFAULT_PIEZO_MIN)
        self.spin_piezo.setFont(QFont("Segoe UI", 14, QFont.Bold))
        self.spin_piezo.valueChanged.connect(self.update_thresholds)
        thresh_grid.addWidget(self.spin_piezo, 0, 1)

        jerk_lbl = QLabel("Jerk (G)")
        jerk_lbl.setFont(QFont("Segoe UI", 13, QFont.Medium))
        jerk_lbl.setStyleSheet(f"color: #FFFFFF; font-size: 13px; font-weight: 500;")
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
                    padding: 8px 10px;    /* FIX BUG 1: kurangi padding agar muat */
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

        # Status indicator
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
                padding: 10px;   /* FIX BUG 1: kurangi dari 16px */
            }}
        """)
        left_layout.addWidget(self.lbl_status)

        # Calibration button
        self.btn_calib = QPushButton("CALIBRATE")
        self.btn_calib.setCursor(Qt.PointingHandCursor)
        self.btn_calib.clicked.connect(self.start_calibration)
        left_layout.addWidget(self.btn_calib)
        self._stylized_button(self.btn_calib, COLORS['accent_blue'], '#FFF')

        # Tare button
        self.btn_tare = QPushButton("TARE — Re-Zero Aim")
        self.btn_tare.setCursor(Qt.PointingHandCursor)
        self.btn_tare.setToolTip("Stores current orientation as screen center. Use after repositioning.")
        self.btn_tare.clicked.connect(self.do_tare)
        left_layout.addWidget(self.btn_tare)
        self._stylized_button(self.btn_tare, '#1B5E20', COLORS['accent_good'], COLORS['accent_good'])

        # Record button
        self.btn_record = QPushButton("▶ START RECORD")
        self.btn_record.setCursor(Qt.PointingHandCursor)
        self.btn_record.clicked.connect(self.toggle_recording)
        self._stylized_button(self.btn_record, COLORS['accent_good'], '#000', COLORS['accent_good'])
        left_layout.addWidget(self.btn_record)

        self.lbl_record_state = QLabel("● IDLE")
        self.lbl_record_state.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 12px;")
        self.lbl_record_state.setAlignment(Qt.AlignCenter)
        left_layout.addWidget(self.lbl_record_state)

        # Multiplier display
        mult_label = QLabel("Multiplier")
        mult_label.setFont(QFont("Segoe UI", 12, QFont.Bold))
        mult_label.setStyleSheet(f"color: #00D26A; font-size: 12px; font-weight: 700; letter-spacing: 1px; margin-top: 8px; margin-bottom: 4px;")
        left_layout.addWidget(mult_label)

        self.lbl_firearm_mult = QLabel(f"{self.current_firearm} x{FIREARM_MULTIPLIERS.get(self.current_firearm, 1.0):.1f}")
        self.lbl_firearm_mult.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 12px;")
        left_layout.addWidget(self.lbl_firearm_mult)

        self.lbl_mode_mult = QLabel(f"{self.current_training_mode} x{TRAINING_MODE_MULTIPLIERS.get(self.current_training_mode, 1.0):.1f}")
        self.lbl_mode_mult.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 12px;")
        left_layout.addWidget(self.lbl_mode_mult)

        # Telemetry
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
        self.lbl_telem_a2c = QLabel("A2C: --\nHold: --\nError: --")
        self.lbl_telem_a2c.setStyleSheet(f"""
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
        left_layout.addWidget(self.lbl_telem_a2c)

        tab1_layout.addWidget(left_panel, 1)

        # ===== CENTER: LIVE AIM MONITOR =====
        center_layout = QVBoxLayout()

        # Canvas-based aim display
        self.aim_canvas = AimCanvas()
        self.aim_canvas.setStyleSheet(f"""
            QWidget {{
                background: {COLORS['bg_secondary']};
                border: 2px solid {COLORS['accent_good']};
                border-radius: 16px;
            }}
        """)
        center_layout.addWidget(self.aim_canvas, 5)

        # Compact bottom strip: Stability Score + Shooting Score + Piezo + Phase scores
        strip = QHBoxLayout()
        strip.setSpacing(16)

        # ── Stability Score block (MantisX-style) ──
        stability_block = QVBoxLayout()
        stability_block.setSpacing(2)

        stab_title = QLabel("STABILITY")
        stab_title.setAlignment(Qt.AlignCenter)
        stab_title.setStyleSheet(f"""
            color: {COLORS['text_muted']};
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 1.5px;
        """)
        stability_block.addWidget(stab_title)

        stab_score_row = QHBoxLayout()
        stab_score_row.setSpacing(8)
        self.lbl_stability_score = QLabel("--")
        self.lbl_stability_score.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.lbl_stability_score.setStyleSheet(f"""
            QLabel {{
                font-size: 42px;
                font-weight: 200;
                color: {COLORS['text_muted']};
            }}
        """)
        stab_score_row.addWidget(self.lbl_stability_score)

        self.lbl_stability_grade = QLabel("")
        self.lbl_stability_grade.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        self.lbl_stability_grade.setStyleSheet(f"""
            QLabel {{
                font-size: 22px;
                font-weight: 600;
                color: {COLORS['text_muted']};
            }}
        """)
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

        # ── Shooting Score block (SCATT-style) ──
        shooting_block = QVBoxLayout()
        shooting_block.setSpacing(2)

        shoot_title = QLabel("SHOOTING")
        shoot_title.setAlignment(Qt.AlignCenter)
        shoot_title.setStyleSheet(f"""
            color: {COLORS['text_muted']};
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 1.5px;
        """)
        shooting_block.addWidget(shoot_title)

        shoot_score_row = QHBoxLayout()
        shoot_score_row.setSpacing(8)
        self.lbl_shooting_score = QLabel("--")
        self.lbl_shooting_score.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.lbl_shooting_score.setStyleSheet(f"""
            QLabel {{
                font-size: 42px;
                font-weight: 200;
                color: {COLORS['text_muted']};
            }}
        """)
        shoot_score_row.addWidget(self.lbl_shooting_score)

        self.lbl_shooting_grade = QLabel("")
        self.lbl_shooting_grade.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        self.lbl_shooting_grade.setStyleSheet(f"""
            QLabel {{
                font-size: 22px;
                font-weight: 600;
                color: {COLORS['text_muted']};
            }}
        """)
        shoot_score_row.addWidget(self.lbl_shooting_grade)
        shooting_block.addLayout(shoot_score_row)

        # Group center hint
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
        piezo_title.setStyleSheet(f"""
            color: {COLORS['text_muted']};
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 1.5px;
        """)
        piezo_block.addWidget(piezo_title)

        self.lbl_big_piezo = QLabel("--")
        self.lbl_big_piezo.setAlignment(Qt.AlignCenter)
        self.lbl_big_piezo.setStyleSheet(f"""
            QLabel {{
                font-size: 36px;
                font-weight: 200;
                color: {COLORS['text_muted']};
            }}
        """)
        piezo_block.addWidget(self.lbl_big_piezo)

        self.piezo_bar_container = QFrame()
        self.piezo_bar_container.setFixedHeight(8)
        self.piezo_bar_container.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_tertiary']};
                border-radius: 4px;
            }}
        """)
        self.piezo_bar_inner = QFrame(self.piezo_bar_container)
        self.piezo_bar_inner.setGeometry(4, 2, 0, 4)
        self.piezo_bar_inner.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['accent_ok']};
                border-radius: 2px;
            }}
        """)
        piezo_block.addWidget(self.piezo_bar_container)

        self.lbl_piezo_minmax = QLabel("0 / 4095")
        self.lbl_piezo_minmax.setAlignment(Qt.AlignCenter)
        self.lbl_piezo_minmax.setStyleSheet(f"""
            color: {COLORS['text_muted']};
            font-size: 10px;
            font-family: 'Consolas', 'Courier New', monospace;
        """)
        piezo_block.addWidget(self.lbl_piezo_minmax)
        strip.addLayout(piezo_block, 2)

        # Divider
        div2 = QFrame()
        div2.setFrameShape(QFrame.VLine)
        div2.setStyleSheet(f"color: {COLORS['border']};")
        strip.addWidget(div2)

        # Phase scores row
        for phase_lbl, score_attr in [
            ("HOLD", 'hold_score'),
            ("PRESS", 'press_score'),
            ("RECOIL", 'recoil_score'),
            ("FT", 'ft_score'),
        ]:
            phase_frame = QFrame()
            phase_frame.setStyleSheet(f"""
                QFrame {{
                    background: {COLORS['bg_secondary']};
                    border: 1px solid {COLORS['border']};
                    border-radius: 8px;
                }}
            """)
            phase_inner = QVBoxLayout(phase_frame)
            phase_inner.setContentsMargins(10, 6, 10, 6)
            phase_inner.setSpacing(2)

            ph_lbl = QLabel(phase_lbl)
            ph_lbl.setAlignment(Qt.AlignCenter)
            ph_lbl.setStyleSheet(f"""
                color: {COLORS['text_muted']};
                font-size: 9px;
                text-transform: uppercase;
                letter-spacing: 1px;
            """)
            phase_inner.addWidget(ph_lbl)

            ph_val = QLabel("--")
            ph_val.setAlignment(Qt.AlignCenter)
            ph_val.setObjectName(f"lbl_{score_attr}")
            ph_val.setStyleSheet(f"""
                QLabel {{
                    color: {COLORS['text_primary']};
                    font-size: 16px;
                    font-weight: 600;
                }}
            """)
            phase_inner.addWidget(ph_val)
            strip.addWidget(phase_frame)

        strip_frame = QFrame()
        strip_frame.setMaximumHeight(110)
        strip_frame.setLayout(strip)
        center_layout.addWidget(strip_frame)

        self.lbl_context_info = QLabel(f"{DEFAULT_FIREARM} • {DEFAULT_TRAINING_MODE}")
        self.lbl_context_info.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 11px;")
        center_layout.addWidget(self.lbl_context_info)

        tab1_layout.addLayout(center_layout, 5)

        self.tabs.addTab(tab1, "Live Monitor")

    def _build_shot_analysis_tab(self):
        """Build the redesigned Shot Analysis tab — 60/40 split layout."""
        tab2 = QWidget()
        tab2.setStyleSheet(f"background: {COLORS['bg_primary']};")

        # 60/40 horizontal splitter
        splitter = QSplitter(Qt.Horizontal)
        splitter.setContentsMargins(20, 20, 20, 20)
        splitter.setHandleWidth(8)

        # ===== LEFT PANEL (60%) =====
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(12)

        # Header + Export button row
        header_row = QHBoxLayout()
        header_row.setSpacing(12)

        tab_title = QLabel("SHOT ANALYSIS")
        tab_title.setStyleSheet(
            f"color: {COLORS['text_primary']}; font-size: 18px; font-weight: 700; letter-spacing: 1px;")
        header_row.addWidget(tab_title)
        header_row.addStretch()

        self.btn_export_tab = QPushButton("Export CSV")
        self.btn_export_tab.setCursor(Qt.PointingHandCursor)
        self.btn_export_tab.clicked.connect(self._export_session_data)
        self._stylized_button(self.btn_export_tab, COLORS['accent_blue'], '#FFF')
        header_row.addWidget(self.btn_export_tab)

        left_layout.addLayout(header_row)

        # Trace canvas panel
        canvas_panel = QFrame()
        canvas_panel.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_secondary']};
                border-radius: 16px;
                padding: 16px;
            }}
        """)
        canvas_layout = QVBoxLayout(canvas_panel)
        canvas_layout.setContentsMargins(12, 12, 12, 12)
        canvas_layout.setSpacing(10)

        # Legend row — 5 phases + impact
        legend_layout = QHBoxLayout()
        legend_layout.setSpacing(16)
        for color, label in [
            ('#2196F3',  'Pre-Shot'),
            ('#00D26A',  'Hold'),
            ('#FFEB3B',  'Press'),
            ('#FF9800',  'Lock Time'),
            ('#FF5252',  'Recoil / FT'),
            ('#00E5FF',  'Impact'),
        ]:
            dot = QLabel()
            dot.setFixedSize(10, 10)
            dot.setStyleSheet(f"background: {color}; border-radius: 5px;")
            legend_layout.addWidget(dot)
            lbl = QLabel(label)
            lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px;")
            legend_layout.addWidget(lbl)
        legend_layout.addStretch()
        zoom_hint = QLabel("Scroll to zoom")
        zoom_hint.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 11px;")
        legend_layout.addWidget(zoom_hint)
        canvas_layout.addLayout(legend_layout)

        # Canvas
        self.trace_canvas = ShotTraceCanvas()
        canvas_layout.addWidget(self.trace_canvas, 1)

        # Playback controls
        self._playback_controls = PlaybackControlsWidget()
        # Wire up playback controls
        self._playback_controls.btn_play.clicked.connect(self._toggle_playback)
        self._playback_controls.btn_step_back.clicked.connect(lambda: self._step_playback(-5))
        self._playback_controls.btn_step_fwd.clicked.connect(lambda: self._step_playback(5))
        self._playback_controls.btn_skip_start.clicked.connect(self._skip_to_start)
        self._playback_controls.btn_skip_end.clicked.connect(self._skip_to_end)
        for speed, btn in self._playback_controls._speed_btns.items():
            btn.clicked.connect(lambda checked, s=speed: self._set_playback_speed(s))
        canvas_layout.addWidget(self._playback_controls)

        # Timeline scrubber
        self._timeline = TimelineSlider()
        self._timeline.valueChanged.connect(self._on_timeline_changed)
        canvas_layout.addWidget(self._timeline)

        left_layout.addWidget(canvas_panel, 1)

        # ===== RIGHT PANEL (40%) =====
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(12)

        # Shot History list (top 40%)
        history_panel = QFrame()
        history_panel.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_secondary']};
                border-radius: 16px;
                padding: 14px;
            }}
        """)
        history_layout = QVBoxLayout(history_panel)
        history_layout.setContentsMargins(10, 10, 10, 10)
        history_layout.setSpacing(8)

        history_title = QLabel("Shot History")
        history_title.setStyleSheet(
            f"color: {COLORS['text_primary']}; font-size: 14px; font-weight: 600;")
        history_layout.addWidget(history_title)

        self.list_history = QListWidget()
        self.list_history.setStyleSheet(f"""
            QListWidget {{
                background: {COLORS['bg_tertiary']};
                color: {COLORS['text_primary']};
                border: 1px solid {COLORS['border']};
                border-radius: 8px;
                padding: 6px;
                font-size: 13px;
            }}
            QListWidget::item {{
                padding: 8px;
                border-bottom: 1px solid {COLORS['border']};
            }}
            QListWidget::item:selected {{
                background: {COLORS['bg_elevated']};
            }}
        """)
        self.list_history.itemClicked.connect(self._on_shot_selected)
        history_layout.addWidget(self.list_history, 1)
        right_layout.addWidget(history_panel, 2)

        # Per-Shot Stats (middle 30%)
        per_shot_panel = QFrame()
        per_shot_panel.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_secondary']};
                border-radius: 16px;
                padding: 14px;
            }}
        """)
        per_shot_layout = QVBoxLayout(per_shot_panel)
        per_shot_layout.setContentsMargins(10, 10, 10, 10)
        per_shot_layout.setSpacing(8)

        self._per_shot_stats = PerShotStatsWidget()
        per_shot_layout.addWidget(self._per_shot_stats)
        right_layout.addWidget(per_shot_panel, 2)

        # Session Statistics (bottom 30%)
        session_panel = QFrame()
        session_panel.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_secondary']};
                border-radius: 16px;
                padding: 14px;
            }}
        """)
        session_layout = QVBoxLayout(session_panel)
        session_layout.setContentsMargins(10, 10, 10, 10)
        session_layout.setSpacing(8)

        self._session_stats = SessionStatsWidget()
        session_layout.addWidget(self._session_stats)
        right_layout.addWidget(session_panel, 2)

        # Wire up splitter
        splitter.addWidget(left_widget)
        splitter.addWidget(right_widget)
        splitter.setStretchFactor(0, 6)   # 60%
        splitter.setStretchFactor(1, 4)   # 40%

        tab_layout = QHBoxLayout(tab2)
        tab_layout.setContentsMargins(0, 0, 0, 0)
        tab_layout.addWidget(splitter)

        self.tabs.addTab(tab2, "Shot Analysis")

        # Playback timer
        self._playback_timer = QTimer()
        self._playback_timer.timeout.connect(self._advance_playback)
        self._playback_speed = 1.0

    def _score_color(self, score):
        """Return STSYS color for a score value."""
        if score >= 95: return COLORS.get('score_elite', COLORS['accent_good'])
        if score >= 85: return COLORS.get('score_expert', COLORS['accent_good'])
        if score >= 70: return COLORS.get('score_advanced', COLORS['accent_ok'])
        if score >= 50: return COLORS.get('score_intermediate', COLORS['accent_ok'])
        return COLORS.get('score_beginner', COLORS['accent_bad'])

    def _add_session_card(self, data):
        """Create a styled card widget for a session row."""
        item = QListWidgetItem()
        item.setData(Qt.UserRole, data['session_id'])

        card = QFrame()
        card.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_secondary']};
                border-radius: 14px;
                border: 1px solid {COLORS['border']};
                padding: 16px 18px;
            }}
            QFrame:hover {{ background: {COLORS['bg_elevated']}; border-color: {COLORS['accent_good']}; }}
        """)
        layout = QHBoxLayout(card)
        layout.setContentsMargins(16, 12, 16, 12)
        layout.setSpacing(16)

        # Left: date + firearm badge
        left = QVBoxLayout()
        left.setSpacing(4)
        date_lbl = QLabel(data['date_label'])
        date_lbl.setFont(QFont("Segoe UI", 10, QFont.Bold))
        date_lbl.setStyleSheet(f"color: {COLORS['accent_good']}; font-size: 10px; font-weight: 700; letter-spacing: 0.5px;")
        left.addWidget(date_lbl)
        time_lbl = QLabel(data['time_label'])
        time_lbl.setFont(QFont("Segoe UI", 20, QFont.Bold))
        time_lbl.setStyleSheet(f"color: #FFFFFF; font-size: 20px; font-weight: 700;")
        left.addWidget(time_lbl)
        badge = QLabel(data['firearm'])
        badge.setFont(QFont("Segoe UI", 11, QFont.Normal))
        badge.setStyleSheet(f"background: {COLORS['bg_tertiary']}; border-radius: 16px; padding: 3px 10px; font-size: 11px; font-weight: 600; color: {COLORS['text_primary']};")
        left.addWidget(badge)
        layout.addLayout(left, 3)

        # Middle: shot count badge
        mid = QFrame()
        mid.setStyleSheet(f"background: {COLORS['bg_tertiary']}; border-radius: 10px; padding: 6px 10px; border: 1px solid {COLORS['border']};")
        mid_layout = QVBoxLayout(mid)
        mid_layout.setContentsMargins(6, 4, 6, 4)
        mid_layout.setSpacing(0)
        mid_layout.setAlignment(Qt.AlignCenter)
        cnt = QLabel(str(data['shot_count']))
        cnt.setFont(QFont("Segoe UI", 18, QFont.Bold))
        cnt.setStyleSheet(f"font-size: 18px; font-weight: 700; color: #00D26A;")
        mid_layout.addWidget(cnt)
        shots_lbl = QLabel("shots")
        shots_lbl.setFont(QFont("Segoe UI", 11, QFont.Medium))
        shots_lbl.setStyleSheet(f"font-size: 11px; color: {COLORS['text_primary']}; font-weight: 600; letter-spacing: 0.5px;")
        mid_layout.addWidget(shots_lbl)
        layout.addWidget(mid)  # FIX BUG 3: harus addWidget(mid), bukan addLayout(mid_layout)

        # Right: avg score (colored)
        score = data['avg']
        score_color = self._score_color(score)
        right = QVBoxLayout()
        right.setAlignment(Qt.AlignRight)
        s = QLabel(f"{score:.0f}")
        s.setFont(QFont("Segoe UI", 28, QFont.Bold))
        s.setStyleSheet(f"font-size: 28px; font-weight: 700; color: {score_color};")
        right.addWidget(s)
        avg_lbl = QLabel("AVG")
        avg_lbl.setFont(QFont("Segoe UI", 9, QFont.Bold))
        avg_lbl.setStyleSheet(f"font-size: 9px; font-weight: 600; color: {COLORS['text_primary']}; letter-spacing: 1px;")
        right.addWidget(avg_lbl)
        layout.addLayout(right, 1)

        self.list_sessions.addItem(item)
        self.list_sessions.setItemWidget(item, card)
        item.setSizeHint(QSize(0, 105))

    def _make_stat_card(self, title, value):
        """Create a MantisX-style stat card."""
        card = QFrame()
        card.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_tertiary']};
                border: 1px solid {COLORS['border']};
                border-radius: 12px;
                padding: 16px;
            }}
        """)
        layout = QVBoxLayout(card)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(6)

        lbl_title = QLabel(title.upper())
        lbl_title.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px; font-weight: 600; letter-spacing: 1px;")
        lbl_title.setFont(QFont("Segoe UI", 12, QFont.Bold))
        layout.addWidget(lbl_title)

        lbl_value = QLabel(value)
        lbl_value.setObjectName("stat_value")  # FIX BUG 4: beri nama agar findChild tepat sasaran
        lbl_value.setStyleSheet(f"color: #FFFFFF; font-size: 32px; font-weight: 900;")
        lbl_value.setFont(QFont("Segoe UI", 32, QFont.Black))
        layout.addWidget(lbl_value)

        return card

    def _build_history_tab(self):
        """Build session history browser with stat cards, rich items, and detail panel."""
        tab3 = QWidget()
        tab3.setStyleSheet(f"background: {COLORS['bg_primary']};")
        tab3_layout = QVBoxLayout(tab3)
        tab3_layout.setContentsMargins(20, 20, 20, 20)
        tab3_layout.setSpacing(16)

        # Header row
        header_layout = QHBoxLayout()
        title = QLabel("Session History")
        title.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 24px; font-weight: 600;")
        header_layout.addWidget(title)

        header_layout.addStretch()

        self.cmb_history_sort = QComboBox()
        self.cmb_history_sort.addItems(['Date (Newest)', 'Date (Oldest)', 'Avg Score', 'Shot Count'])
        self.cmb_history_sort.setCurrentIndex(0)
        self.cmb_history_sort.currentIndexChanged.connect(self._on_history_sort_changed)
        self.cmb_history_sort.setStyleSheet(f"""
            QComboBox {{
                background: {COLORS['bg_tertiary']};
                color: {COLORS['text_primary']};
                border: 1px solid {COLORS['border']};
                border-radius: 6px;
                padding: 8px 14px;
            }}
        """)
        header_layout.addWidget(self.cmb_history_sort)

        self.btn_export = QPushButton("Export All")
        self.btn_export.setCursor(Qt.PointingHandCursor)
        self.btn_export.clicked.connect(self._export_report)
        self._stylized_button(self.btn_export, COLORS['accent_blue'], '#FFF')
        header_layout.addWidget(self.btn_export)

        self.btn_delete_all = QPushButton("Delete All")
        self.btn_delete_all.setCursor(Qt.PointingHandCursor)
        self.btn_delete_all.clicked.connect(self._delete_all_sessions)
        self._stylized_button(self.btn_delete_all, '#FF5252', '#FFF')
        header_layout.addWidget(self.btn_delete_all)

        tab3_layout.addLayout(header_layout)

        # Stat cards row
        stat_row = QHBoxLayout()
        stat_row.setSpacing(16)
        stat_row.setContentsMargins(0, 0, 0, 0)
        for i, card in enumerate(["Sessions", "Shots", "Avg Score", "Best"]):
            stat_card = self._make_stat_card(card, "0" if i < 2 else "--")
            stat_row.addWidget(stat_card, 1)  # Equal stretch
        self._stat_sessions = stat_row.itemAt(0).widget()
        self._stat_shots    = stat_row.itemAt(1).widget()
        self._stat_avg      = stat_row.itemAt(2).widget()
        self._stat_best     = stat_row.itemAt(3).widget()
        tab3_layout.addLayout(stat_row)

        # Session list
        self.list_sessions = QListWidget()
        self.list_sessions.itemClicked.connect(self._on_session_selected)
        self.list_sessions.setStyleSheet(f"""
            QListWidget {{
                background: {COLORS['bg_secondary']};
                color: {COLORS['text_primary']};
                border: 1px solid {COLORS['border']};
                border-radius: 12px;
                padding: 8px;
                font-size: 14px;
            }}
            QListWidget::item {{
                padding: 0px;          /* FIX BUG A: padding konflik dengan setItemWidget, harus 0 */
                border-bottom: none;
            }}
            QListWidget::item:selected {{
                background: transparent;
            }}
        """)
        tab3_layout.addWidget(self.list_sessions, 1)

        # Detail panel (hidden until session selected)
        self._detail_panel = QFrame()
        self._detail_panel.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_secondary']};
                border-radius: 12px;
                padding: 16px;
            }}
        """)
        self._detail_panel.setVisible(False)
        detail_layout = QVBoxLayout(self._detail_panel)
        detail_layout.setContentsMargins(12, 12, 12, 12)
        detail_layout.setSpacing(10)

        detail_header = QHBoxLayout()
        detail_title = QLabel("Shot Details")
        detail_title.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 16px; font-weight: 600;")
        detail_header.addWidget(detail_title)
        detail_header.addStretch()
        btn_export_session = QPushButton("Export This Session")
        btn_export_session.setCursor(Qt.PointingHandCursor)
        btn_export_session.clicked.connect(self._export_current_session)
        self._stylized_button(btn_export_session, COLORS['accent_blue'], '#FFF')
        detail_header.addWidget(btn_export_session)
        detail_layout.addLayout(detail_header)

        self._shot_detail_list = QListWidget()
        self._shot_detail_list.itemClicked.connect(self._on_shot_detail_selected)
        self._shot_detail_list.setStyleSheet(f"""
            QListWidget {{
                background: {COLORS['bg_tertiary']};
                color: {COLORS['text_primary']};
                border: 1px solid {COLORS['border']};
                border-radius: 8px;
                padding: 4px;
                font-size: 12px;
            }}
            QListWidget::item {{
                padding: 0px;          /* FIX BUG B: padding konflik dengan setItemWidget */
                border-bottom: none;
            }}
            QListWidget::item:selected {{
                background: transparent;
            }}
        """)
        detail_layout.addWidget(self._shot_detail_list, 1)
        tab3_layout.addWidget(self._detail_panel)

        self._refresh_history_list()
        self.tabs.addTab(tab3, "History")

    def _section_header(self, text):
        """Create an uppercase STSYS-style section header."""
        lbl = QLabel(text.upper())
        lbl.setStyleSheet(f"""
            color: {COLORS['accent_good']};
            font-size: 10px;
            font-weight: 700;
            letter-spacing: 2px;
            padding: 12px 0 6px;
        """)
        self._settings_content_layout().addWidget(lbl)
        return lbl

    def _settings_content_layout(self):
        return getattr(self, '_settings_content_layout_var', None)

    def _update_firearm_btn_style(self, btn, selected):
        if selected:
            btn.setStyleSheet(f"""
                QPushButton {{
                    background: qlineargradient(x1:0, y1:0, x2:1, y2:1, stop:0 {COLORS['accent_good']}, stop:1 #FF6B00);
                    color: {COLORS['bg_primary']};
                    border: none;
                    border-radius: 8px;
                    padding: 12px 16px;
                    font-size: 12px;
                    font-weight: 800;
                }}
                QPushButton:hover {{ opacity: 0.9; }}
            """)
        else:
            btn.setStyleSheet(f"""
                QPushButton {{
                    background: {COLORS['bg_tertiary']};
                    color: {COLORS['text_muted']};
                    border: 1px solid {COLORS['border']};
                    border-radius: 8px;
                    padding: 12px 16px;
                    font-size: 12px;
                    font-weight: 600;
                }}
                QPushButton:hover {{ background: {COLORS['bg_elevated']}; color: {COLORS['text_primary']}; }}
            """)

    def _update_mode_btn_style(self, btn, selected):
        if selected:
            btn.setStyleSheet(f"""
                QPushButton {{
                    background: qlineargradient(x1:0, y1:0, x2:1, y2:1, stop:0 {COLORS['accent_good']}, stop:1 #FF6B00);
                    color: {COLORS['bg_primary']};
                    border: none;
                    border-radius: 8px;
                    padding: 12px 24px;
                    font-size: 12px;
                    font-weight: 800;
                }}
                QPushButton:hover {{ opacity: 0.9; }}
            """)
        else:
            btn.setStyleSheet(f"""
                QPushButton {{
                    background: {COLORS['bg_tertiary']};
                    color: {COLORS['text_muted']};
                    border: 1px solid {COLORS['border']};
                    border-radius: 8px;
                    padding: 12px 24px;
                    font-size: 12px;
                    font-weight: 600;
                }}
                QPushButton:hover {{ background: {COLORS['bg_elevated']}; color: {COLORS['text_primary']}; }}
            """)

    def _select_firearm(self, firearm):
        self.current_firearm = firearm
        for btn in self._firearm_btns:
            self._update_firearm_btn_style(btn, btn.text() == firearm)
        if hasattr(self, 'lbl_context_info'):
            self.lbl_context_info.setText(f"{self.current_firearm} • {self.current_training_mode}")
        if hasattr(self, 'lbl_firearm_mult'):
            self.lbl_firearm_mult.setText(f"{self.current_firearm} x{FIREARM_MULTIPLIERS.get(self.current_firearm, 1.0):.1f}")
        self._sync_mode_to_cmb()
        self._save_settings()

    def _select_training_mode(self, mode):
        self.current_training_mode = mode
        for btn in self._mode_btns:
            self._update_mode_btn_style(btn, btn.text() == mode)
        if hasattr(self, 'lbl_context_info'):
            self.lbl_context_info.setText(f"{self.current_firearm} • {self.current_training_mode}")
        if hasattr(self, 'lbl_mode_mult'):
            self.lbl_mode_mult.setText(f"{self.current_training_mode} x{TRAINING_MODE_MULTIPLIERS.get(self.current_training_mode, 1.0):.1f}")
        self._sync_mode_to_cmb()
        self._save_settings()

    def _sync_mode_to_cmb(self):
        """Sync Live Monitor detection mode combobox to Training Mode setting."""
        target = 0 if self.current_training_mode == 'Dry Fire' else 1
        if hasattr(self, 'cmb_mode') and self.cmb_mode.currentIndex() != target:
            self.cmb_mode.blockSignals(True)
            self.cmb_mode.setCurrentIndex(target)
            self.cmb_mode.blockSignals(False)
            # Also update detector trigger mode
            self.detector.trigger_mode = target

    def _set_mount_direction(self, direction):
        self.current_mount_direction = direction
        self.detector.mount_direction = direction
        if hasattr(self, 'mount_dir_btns'):
            for btn in self.mount_dir_btns:
                self._update_mount_btn_style(btn, btn.text() == direction)

    def _select_mount_direction(self, direction):
        self._set_mount_direction(direction)
        # Re-tare so existing trace clears and next sample uses new direction
        if hasattr(self, 'detector') and self.detector.is_calibrated:
            self.detector._apply_tare()
        self._save_settings()

    def _update_mount_btn_style(self, btn, selected):
        accent = COLORS['accent_good']
        if selected:
            btn.setStyleSheet(f"""
                QPushButton {{
                    background: {accent};
                    color: #0D0D0D;
                    border-radius: 8px;
                    padding: 8px 16px;
                    font-size: 11px;
                    font-weight: 600;
                }}
            """)
        else:
            btn.setStyleSheet(f"""
                QPushButton {{
                    background: {COLORS['bg_tertiary']};
                    color: {COLORS['text_secondary']};
                    border-radius: 8px;
                    padding: 8px 16px;
                    font-size: 11px;
                }}
                QPushButton:hover {{ background: {COLORS['bg_elevated']}; color: {COLORS['text_primary']}; }}
            """)
        """Sync Live Monitor detection mode combobox to Training Mode setting."""
        target = 0 if self.current_training_mode == 'Dry Fire' else 1
        if hasattr(self, 'cmb_mode') and self.cmb_mode.currentIndex() != target:
            self.cmb_mode.blockSignals(True)
            self.cmb_mode.setCurrentIndex(target)
            self.cmb_mode.blockSignals(False)
            # Also update detector trigger mode
            self.detector.trigger_mode = target

    def _refresh_history_list(self, sort='date'):
        """Populate session list with styled card widgets and update stat cards."""
        sessions = get_all_sessions()
        self.list_sessions.clear()

        if not sessions:
            # FIX BUG 4: gunakan findChild dengan objectName agar update value, bukan title label
            self._stat_sessions.findChild(QLabel, 'stat_value').setText("0")
            self._stat_shots.findChild(QLabel, 'stat_value').setText("0")
            self._stat_avg.findChild(QLabel, 'stat_value').setText("--")
            self._stat_best.findChild(QLabel, 'stat_value').setText("--")
            return

        enriched = []
        all_scores = []
        for row in sessions:
            sid = row['session_id']
            shots = get_session_shots(sid)
            scores = [s['score'] for s in shots if s.get('score') is not None]
            avg = sum(scores) / len(scores) if scores else 0.0
            best = max(scores) if scores else 0.0
            all_scores.extend(scores)
            firearm = ''
            mode = row['mode'] or 'Unknown'
            if shots and shots[0].get('firearm'):
                firearm = shots[0]['firearm']

            # Parse date/time from session_id (format: YYYYMMDD_HHMMSS)
            sid_str = sid or ''
            if '_' in sid_str and len(sid_str) >= 15:
                parts = sid_str.split('_', 1)
                date_part = parts[0]
                time_part = parts[1] if len(parts) > 1 else ''
                try:
                    date_obj = datetime.strptime(date_part, "%Y%m%d")
                    date_label = date_obj.strftime("%d %b %Y").upper()
                except:
                    date_label = date_part
                try:
                    time_label = f"{time_part[:2]}:{time_part[2:4]}:{time_part[4:6]}"
                except:
                    time_label = time_part
            else:
                date_label = sid_str[:8] if len(sid_str) >= 8 else sid_str
                time_label = sid_str[9:17] if len(sid_str) > 9 else sid_str

            enriched.append({
                'session_id': sid, 'shot_count': len(shots),
                'avg': avg, 'best': best,
                'date_label': date_label, 'time_label': time_label,
                'firearm': firearm or mode, 'mode': mode
            })

        sort_map = {
            'date': lambda e: e['session_id'],
            'date_asc': lambda e: e['session_id'],
            'avg_score': lambda e: e['avg'],
            'shot_count': lambda e: e['shot_count'],
        }
        reverse = sort != 'date_asc'
        enriched.sort(key=sort_map.get(sort, sort_map['date']), reverse=reverse)

        for e in enriched:
            self._add_session_card(e)

        total_sessions = len(enriched)
        total_shots = sum(e['shot_count'] for e in enriched)
        avg_all = sum(all_scores) / len(all_scores) if all_scores else 0.0
        best_all = max(all_scores) if all_scores else 0.0

        # FIX BUG 4: gunakan findChild dengan objectName 'stat_value'
        self._stat_sessions.findChild(QLabel, 'stat_value').setText(str(total_sessions))
        self._stat_shots.findChild(QLabel, 'stat_value').setText(str(total_shots))
        self._stat_avg.findChild(QLabel, 'stat_value').setText(f"{avg_all:.1f}" if all_scores else "--")
        self._stat_best.findChild(QLabel, 'stat_value').setText(f"{best_all:.1f}" if all_scores else "--")

    def _delete_all_sessions(self):
        """Delete all sessions and their shots from the database."""
        from PyQt5.QtWidgets import QMessageBox
        reply = QMessageBox.question(
            self, 'Delete All Sessions',
            'Are you sure you want to delete ALL sessions and shot data?\nThis cannot be undone.',
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
        if reply == QMessageBox.Yes:
            with sqlite3.connect(DB_FILE) as conn:
                conn.execute("DELETE FROM shot_traces")
                conn.execute("DELETE FROM sessions")
                conn.commit()
            self._refresh_history_list()

    def _on_history_sort_changed(self, idx):
        sort_map = ['date', 'date_asc', 'avg_score', 'shot_count']
        self._refresh_history_list(sort_map[idx])

    def _on_session_selected(self, item):
        sid = item.data(Qt.UserRole)
        shots = get_session_shots(sid)
        self._detail_panel.setVisible(True)
        self._shot_detail_list.clear()
        for s in shots:
            score = s.get('score', 0)
            color = self._score_color(score)
            grade = s.get('stability_grade', '') or ''
            err = s.get('error_type', '')
            err_str = f"[{err}]" if err and err != 'NONE' else ''
            imp_x = s.get('impact_x_cm', 0) or 0
            imp_y = s.get('impact_y_cm', 0) or 0
            ts = s.get('timestamp', '') or ''
            ts_str = ts[:19] if ts else '?'

            row = QFrame()
            row.setStyleSheet(f"background: {COLORS['bg_tertiary']}; border-radius: 6px; padding: 6px; margin-bottom: 4px;")
            row_layout = QHBoxLayout(row)
            row_layout.setContentsMargins(6, 4, 6, 4)
            row_layout.setSpacing(6)

            # Shot number
            shot_lbl = QLabel(f"Shot {s['shot_number']}")
            shot_lbl.setStyleSheet(f"color: {COLORS['accent_good']}; font-size: 10px; font-weight: 700; letter-spacing: 0.5px;")
            row_layout.addWidget(shot_lbl)

            # Time
            time_lbl = QLabel(ts_str)
            time_lbl.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 10px;")
            row_layout.addWidget(time_lbl)

            row_layout.addStretch()

            # Score badge
            score_badge = QLabel(f"{score:.0f}")
            score_badge.setStyleSheet(
                f"background: {color}33; border: 1px solid {color}; "
                f"border-radius: 6px; padding: 4px 10px; "
                f"font-size: 12px; font-weight: 700; color: {color};")
            row_layout.addWidget(score_badge)

            # Grade
            if grade:
                grade_lbl = QLabel(f"[{grade}]")
                grade_lbl.setStyleSheet(f"color: {color}; font-size: 11px; font-weight: 700;")
                row_layout.addWidget(grade_lbl)

            # Error badge
            if err_str:
                err_badge = QLabel(err_str)
                err_badge.setStyleSheet(
                    f"background: {COLORS['accent_ok']}33; border: 1px solid {COLORS['accent_ok']}; "
                    f"border-radius: 4px; padding: 2px 6px; "
                    f"font-size: 9px; color: {COLORS['accent_ok']};")
                row_layout.addWidget(err_badge)

            # Impact
            imp_lbl = QLabel(f"({imp_x:+.1f}, {imp_y:+.1f}) cm")
            imp_lbl.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 10px;")
            row_layout.addWidget(imp_lbl)

            list_item = QListWidgetItem()
            list_item.setData(Qt.UserRole, s)
            self._shot_detail_list.addItem(list_item)
            self._shot_detail_list.setItemWidget(list_item, row)
            list_item.setSizeHint(QSize(0, 48))

    def _on_shot_detail_selected(self, item):
        s = item.data(Qt.UserRole)
        if not s or not s.get('aim_trace'):
            return
        trace = s['aim_trace']
        self.trace_canvas.set_trace(
            preshot_routine=trace.get('preshot_routine') or trace.get('preshot'),
            approach_settle=trace.get('approach_settle'),
            hold=trace.get('hold'),
            press=trace.get('press'),
            break_pt=trace.get('break'),
            ft=trace.get('followthrough'),
            impact_x_cm=s.get('impact_x_cm', 0.0), impact_y_cm=s.get('impact_y_cm', 0.0))
        self.tabs.setCurrentIndex(1)

    def _export_current_session(self):
        """Export only the currently selected session's shots."""
        sel = self.list_sessions.currentItem()
        if not sel:
            return
        sid = sel.data(Qt.UserRole)
        shots = get_session_shots(sid)
        if not shots:
            return
        reports_dir = os.path.join(SCRIPT_DIR, 'reports')
        os.makedirs(reports_dir, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        csv_path = os.path.join(reports_dir, f'stasy_session_{sid}_{ts}.csv')
        try:
            with open(csv_path, 'w', newline='', encoding='utf-8') as f:
                f.write("Shot,Timestamp,Stability_score,Stability_grade,Shooting_score,Shooting_grade,"
                        "A2C_angle_deg,A2C_mag_mrad,Hold_score,Press_score,Recoil_score,FT_score,"
                        "Hold_stability_deg,Recovery_ms,Error_type,Severity,Impact_X_cm,Impact_Y_cm,"
                        "Target_m,Piezo,Firearm,Training_mode\n")
                for shot in shots:
                    f.write(f"{shot['shot_number']},"
                            f"{shot.get('timestamp','N/A')[:19] if shot.get('timestamp') else 'N/A'},"
                            f"{shot.get('stability_score', 0):.1f},"
                            f"{shot.get('stability_grade', '')},"
                            f"{shot.get('shooting_score', 0):.1f},"
                            f"{shot.get('shooting_grade', '')},"
                            f"{shot.get('a2c_angle', 0):.1f},"
                            f"{shot.get('a2c_mag', 0) * 1000:.2f},"
                            f"{shot.get('hold_score', 0):.1f},"
                            f"{shot.get('press_score', 0):.1f},"
                            f"{shot.get('recoil_score', 0):.1f},"
                            f"{shot.get('ft_score', 0):.1f},"
                            f"{math.degrees(shot.get('hold_stability', 0)):.3f},"
                            f"{shot.get('recoil_recovery_ms', 0):.0f},"
                            f"{shot.get('error_type', 'NONE')},"
                            f"{shot.get('error_severity', '')},"
                            f"{shot.get('impact_x_cm', 0):+.2f},"
                            f"{shot.get('impact_y_cm', 0):+.2f},"
                            f"{shot.get('target_distance', DEFAULT_TARGET_DISTANCE):.1f},"
                            f"{shot.get('piezo_value', 0)},"
                            f"{shot.get('firearm', '')},"
                            f"{shot.get('training_mode', '')}\n")
            logger.info(f"Session export saved: {csv_path}")
        except Exception:
            logger.exception("Failed to export session")

    def _build_settings_tab(self):
        """Build settings tab."""
        tab4 = QWidget()
        tab4.setStyleSheet(f"background: {COLORS['bg_primary']};")
        tab4_layout = QVBoxLayout(tab4)
        tab4_layout.setContentsMargins(0, 0, 0, 0)
        tab4_layout.setSpacing(0)

        title = QLabel("Settings")
        title.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 24px; font-weight: 600; padding: 24px 24px 16px;")
        tab4_layout.addWidget(title)

        # Scrollable content area
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet(f"""
            QScrollArea {{ background: {COLORS['bg_primary']}; border: none; }}
            QScrollArea > QWidget > QWidget {{ background: {COLORS['bg_primary']}; }}
        """)
        content = QWidget()
        self._settings_content_layout_var = QVBoxLayout(content)
        content_layout = self._settings_content_layout_var
        content_layout.setContentsMargins(24, 8, 24, 24)
        content_layout.setSpacing(20)

        # Firearm Profile (chip-style selection, like Flutter app)
        self._section_header("Firearm Profile")
        self._firearm_btns = []
        firearm_options = ['Pistol', 'Rifle', 'Archery', 'Shotgun']
        for opt in firearm_options:
            btn = QPushButton(opt)
            btn.setCursor(Qt.PointingHandCursor)
            btn.clicked.connect(lambda _, o=opt: self._select_firearm(o))
            self._firearm_btns.append(btn)
        # 2x2 grid layout for chips
        profile_grid = QGridLayout()
        profile_grid.setSpacing(8)
        profile_grid.addWidget(self._firearm_btns[0], 0, 0)
        profile_grid.addWidget(self._firearm_btns[1], 0, 1)
        profile_grid.addWidget(self._firearm_btns[2], 1, 0)
        profile_grid.addWidget(self._firearm_btns[3], 1, 1)
        for btn in self._firearm_btns:
            is_sel = (btn.text() == self.current_firearm)
            self._update_firearm_btn_style(btn, is_sel)
        content_layout.addLayout(profile_grid)

        self._section_header("Training Mode")
        self._mode_btns = []
        mode_options = ['Dry Fire', 'Live Fire']
        mode_layout = QHBoxLayout()
        mode_layout.setSpacing(8)
        for opt in mode_options:
            btn = QPushButton(opt)
            btn.setCursor(Qt.PointingHandCursor)
            btn.clicked.connect(lambda _, o=opt: self._select_training_mode(o))
            self._mode_btns.append(btn)
            mode_layout.addWidget(btn)
        for btn in self._mode_btns:
            is_sel = (btn.text() == self.current_training_mode)
            self._update_mode_btn_style(btn, is_sel)
        content_layout.addLayout(mode_layout)

        self._section_header("Mount Direction")
        self.mount_dir_btns = []
        mount_options = ['Forward', 'Backward']
        mount_layout = QHBoxLayout()
        mount_layout.setSpacing(8)
        for opt in mount_options:
            btn = QPushButton(opt)
            btn.setCursor(Qt.PointingHandCursor)
            btn.clicked.connect(lambda _, o=opt: self._select_mount_direction(o))
            self.mount_dir_btns.append(btn)
            mount_layout.addWidget(btn)
        for btn in self.mount_dir_btns:
            is_sel = (btn.text().capitalize() == self.current_mount_direction.capitalize())
            self._update_mount_btn_style(btn, is_sel)
        content_layout.addLayout(mount_layout)

        # Connection settings
        self._section_header("Connection")
        conn_frame = self._settings_group("")
        conn_layout = QGridLayout(conn_frame)
        conn_layout.setSpacing(16)

        port_lbl = QLabel("COM Port")
        port_lbl.setStyleSheet(f"color: {COLORS['text_secondary']};")
        conn_layout.addWidget(port_lbl, 0, 0)
        self.cmb_com_port = QComboBox()
        self.cmb_com_port.addItems(["COM22", "COM25", "COM13", "COM14", "COM1", "COM2", "COM3", "COM4", "COM5"])
        conn_layout.addWidget(self.cmb_com_port, 0, 1)

        baud_lbl = QLabel("Baud Rate")
        baud_lbl.setStyleSheet(f"color: {COLORS['text_secondary']};")
        conn_layout.addWidget(baud_lbl, 1, 0)
        self.spin_baud = QComboBox()
        self.spin_baud.addItems(["9600", "19200", "38400", "57600", "115200", "230400"])
        self.spin_baud.setCurrentText(str(BAUD_RATE))
        conn_layout.addWidget(self.spin_baud, 1, 1)

        for widget in [self.cmb_com_port, self.spin_baud]:
            widget.setStyleSheet(f"""
                QComboBox {{
                    background: {COLORS['bg_tertiary']};
                    color: {COLORS['text_primary']};
                    border: 1px solid {COLORS['border']};
                    border-radius: 6px;
                    padding: 10px 14px;
                }}
            """)
        scroll.setWidget(content)
        tab4_layout.addWidget(scroll, 1)

        # Connect connection settings to auto-save
        if hasattr(self, 'cmb_com_port'):
            self.cmb_com_port.currentTextChanged.connect(self._save_settings)
        if hasattr(self, 'spin_baud'):
            self.spin_baud.currentTextChanged.connect(self._save_settings)

        self.tabs.addTab(tab4, "Settings")

        # Tab switch: refresh history list when History tab is shown
        self.tabs.currentChanged.connect(lambda i: i == 2 and self._refresh_history_list())

    def _settings_group(self, title):
        """Create a grouped settings section."""
        frame = QFrame()
        frame.setStyleSheet(f"""
            QFrame {{
                background: {COLORS['bg_secondary']};
                border-radius: 12px;
                padding: 16px;
            }}
        """)
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(16)

        title_lbl = QLabel(title)
        title_lbl.setStyleSheet(f"color: {COLORS['text_primary']}; font-size: 16px; font-weight: 600;")
        layout.addWidget(title_lbl)

        return frame

    def change_mode(self):
        self.detector.trigger_mode = self.cmb_mode.currentIndex()
        self.session_mode = self.cmb_mode.currentText().split(" (")[0]
        if self.detector.trigger_mode == 1:
            self.spin_jerk.setValue(LIVE_FIRE_DEFAULT_JERK)
            self.spin_piezo.setValue(LIVE_FIRE_DEFAULT_PIEZO)
        else:
            self.spin_jerk.setValue(DEFAULT_ACCEL_THRESH)
            self.spin_piezo.setValue(DEFAULT_PIEZO_MIN)

    def _load_settings(self):
        defaults = {
            'firearm': DEFAULT_FIREARM, 'training_mode': DEFAULT_TRAINING_MODE,
            'mount_direction': 'forward',
            'com_port': BLUETOOTH_COM_PORT, 'piezo_min': DEFAULT_PIEZO_MIN,
            'jerk_thresh': DEFAULT_ACCEL_THRESH,
            'travel_penalty': SCORE_PENALTY_TRAVEL, 'jerk_penalty': SCORE_PENALTY_JERK
        }
        try:
            with open(os.path.join(SCRIPT_DIR, 'settings.json')) as f:
                defaults.update(json.load(f))
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        self._settings = defaults
        # Apply loaded values to instance state
        self.current_firearm = self._settings.get('firearm', DEFAULT_FIREARM)
        self.current_training_mode = self._settings.get('training_mode', DEFAULT_TRAINING_MODE)
        self.current_mount_direction = self._settings.get('mount_direction', 'forward')

    def _save_settings(self):
        self._settings.update({
            'firearm': self.current_firearm,
            'training_mode': self.current_training_mode,
            'mount_direction': self.current_mount_direction,
            'com_port': self.cmb_com_port.currentText() if hasattr(self, 'cmb_com_port') else BLUETOOTH_COM_PORT,
            'piezo_min': self.spin_piezo.value() if hasattr(self, 'spin_piezo') else DEFAULT_PIEZO_MIN,
            'jerk_thresh': self.spin_jerk.value() if hasattr(self, 'spin_jerk') else DEFAULT_ACCEL_THRESH,
            'travel_penalty': self.score_spins[0].value() if hasattr(self, 'score_spins') and len(self.score_spins) > 0 else SCORE_PENALTY_TRAVEL,
            'jerk_penalty': self.score_spins[1].value() if hasattr(self, 'score_spins') and len(self.score_spins) > 1 else SCORE_PENALTY_JERK,
        })
        try:
            with open(os.path.join(SCRIPT_DIR, 'settings.json'), 'w') as f:
                json.dump(self._settings, f, indent=2)
        except Exception as e:
            logger.warning("settings save failed: %s", e)

    def _on_profile_changed(self):
        # Deprecated: firearm/mode now use _select_firearm / _select_training_mode
        pass

    def toggle_dry_fire_mode(self, enabled):
        self.detector.dry_fire_mode = enabled

    def toggle_recording(self):
        if not self._recording and self._countdown_value == 0:
            self._countdown_value = 3
            self._do_countdown()
        elif self._recording:
            self._recording = False
            self._countdown_value = 0
            self._shot_impacts = []
            self.btn_record.setText("▶ START RECORD")
            if hasattr(self, '_refresh_history_list'):
                self._refresh_history_list()
            self.btn_record.setStyleSheet(f"""
                QPushButton {{
                    background: {COLORS['accent_good']};
                    color: #0D0D0D;
                    border: 1px solid {COLORS['accent_good']};
                    border-radius: 6px;
                    padding: 12px 20px;
                    font-size: 13px;
                    font-weight: 600;
                }}
                QPushButton:hover {{ background: {COLORS['accent_good']}dd; }}
            """)
            self.lbl_record_state.setText("■ STOPPED")
            self.lbl_record_state.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 12px;")

    def _do_countdown(self):
        if self._countdown_value > 0:
            self.lbl_record_state.setText(f"◉ {self._countdown_value}...")
            self.lbl_record_state.setStyleSheet(f"color: {COLORS['accent_ok']}; font-size: 12px; font-weight: 600;")
            self._countdown_value -= 1
            QTimer.singleShot(1000, self._do_countdown)
        else:
            self._recording = True
            # Save session to DB when START RECORD is pressed — creates new session
            if not self._session_saved:
                start_session(self.session_id, self.session_mode)
                self._session_saved = True
            self.btn_record.setText("⏹ STOP RECORD")
            self.btn_record.setStyleSheet(f"""
                QPushButton {{
                    background: {COLORS['accent_bad']};
                    color: #FFF;
                    border: 1px solid {COLORS['accent_bad']};
                    border-radius: 6px;
                    padding: 12px 20px;
                    font-size: 13px;
                    font-weight: 600;
                }}
                QPushButton:hover {{ background: {COLORS['accent_bad']}dd; }}
            """)
            self.lbl_record_state.setText("⬤ RECORDING")
            self.lbl_record_state.setStyleSheet(f"color: {COLORS['accent_good']}; font-size: 12px; font-weight: 600;")

    def update_thresholds(self):
        self.detector.accel_thresh = self.spin_jerk.value()
        self.detector.piezo_thresh = self.spin_piezo.value()

    def start_calibration(self, auto=False):
        self.calib_buffer = []
        self.calibrating = True
        self._auto_calibrating = auto
        if auto:
            self.btn_calib.setText("AUTO-CALIBRATING...")
            self.btn_calib.setStyleSheet("""
                QPushButton {
                    background: #FF9800;
                    color: #000;
                    border: 1px solid #FF9800;
                    border-radius: 6px;
                    padding: 12px 20px;
                    font-size: 13px;
                    font-weight: 600;
                }
            """)
            self.btn_calib.setEnabled(False)
        else:
            self.btn_calib.setText("CALIBRATING...")
            self.btn_calib.setStyleSheet("""
                QPushButton {
                    background: #FF9800;
                    color: #000;
                    border: 1px solid #FF9800;
                    border-radius: 6px;
                    padding: 12px 20px;
                    font-size: 13px;
                    font-weight: 600;
                }
            """)

    def _load_or_auto_calibrate(self):
        saved = load_device_calibration(self._device_key)
        if saved:
            self.detector.gyro_bias = saved['gyro_bias']
            self.detector.q = np.array(saved['q'], dtype=np.float64)
            self.detector.accel_bias = saved['accel_bias']
            self.detector._apply_tare()
            self.detector.is_calibrated = True
            self._show_calibrated_ui("DEVICE CALIBRATED")
            logger.info("Loaded calibration from DB for device: %s", self._device_key)
        else:
            logger.info("No calibration found for %s — auto-calibrating...", self._device_key)
            self.start_calibration(auto=True)

    def _show_calibrated_ui(self, status_text="CALIBRATED"):
        self.btn_calib.setText(status_text)
        self.btn_calib.setStyleSheet("""
            QPushButton {
                background: #00D26A;
                color: #0D0D0D;
                border: 1px solid #00D26A;
                border-radius: 6px;
                padding: 12px 20px;
                font-size: 13px;
                font-weight: 600;
            }
        """)
        self.btn_calib.setEnabled(False)
        self.lbl_status.setText("READY")
        self.lbl_status.setStyleSheet(f"""
            QLabel {{
                background: {COLORS['accent_good']};
                color: #0D0D0D;
                font-size: 14px;
                font-weight: 600;
                border-radius: 8px;
                padding: 16px;
            }}
        """)

    def _on_calibration_complete(self):
        self.btn_calib.setText("CALIBRATED")
        self.btn_calib.setStyleSheet("""
            QPushButton {
                background: #00D26A;
                color: #0D0D0D;
                border: 1px solid #00D26A;
                border-radius: 6px;
                padding: 12px 20px;
                font-size: 13px;
                font-weight: 600;
            }
        """)
        self.lbl_status.setText("READY")
        self.lbl_status.setStyleSheet(f"""
            QLabel {{
                background: {COLORS['accent_good']};
                color: #0D0D0D;
                font-size: 14px;
                font-weight: 600;
                border-radius: 8px;
                padding: 16px;
            }}
        """)
        # Save calibration for this device if auto-cal triggered
        if self._auto_calibrating and self._device_key and self._device_key != "SIM":
            save_device_calibration(
                self._device_key,
                self.detector.gyro_bias,
                self.detector.q.tolist(),
                self.detector.accel_bias,
                len(self.calib_buffer)
            )
            logger.info("Saved auto-calibration for device: %s", self._device_key)
        self._auto_calibrating = False

    def do_tare(self):
        if not self.detector.is_calibrated:
            self.lbl_status.setText("CALIBRATE FIRST")
            self.lbl_status.setStyleSheet(f"""
                QLabel {{
                    background: #5D4037;
                    color: #FFF;
                    font-size: 14px;
                    font-weight: 600;
                    border-radius: 8px;
                    padding: 16px;
                }}
            """)
            return
        self.detector.tare()
        self.btn_tare.setText("TARE APPLIED")
        self.btn_tare.setStyleSheet("""
            QPushButton {
                background: #00D26A;
                color: #0D0D0D;
                border: 1px solid #00D26A;
                border-radius: 6px;
                padding: 12px 20px;
                font-size: 13px;
                font-weight: 600;
            }
        """)
        QTimer.singleShot(1500, lambda: self._reset_tare_button())

    def _reset_tare_button(self):
        self.btn_tare.setText("TARE — Re-Zero Aim")
        self.btn_tare.setStyleSheet("""
            QPushButton {
                background: #1B5E20;
                color: #00D26A;
                border: 1px solid #00D26A;
                border-radius: 6px;
                padding: 12px 20px;
                font-size: 13px;
                font-weight: 600;
            }
            QPushButton:hover { background: #1B5E20dd; }
        """)

    def _update_stats(self):
        """No-op: session stats removed."""
        pass

    def _on_shot_selected(self, item):
        """Handle shot selection from history list — load trace, stats, and update timeline."""
        idx = self.list_history.row(item)
        if 0 <= idx < len(self.shot_history):
            shot = self.shot_history[idx]

            # Pause any running playback
            if hasattr(self, '_playback_timer') and self._playback_timer.isActive():
                self._playback_timer.stop()
                self._playback_controls.set_playing(False)

            # Load trace into canvas (6-phase format, with fallback for old DB format)
            self.trace_canvas.set_trace(
                preshot_routine=shot.get('preshot_routine') or shot.get('preshot'),
                approach_settle=shot.get('approach_settle'),
                hold=shot.get('hold'),
                press=shot.get('press'),
                break_pt=shot.get('break'),
                ft=shot.get('followthrough'),
                impact_x_cm=shot.get('impact_x_cm', 0.0),
                impact_y_cm=shot.get('impact_y_cm', 0.0))
            self.trace_canvas.current_shot_idx = shot.get('shot_number', idx + 1)

            # Update timeline scrubber
            total = self._get_total_trace_samples()
            self._timeline.set_trace_info(self.trace_canvas.phase_boundaries, total)
            self._timeline.setValue(0)

            # Populate per-shot stats
            self._per_shot_stats.populate(shot)

            # Update session stats (from all shots)
            self._session_stats.populate(self.shot_history)

    def _step_trace(self, delta):
        """Step forward/backward in trace playback (legacy method, kept for compatibility)."""
        self._step_playback(delta)

    def _step_playback(self, delta):
        """Step forward/backward in trace playback by delta samples."""
        if not hasattr(self, 'trace_canvas'):
            return
        total = self._get_total_trace_samples()
        self.trace_canvas.playback_pos = max(0, min(total, self.trace_canvas.playback_pos + delta))
        self._timeline.setValue(self.trace_canvas.playback_pos)
        self.trace_canvas.update()

    def _toggle_playback(self):
        """Toggle trace playback animation (play/pause)."""
        if not hasattr(self, '_playback_timer'):
            return

        if self._playback_timer.isActive():
            # Pause
            self._playback_timer.stop()
            self._playback_controls.set_playing(False)
        else:
            # Play
            total = self._get_total_trace_samples()
            if self.trace_canvas.playback_pos >= total:
                self.trace_canvas.playback_pos = 0
            interval = int(10 / self._playback_speed)  # 10ms base = 100Hz
            self._playback_timer.start(interval)
            self._playback_controls.set_playing(True)

    def _advance_playback(self):
        """Timer callback to advance playback position by 1 sample."""
        if not hasattr(self, 'trace_canvas'):
            return
        total = self._get_total_trace_samples()
        self.trace_canvas.playback_pos += 1
        if self.trace_canvas.playback_pos >= total:
            # End of trace — stop and reset
            self._playback_timer.stop()
            self._playback_controls.set_playing(False)
            self.trace_canvas.playback_pos = 0
        self._timeline.setValue(self.trace_canvas.playback_pos)
        self.trace_canvas.update()

    def _set_playback_speed(self, speed):
        """Set playback speed multiplier (0.5, 1.0, 2.0)."""
        self._playback_speed = speed
        self._playback_controls.set_speed(speed)
        # If playing, restart timer with new interval
        if hasattr(self, '_playback_timer') and self._playback_timer.isActive():
            interval = int(10 / self._playback_speed)
            self._playback_timer.start(interval)

    def _skip_to_start(self):
        """Skip playback to start (sample 0)."""
        if hasattr(self, 'trace_canvas'):
            self.trace_canvas.playback_pos = 0
            self._timeline.setValue(0)
            self.trace_canvas.update()

    def _skip_to_end(self):
        """Skip playback to end (last sample)."""
        if hasattr(self, 'trace_canvas'):
            total = self._get_total_trace_samples()
            self.trace_canvas.playback_pos = total
            self._timeline.setValue(total)
            self.trace_canvas.update()

    def _on_timeline_changed(self, value):
        """Handle timeline slider drag — update playback position."""
        if hasattr(self, 'trace_canvas'):
            self.trace_canvas.playback_pos = value
            self.trace_canvas.update()
            # Pause playback scrubbing
            if hasattr(self, '_timeline') and self._timeline._dragging:
                if hasattr(self, '_playback_timer') and self._playback_timer.isActive():
                    self._playback_timer.stop()
                    self._playback_controls.set_playing(False)

    def _get_total_trace_samples(self):
        """Calculate total trace length in samples (all 5 phases)."""
        if not hasattr(self, 'trace_canvas'):
            return 0
        return (len(self.trace_canvas.preshot_x) + len(self.trace_canvas.hold_x) +
                len(self.trace_canvas.press_x) + len(self.trace_canvas.recoil_x) +
                len(self.trace_canvas.ft_x))

    def _on_session_selected(self, item):
        """Handle session selection — superseded by rich version in _build_history_tab.
        Kept for compatibility with non-history-tab list widgets."""
        sid = item.data(Qt.UserRole)
        if not sid:
            return
        shots = get_session_shots(sid)
        self._detail_panel.setVisible(True)
        self._shot_detail_list.clear()
        for s in shots:
            score = s.get('score', 0)
            color = self._score_color(score)
            grade = s.get('stability_grade', '') or ''
            err = s.get('error_type', '')
            err_str = f"  {err}" if err and err != 'NONE' else ''
            imp_x = s.get('impact_x_cm', 0) or 0
            imp_y = s.get('impact_y_cm', 0) or 0
            ts = s.get('timestamp', '') or ''
            ts_str = ts[:19] if ts else '?'

            row = QFrame()
            row.setStyleSheet(f"background: {COLORS['bg_tertiary']}; border-radius: 6px; padding: 6px; margin-bottom: 4px;")
            row_layout = QHBoxLayout(row)
            row_layout.setContentsMargins(6, 4, 6, 4)
            row_layout.setSpacing(6)

            shot_lbl = QLabel(f"Shot {s['shot_number']}")
            shot_lbl.setStyleSheet(f"color: {COLORS['accent_good']}; font-size: 10px; font-weight: 700; letter-spacing: 0.5px;")
            row_layout.addWidget(shot_lbl)

            time_lbl = QLabel(ts_str)
            time_lbl.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 10px;")
            row_layout.addWidget(time_lbl)

            row_layout.addStretch()

            score_badge = QLabel(f"{score:.0f}")
            score_badge.setStyleSheet(
                f"background: {color}33; border: 1px solid {color}; "
                f"border-radius: 6px; padding: 4px 10px; "
                f"font-size: 12px; font-weight: 700; color: {color};")
            row_layout.addWidget(score_badge)

            if grade:
                grade_lbl = QLabel(f"[{grade}]")
                grade_lbl.setStyleSheet(f"color: {color}; font-size: 11px; font-weight: 700;")
                row_layout.addWidget(grade_lbl)

            if err_str:
                err_badge = QLabel(err_str.strip())
                err_badge.setStyleSheet(
                    f"background: {COLORS['accent_ok']}33; border: 1px solid {COLORS['accent_ok']}; "
                    f"border-radius: 4px; padding: 2px 6px; "
                    f"font-size: 9px; color: {COLORS['accent_ok']};")
                row_layout.addWidget(err_badge)

            imp_lbl = QLabel(f"({imp_x:+.1f}, {imp_y:+.1f}) cm")
            imp_lbl.setStyleSheet(f"color: {COLORS['text_muted']}; font-size: 10px;")
            row_layout.addWidget(imp_lbl)

            list_item = QListWidgetItem()
            list_item.setData(Qt.UserRole, s)
            self._shot_detail_list.addItem(list_item)
            self._shot_detail_list.setItemWidget(list_item, row)
            list_item.setSizeHint(QSize(0, 48))

    def _on_shot_detail_selected(self, item):
        s = item.data(Qt.UserRole)
        if not s or not s.get('aim_trace'):
            return
        trace = s['aim_trace']
        self.trace_canvas.set_trace(
            preshot_routine=trace.get('preshot_routine') or trace.get('preshot'),
            approach_settle=trace.get('approach_settle'),
            hold=trace.get('hold'),
            press=trace.get('press'),
            break_pt=trace.get('break'),
            ft=trace.get('followthrough'),
            impact_x_cm=s.get('impact_x_cm', 0.0), impact_y_cm=s.get('impact_y_cm', 0.0))
        self.tabs.setCurrentIndex(1)

    def _export_session_data(self):
        """Export shot data to CSV or JSON via file dialog."""
        if not self.shot_history:
            QMessageBox.information(self, "Export", "No shots in current session to export.")
            return

        path, _ = QFileDialog.getSaveFileName(
            self, "Export Session Data",
            os.path.join(SCRIPT_DIR, f"stasys_session_{self.session_id}.csv"),
            "CSV Files (*.csv);;JSON Files (*.json)"
        )
        if not path:
            return

        try:
            if path.endswith('.json'):
                import json
                export_data = []
                for shot in self.shot_history:
                    export_data.append({
                        'shot_number': shot.get('shot_number', 0),
                        'timestamp': shot.get('timestamp', ''),
                        'score': shot.get('score', 0),
                        'stability_score': shot.get('stability_score', 0),
                        'shooting_score': shot.get('shooting_score', 0),
                        'hold_score': shot.get('hold_score', 0),
                        'press_score': shot.get('press_score', 0),
                        'recoil_score': shot.get('recoil_score', 0),
                        'ft_score': shot.get('ft_score', 0),
                        'a2c_angle_deg': shot.get('a2c_angle_deg', 0),
                        'a2c_mag_mrad': shot.get('a2c_mag_mrad', 0),
                        'impact_x_cm': shot.get('impact_x_cm', 0),
                        'impact_y_cm': shot.get('impact_y_cm', 0),
                        'error_type': shot.get('error_type', ''),
                        'grade': shot.get('stability_grade', ''),
                    })
                with open(path, 'w', encoding='utf-8') as f:
                    json.dump(export_data, f, indent=2, default=str)
            else:
                import csv
                with open(path, 'w', newline='', encoding='utf-8') as f:
                    writer = csv.writer(f)
                    writer.writerow([
                        'shot_number', 'timestamp', 'score',
                        'stability_score', 'shooting_score',
                        'hold_score', 'press_score', 'recoil_score', 'ft_score',
                        'a2c_angle_deg', 'a2c_mag_mrad',
                        'impact_x_cm', 'impact_y_cm',
                        'error_type', 'grade'
                    ])
                    for shot in self.shot_history:
                        writer.writerow([
                            shot.get('shot_number', 0),
                            shot.get('timestamp', ''),
                            f"{shot.get('score', 0):.1f}",
                            f"{shot.get('stability_score', 0):.1f}",
                            f"{shot.get('shooting_score', 0):.1f}",
                            f"{shot.get('hold_score', 0):.1f}",
                            f"{shot.get('press_score', 0):.1f}",
                            f"{shot.get('recoil_score', 0):.1f}",
                            f"{shot.get('ft_score', 0):.1f}",
                            f"{shot.get('a2c_angle_deg', 0):.2f}",
                            f"{shot.get('a2c_mag_mrad', 0):.2f}",
                            f"{shot.get('impact_x_cm', 0):+.2f}",
                            f"{shot.get('impact_y_cm', 0):+.2f}",
                            shot.get('error_type', ''),
                            shot.get('stability_grade', ''),
                        ])
            logger.info(f"Exported {len(self.shot_history)} shots to {path}")
            QMessageBox.information(self, "Export Complete",
                                    f"Session data exported to:\n{path}")
        except Exception as e:
            logger.error(f"Export failed: {e}")
            QMessageBox.warning(self, "Export Error", f"Failed to export: {e}")

    def _export_report(self):
        """Export session report as a CSV file with full shot breakdown."""
        if not self.shot_history:
            logger.info("No shots to export.")
            return

        reports_dir = os.path.join(SCRIPT_DIR, 'reports')
        os.makedirs(reports_dir, exist_ok=True)

        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        csv_path = os.path.join(reports_dir, f'stasy_report_{ts}.csv')
        txt_path = os.path.join(reports_dir, f'stasy_report_{ts}.txt')

        try:
            # CSV export
            with open(csv_path, 'w', newline='', encoding='utf-8') as f:
                f.write(
                    "Shot,Timestamp,Stability_score,Stability_grade,"
                    "Shooting_score,Shooting_grade,"
                    "A2C_angle_deg,A2C_mag_mrad,"
                    "Hold_score,Press_score,Recoil_score,FT_score,"
                    "Hold_stability_deg,Recovery_ms,Error_type,Severity,"
                    "Impact_X_cm,Impact_Y_cm,Target_m,Piezo\n"
                )
                for i, shot in enumerate(self.shot_history, 1):
                    f.write(
                        f"{i},"
                        f"{shot.get('timestamp', 'N/A')},"
                        f"{shot.get('stability_score', 0):.1f},"
                        f"{shot.get('stability_grade', '')},"
                        f"{shot.get('shooting_score', 0):.1f},"
                        f"{shot.get('shooting_grade', '')},"
                        f"{shot.get('a2c_angle', 0):.1f},"
                        f"{shot.get('a2c_mag', 0) * 1000:.2f},"
                        f"{shot.get('hold_score', 0):.1f},"
                        f"{shot.get('press_score', 0):.1f},"
                        f"{shot.get('recoil_score', 0):.1f},"
                        f"{shot.get('ft_score', 0):.1f},"
                        f"{math.degrees(shot.get('hold_stability', 0)):.3f},"
                        f"{shot.get('recoil_recovery_ms', 0):.0f},"
                        f"{shot.get('error_type', 'NONE')},"
                        f"{shot.get('error_severity', 'N/A')},"
                        f"{shot.get('impact_x_cm', 0):+.2f},"
                        f"{shot.get('impact_y_cm', 0):+.2f},"
                        f"{shot.get('target_distance', DEFAULT_TARGET_DISTANCE):.1f},"
                        f"{shot.get('piezo', 0)}\n"
                    )

            # Text summary report
            stability_scores = [s.get('stability_score', 0) for s in self.shot_history]
            shooting_scores  = [s.get('shooting_score',  0) for s in self.shot_history]
            a2c_mags = [s.get('a2c_mag', 0) for s in self.shot_history]

            with open(txt_path, 'w', encoding='utf-8') as f:
                f.write(f"STASYS Shot Analysis Report\n")
                f.write(f"{'=' * 40}\n")
                f.write(f"Session: {self.session_id}\n")
                f.write(f"Mode: {self.session_mode}\n")
                f.write(f"Shots: {len(self.shot_history)}\n\n")

                f.write(f"SESSION STATISTICS\n")
                f.write(f"{'-' * 40}\n")
                f.write(f"Avg Stability: {sum(stability_scores)/len(stability_scores):.1f}\n")
                f.write(f"Avg Shooting:  {sum(shooting_scores)/len(shooting_scores):.1f}\n")
                f.write(f"Best Stability: {max(stability_scores):.1f}\n")
                f.write(f"Best Shooting:  {max(shooting_scores):.1f}\n")
                f.write(f"Avg A2C: {sum(a2c_mags)/len(a2c_mags)*1000:.2f} mrad\n\n")

                # Shot group
                group = ShotGroupAnalyzer(self.shot_history).analyze()
                if group:
                    f.write(f"SHOT GROUP ANALYSIS\n")
                    f.write(f"{'-' * 40}\n")
                    f.write(f"Group Center: {group['center_x_cm']:+.2f}, {group['center_y_cm']:+.2f} cm\n")
                    f.write(f"Spread: {group['spread_cm']:.2f} cm ({group['spread_moa']:.2f} MOA)\n")
                    f.write(f"Rating: {group['group_rating']}\n\n")

                f.write(f"ERROR DISTRIBUTION\n")
                f.write(f"{'-' * 40}\n")
                err_counts = {}
                for s in self.shot_history:
                    err = s.get('error_type', 'NONE')
                    if err and err != 'NONE':
                        err_counts[err] = err_counts.get(err, 0) + 1
                for err, count in err_counts.items():
                    f.write(f"  {err}: {count}\n")
                if not err_counts:
                    f.write("  None\n")

                f.write(f"\nPER-SHOT BREAKDOWN\n")
                f.write(f"{'-' * 40}\n")
                for i, shot in enumerate(self.shot_history, 1):
                    coaching = shot.get('coaching', '')
                    f.write(
                        f"Shot {i}: STAB={shot.get('stability_score', 0):.1f}[{shot.get('stability_grade', '')}]  "
                        f"SCATT={shot.get('shooting_score', 0):.1f}[{shot.get('shooting_grade', '')}]  "
                        f"A2C={shot.get('a2c_angle', 0):.1f}deg "
                        f"Impact={shot.get('impact_x_cm', 0):+.1f},"
                        f"{shot.get('impact_y_cm', 0):+.1f}cm "
                        f"Error={shot.get('error_type', 'NONE')} "
                        f"[{shot.get('error_severity', '')}]\n"
                    )
                    if coaching:
                        f.write(f"  -> {coaching}\n")

            logger.info(f"Report exported: {csv_path} and {txt_path}")

        except Exception:
            logger.exception("Failed to export report")

    def reset_session(self):
        end_session(self.session_id)
        self.list_history.clear()
        self.shot_history = []
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.shot_count = 0
        self._shot_impacts = []
        self._session_saved = False   # reset — new session not saved until START RECORD pressed
        # Reset stability score display
        self.lbl_stability_score.setText("--")
        self.lbl_stability_score.setStyleSheet(f"font-size: 42px; font-weight: 200; color: {COLORS['text_muted']};")
        self.lbl_stability_grade.setText("")
        # Reset shooting score display
        self.lbl_shooting_score.setText("--")
        self.lbl_shooting_score.setStyleSheet(f"font-size: 42px; font-weight: 200; color: {COLORS['text_muted']};")
        self.lbl_shooting_grade.setText("")
        self.lbl_group_center.setText("Group: --")
        self.lbl_big_piezo.setText("--")
        self.lbl_big_piezo.setStyleSheet("font-size: 36px; font-weight: 200; color: #666666;")
        self.piezo_bar_inner.setFixedSize(0, 4)
        self.lbl_piezo_minmax.setText("0 / 4095")
        for obj_name in ['lbl_hold_score', 'lbl_press_score', 'lbl_recoil_score', 'lbl_ft_score']:
            w = self.findChild(QLabel, obj_name)
            if w:
                w.setText("--")
                w.setStyleSheet("QLabel { color: #666666; font-size: 18px; font-weight: 600; }")
        self.lbl_shot_count.setText("Shots: 0")
        self.lbl_session_info.setText(f"Session: {self.session_id} | Mode: {self.session_mode}")
        self._update_stats()

    def _update_status_display(self, state):
        cfg = {
            "IDLE":        ("STANDBY", f"background:{COLORS['bg_tertiary']}; color:{COLORS['text_muted']};"),
            "ARMING":      ("STEADY", f"background:#FF9800; color:#000;"),
            "ARMED":       ("READY", f"background:{COLORS['accent_good']}; color:#0D0D0D; border: 2px solid {COLORS['accent_good']};"),
            "POST_GATHER": ("TRIGGERED", f"background:{COLORS['accent_good']}; color:#FFF;"),
            "COOLDOWN":    ("RECORDED", f"background:{COLORS['accent_blue']}; color:#FFF;"),
        }
        if state in cfg:
            text, style = cfg[state]
            self.lbl_status.setText(text)
            self.lbl_status.setStyleSheet(f"""
                QLabel {{
                    font-size: 14px;
                    font-weight: 600;
                    border-radius: 8px;
                    padding: 16px;
                    {style}
                }}
            """)

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Escape:
            self.close()
        super().keyPressEvent(event)

    def closeEvent(self, event):
        if self._session_saved:
            end_session(self.session_id)
        try:
            if hasattr(self.ser, 'close') and callable(self.ser.close):
                self.ser.close()
        except Exception:
            pass  # MockSerial has no close()
        super().closeEvent(event)

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
                        self._on_calibration_complete()
                    else:
                        self.calib_buffer = []
                continue

            shot_res, bat, rot, jerk, piezo = self.detector.process(pkt)

            self.detector.auto_tare()

            self.lbl_telem.setText(
                f"Jerk:  {jerk:.1f}\nPiezo: {piezo}\nRot:   {rot:.2f}\nBat:   {bat}%")

            # FIX BUG 2: Update lbl_big_piezo secara LIVE (bukan hanya saat ada shot_res)
            if hasattr(self, 'lbl_big_piezo'):
                self.lbl_big_piezo.setText(f"{piezo}")
                pc_live = COLORS['accent_good'] if piezo > 1500 else COLORS['accent_ok'] if piezo > 100 else COLORS['accent_bad']
                self.lbl_big_piezo.setStyleSheet(
                    f"font-size: 36px; font-weight: 200; color: {pc_live};")

            # Live piezo bar update (FIX BUG 2: hapus syarat is_calibrated agar bar selalu update)
            if hasattr(self, 'lbl_big_piezo'):
                bar_w = max(4, int((piezo / 4095.0) * max(self.piezo_bar_container.width() - 8, 4)))
                self.piezo_bar_inner.setFixedSize(bar_w, 4)
                pc = COLORS['accent_ok']
                if piezo > 1500: pc = COLORS['accent_good']
                elif piezo < 100: pc = COLORS['accent_bad']
                self.piezo_bar_inner.setStyleSheet(f"QFrame {{ background: {pc}; border-radius: 3px; }}")
                self.lbl_piezo_minmax.setText(f"0 / {piezo}")

            if shot_res:
                self.lbl_telem_a2c.setText(
                    f"A2C: {shot_res.get('a2c_angle', 0):.1f}° "
                    f"({shot_res.get('a2c_mag', 0) * 1000:.2f}mrad)\n"
                    f"Hold: {math.degrees(shot_res.get('hold_stability', 0)):.2f}°\n"
                    f"Err:  {shot_res.get('error_type', 'NONE')}")
            else:
                self.lbl_telem_a2c.setText("A2C: --\nHold: --\nError: --")

            self._update_status_display(self.detector.state)

            # Always log shot detection (regardless of recording state)
            if shot_res:
                logger.info(
                    "SHOT TRIGGERED  Stab:%-5s  Shoot:%-5s  "
                    "A2C:%-7s  Piezo:%d  Err:%s",
                    f"{shot_res.get('stability_score', 0):.1f}",
                    f"{shot_res.get('shooting_score', 0):.1f}",
                    f"{shot_res.get('a2c_mag', 0) * 1000:.2f}mrad",
                    shot_res.get('piezo', 0),
                    shot_res.get('error_type', 'NONE'),
                )

            # ── ALWAYS display shot in Shot Analysis tab (even without recording) ───
            if shot_res:
                stability = shot_res.get('stability_score', 0)
                shooting  = shot_res.get('shooting_score', 0)
                piezo_val = shot_res['piezo']
                stab_grade = shot_res.get('stability_grade', '')
                shoot_grade = shot_res.get('shooting_grade', '')

                # Apply multipliers if recording (for list history display)
                if self._recording:
                    fw = FIREARM_MULTIPLIERS.get(self.current_firearm, 1.0)
                    tm = TRAINING_MODE_MULTIPLIERS.get(self.current_training_mode, 1.0)
                    stability = min(100.0, stability * fw * tm)
                    shooting  = min(100.0, shooting  * fw * tm)

                # Update trace canvas immediately
                self.trace_canvas.set_trace(
                    preshot_routine=shot_res.get('preshot_routine'),
                    approach_settle=shot_res.get('approach_settle'),
                    hold=shot_res['hold'],
                    press=shot_res.get('press'),
                    break_pt=shot_res.get('break'),
                    ft=shot_res.get('followthrough'),
                    impact_x_cm=shot_res.get('impact_x_cm', 0.0),
                    impact_y_cm=shot_res.get('impact_y_cm', 0.0))

                # Add to history list (with recording indicator)
                self.shot_history.append(shot_res)
                time_str = datetime.now().strftime('%H:%M:%S')
                rec_tag = "[REC] " if self._recording else "[LIVE] "
                error = shot_res.get('error_type', '')
                severity = shot_res.get('error_severity', '')
                error_str = f" [{error} {severity}]" if error and error != 'NONE' else ""
                self.list_history.insertItem(
                    0, f"{rec_tag}{time_str}  |  STAB:{stability:.0f}  SCATT:{shooting:.0f}"
                    f"  [{stab_grade}/{shoot_grade}]  Piezo:{piezo_val}{error_str}")

            # ── RECORDING-ONLY: update large score labels, group center, DB, phase scores ─
            if shot_res and self._recording:
                self.shot_count += 1
                self.lbl_shot_count.setText(f"Shots: {self.shot_count}")

                # ── Log full shot analysis result ──────────────────────────────
                logger.info(
                    "SHOT SAVED  #%d  Stab:%-5s  Shoot:%-5s  "
                    "Hold:%-5s  Press:%-5s  Recoil:%-5s  FT:%-5s  "
                    "A2C:%-7s  Piezo:%d  Err:%s %s",
                    self.shot_count,
                    f"{stability:.1f}",
                    f"{shooting:.1f}",
                    f"{shot_res.get('hold_score', 0):.1f}",
                    f"{shot_res.get('press_score', 0):.1f}",
                    f"{shot_res.get('recoil_score', 0):.1f}",
                    f"{shot_res.get('ft_score', 0):.1f}",
                    f"{shot_res.get('a2c_mag', 0) * 1000:.2f}mrad",
                    piezo_val,
                    shot_res.get('error_type', 'NONE'),
                    shot_res.get('error_severity', ''),
                )

                # Apply multipliers for recording
                fw = FIREARM_MULTIPLIERS.get(self.current_firearm, 1.0)
                tm = TRAINING_MODE_MULTIPLIERS.get(self.current_training_mode, 1.0)
                # stability/shooting were already multiplied in the first block when recording,
                # so don't double-apply. Use the raw values from shot_res for log.
                stability_raw = shot_res.get('stability_score', 0)
                shooting_raw  = shot_res.get('shooting_score', 0)

                # ── Stability score (MantisX) ──
                self.lbl_stability_score.setText(f"{int(stability)}")
                c_stab = COLORS['accent_good'] if stability > 90 else COLORS['accent_ok'] if stability > 70 else COLORS['accent_bad']
                self.lbl_stability_score.setStyleSheet(
                    f"font-size: 42px; font-weight: 200; color: {c_stab};")
                self.lbl_stability_grade.setText(stab_grade)
                self.lbl_stability_grade.setStyleSheet(
                    f"font-size: 22px; font-weight: 600; color: {c_stab};")

                # ── Shooting score (SCATT) ──
                self.lbl_shooting_score.setText(f"{int(shooting)}")
                c_shoot = COLORS['accent_good'] if shooting > 90 else COLORS['accent_ok'] if shooting > 70 else COLORS['accent_bad']
                self.lbl_shooting_score.setStyleSheet(
                    f"font-size: 42px; font-weight: 200; color: {c_shoot};")
                self.lbl_shooting_grade.setText(shoot_grade)
                self.lbl_shooting_grade.setStyleSheet(
                    f"font-size: 22px; font-weight: 600; color: {c_shoot};")

                # ── Update running group center ──
                if not hasattr(self, '_shot_impacts'):
                    self._shot_impacts = []
                self._shot_impacts.append((shot_res.get('impact_x_cm', 0.0),
                                           shot_res.get('impact_y_cm', 0.0)))
                n = len(self._shot_impacts)
                target_d = shot_res.get('target_distance', DEFAULT_TARGET_DISTANCE)
                gc_x = sum(ix for ix, iy in self._shot_impacts) / n
                gc_y = sum(iy for ix, iy in self._shot_impacts) / n
                self.detector._group_center_x = math.atan(gc_x / (target_d * 100.0))
                self.detector._group_center_y = math.atan(gc_y / (target_d * 100.0))
                self.lbl_group_center.setText(f"Group: {gc_x:+.1f}, {gc_y:+.1f} cm")

                # Phase scores
                for obj_name, val in [
                    ('lbl_hold_score',   shot_res.get('hold_score', 0)),
                    ('lbl_press_score',  shot_res.get('press_score', 0)),
                    ('lbl_recoil_score', shot_res.get('recoil_score', 0)),
                    ('lbl_ft_score',     shot_res.get('ft_score', 0)),
                ]:
                    w = self.findChild(QLabel, obj_name)
                    if w:
                        w.setText(f"{val:.0f}")
                        sc = COLORS['accent_good'] if val > 85 else COLORS['accent_ok'] if val > 65 else COLORS['accent_bad']
                        w.setStyleSheet(f"QLabel {{ color: {sc}; font-size: 18px; font-weight: 600; }}")

                # Update stats and DB
                self._update_stats()

                aim_trace = {
                    "hold":   {"x": list(shot_res['hold'][0]),   "y": list(shot_res['hold'][1])},
                    "press":  {"x": list(shot_res['press'][0]), "y": list(shot_res['press'][1])},
                    "recoil": {"x": list(shot_res['recoil'][0]),"y": list(shot_res['recoil'][1])},
                    "followthrough": {"x": list(shot_res.get('followthrough', ([], []))[0]),
                                      "y": list(shot_res.get('followthrough', ([], []))[1])},
                }
                log_shot_trace(
                    self.session_id, self.shot_count, stability, piezo_val, aim_trace,
                    self.session_mode,
                    stability_grade=shot_res.get('stability_grade', ''),
                    shooting_score=shooting,
                    shooting_grade=shot_res.get('shooting_grade', ''),
                    a2c_angle=shot_res.get('a2c_angle', 0.0),
                    a2c_mag=shot_res.get('a2c_mag', 0.0),
                    hold_score=shot_res.get('hold_score', 0.0),
                    press_score=shot_res.get('press_score', 0.0),
                    recoil_score=shot_res.get('recoil_score', 0.0),
                    ft_score=shot_res.get('ft_score', 0.0),
                    hold_stability=shot_res.get('hold_stability', 0.0),
                    recoil_recovery_ms=shot_res.get('recoil_recovery_ms', 0.0),
                    error_type=shot_res.get('error_type', 'NONE'),
                    error_severity=shot_res.get('error_severity', ''),
                    coaching=shot_res.get('coaching', ''),
                    impact_x_cm=shot_res.get('impact_x_cm', 0.0),
                    impact_y_cm=shot_res.get('impact_y_cm', 0.0),
                    target_distance=shot_res.get('target_distance', DEFAULT_TARGET_DISTANCE),
                    stability_score=stability,
                    firearm=self.current_firearm,
                    training_mode=self.current_training_mode)

            # Update aim canvas
            recent_x = list(self.detector.trace_x)
            recent_y = list(self.detector.trace_y)
            if recent_x and self.detector.is_calibrated:
                cx = recent_x[-1]
                cy = recent_y[-1]
                self.aim_canvas.update_aim(recent_x, recent_y, cx, cy, True)


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
            win = MainWindow(ser, device_key=BLUETOOTH_COM_PORT)
            win.show()
            sys.exit(app.exec_())
        else:
            logger.error("Hardware Authentication Failed. Switching to simulation.")
            ser.close()
            ser = None

    if ser is None or not ser.is_open:
        logger.info(">> SWITCHING TO SIMULATION MODE <<")
        ser = MockSerial()
        win = MainWindow(ser, device_key="SIM")
        win.setWindowTitle(win.windowTitle() + " [SIMULATION MODE]")
        win.show()
        sys.exit(app.exec_())