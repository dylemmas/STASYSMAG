"""Shared protocol, display, and detector constants."""

import os
import struct
from dataclasses import dataclass

import numpy as np

COLORS = {
    'bg_primary': '#0D0D0D', 'bg_secondary': '#1A1A1A', 'bg_tertiary': '#252525',
    'bg_card': '#1E1E1E', 'bg_elevated': '#2A2A2A', 'text_primary': '#E8E8E8',
    'text_secondary': '#A0A0A0', 'text_muted': '#666666', 'accent_good': '#00D26A',
    'accent_ok': '#FFC107', 'accent_bad': '#FF5252', 'accent_blue': '#2196F3',
    'score_elite': '#FFD700', 'score_expert': '#4CAF50',
    'score_advanced': '#2196F3', 'score_intermediate': '#FF9800',
    'score_beginner': '#F44336', 'border': '#333333', 'border_active': '#00D26A',
    'status_idle': '#555555', 'status_arming': '#FF9800',
    'status_armed': '#00D26A', 'status_cooldown': '#2196F3',
}

BAUD_RATE = 115200
PACKET_SIZE = 36
PACKET_HEADER = b'\xAA\xBB'
PACKET_FORMAT = '<ffffffhhhHB'
PACKET_PAYLOAD_SIZE = struct.calcsize(PACKET_FORMAT)
DT = 0.01
DEFAULT_TARGET_DISTANCE = 10.0
DEFAULT_MUZZLE_VELOCITY = 200.0
DEFAULT_TRIGGER_PULL_TIME = 0.050
DEFAULT_PIEZO_MIN = 100
DEFAULT_ACCEL_THRESH = 8.0
DEFAULT_SHOT_ROTATION_LIMIT = 4.0
PIEZO_MAX_LIMIT = 4000.0
CALIBRATION_SAMPLE_COUNT = 100
MAG_GAIN_LSB_PER_GA = 655.0
MAHONY_KP_ACC = 1.0
MAHONY_KP_MAG = 1.0
MAHONY_KI = 0.0
MAG_NORM_TOLERANCE = 0.40
LIVE_FIRE_JERK_MULT = 1.5
COOLDOWN_DURATION = 0.5
MAX_PACKETS_PER_TICK = 10
TELEMETRY_BUF_SAMPLES = 500
LIVE_TRACE_LENGTH = 50
MONITOR_TRACE_LENGTH = 100
PLOT_RANGE = 0.20
RING_RADII = (0.02, 0.04, 0.06, 0.08, 0.10)
HOLD_DURATION_IDX = 300
PRESS_DURATION_IDX = 20
RECOIL_DURATION_IDX = 100
SHOT_PHASE_TOTAL = HOLD_DURATION_IDX + PRESS_DURATION_IDX + RECOIL_DURATION_IDX
AUTH_TIMEOUT = 12.0
AUTH_RESPONSE_TIMEOUT = 3.0
AUTH_CHALLENGE_LENGTH = 16
SECRET_KEY = os.environ.get('STASYS_SECRET_KEY', '12ebaf10h12fa9123z21sti').encode()

FEINWERKBAU_PROFILES = {
    'FWB_P700': {'id': 'FWB_P700', 'name': 'Feinwerkbau P700 Air Pistol', 'type': 'pistol', 'target_type': '10m_air_pistol', 'target_distance': 10.0, 'muzzle_velocity': 175.0, 'trigger_pull_time_ms': 45.0, 'max_energy_j': 7.5},
    'FWB_P800': {'id': 'FWB_P800', 'name': 'Feinwerkbau P800 Air Pistol', 'type': 'pistol', 'target_type': '10m_air_pistol', 'target_distance': 10.0, 'muzzle_velocity': 190.0, 'trigger_pull_time_ms': 50.0, 'max_energy_j': 7.5},
    'FWB_700_RIFLE': {'id': 'FWB_700_RIFLE', 'name': 'Feinwerkbau 700 Air Rifle', 'type': 'rifle', 'target_type': '10m_air_rifle', 'target_distance': 10.0, 'muzzle_velocity': 170.0, 'trigger_pull_time_ms': 35.0, 'max_energy_j': 7.5},
}

@dataclass
class ISSFTargetSpec:
    name: str
    distance_m: float
    total_diameter_mm: float
    ten_ring_diameter_mm: float
    inner_ten_mm: float
    ring_count: int = 10
    svg_filename: str = ''

TARGET_SPECS = {
    '10m_air_pistol': ISSFTargetSpec('10m Air Pistol', 10.0, 170.0, 11.5, 5.75, svg_filename='10m ISSF.svg'),
    '10m_air_rifle': ISSFTargetSpec('10m Air Rifle', 10.0, 45.5, 5.5, 0.5, svg_filename='10m ISSF.svg'),
    '20m_pistol': ISSFTargetSpec('20m Pistol', 20.0, 500.0, 50.0, 25.0, svg_filename='20m ISSF.svg'),
    '50m_free_pistol': ISSFTargetSpec('50m Free Pistol', 50.0, 500.0, 50.0, 25.0, svg_filename='50m ISSF.svg'),
}
