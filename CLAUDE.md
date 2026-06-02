# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

STASYS is a battery-powered shooting training sensor system inspired by commercial products like MantisX and SCATT. It streams 6-axis IMU (MPU6050) + piezo knock sensor data over Bluetooth Classic to a Python receiver application at 100Hz, enabling professional-grade aim analysis and shot coaching.

The system has two main components:
- **ESP32 Firmware** (`src/main.cpp`) — Sensor data acquisition and Bluetooth streaming
- **Python Receiver** (`stasys_app/main.py`) — PyQt5 desktop application with real-time aim visualization, 6-phase shot analysis, dual scoring (Stability + Shooting), session history, and SQLite persistence

**Hardware:** ESP32 DEVKITV1 + MPU6050 IMU + piezo knock sensor + Li-Ion battery with TP4056 charger

**Use cases:** Dry fire and live fire training for pistol, rifle, archery, and shotgun (attached on the bottom of the gun)

## Build Commands

### ESP32 Firmware
```bash
pio run              # Build firmware
pio run --target upload  # Build and flash to ESP32
pio run --target monitor # Build and open serial monitor (115200 baud)
pio run -e esp32dev  # Build specific environment
```

### Python Receiver
```bash
python stasys_app/main.py  # Run the PyQt5 receiver application
```

## Hardware Architecture

| Pin | Role |
|-----|------|
| GPIO 39 (ADC1_CH3) | Battery voltage via 100kΩ/100kΩ divider |
| GPIO 35 (ADC1_CH7) | Piezo knock/vibration sensor |
| GPIO 21 / 22 | I2C SDA / SCL for MPU6050 |

**MPU6050 configuration:** 4G accel range, 500dps gyro, DLPF bandwidth 260Hz (register 0x1A = 0x00 — hardware smoothing disabled; smoothing is done in software).

**Piezo:** Parallel 1MΩ bleed resistor. Firmware reads ADC inside the 1kHz oversampling loop to catch transient spikes.

**Battery:** TP4056 charger module. Voltage divider (100k/100k) scales battery voltage by 0.5 for ESP32 ADC. Multiply ADC reading by 2 to get true voltage.

## Firmware Architecture

Single-file Arduino sketch (`src/main.cpp`). Two FreeRTOS tasks, no external dependencies beyond ESP32 core libraries:

- **sensorTask** (Core 1, priority 1) — Reads MPU6050 raw registers via I2C and piezo ADC 10× per packet (1kHz oversampling), extracts peak acceleration (for click detection via jerk) and peak piezo value, averages gyro. Sends binary `DataPacket` over Bluetooth at 100Hz (every 10ms). Challenge-response auth via SHA-256 HMAC on first connection.
- **batteryMonitorTask** (Core 0, priority 1) — Polls battery voltage every 2s, publishes percentage to shared `batteryPercentage` variable when delta ≥ 2%.

**DataPacket layout** (30 bytes, packed): header[2] (0xAA, 0xBB) → ax/float → ay/float → az/float → gx/float → gy/float → gz/float → piezo/uint16 → battery/uint8 → checksum/uint8.

**Authentication flow:** ESP32 awaits a challenge string over Bluetooth, appends `SECRET_KEY`, computes SHA-256, sends hex digest back. Pins device name to `STASYS-<chipid>`.

## Software Architecture — Python Receiver

### Overview

Single-file PyQt5 GUI application (`stasys_app/main.py`, ~5000 lines) with 4-tab interface:

1. **Live Monitor** — Real-time aim canvas with phosphor trail, sensor status, calibration controls
2. **Shot Analysis** — Phase-colored shot trace visualization, per-shot stats, session summary
3. **Session History** — Browser for past sessions with playback
4. **Settings** — Firearm profile, training mode, COM port, detection thresholds

Data persisted in SQLite (`stasys_app/shooter_data.db`). Settings stored in `stasys_app/settings.json`.

### Core Components

**ShotDetector class** — Heart of the application. Handles all sensor processing:
- **State machine:** IDLE → ARMING → ARMED → POST_GATHER → COOLDOWN → IDLE
- **Quaternion math:** Orientation tracking using gyroscope integration with accelerometer correction
- **40-second circular buffer:** 4000 samples at 100Hz; trigger always at index 2000 (center) for complete pre/post-shot analysis
- **Dual-mode shot detection:**
  - Mode 0 (Dry Fire): Piezo threshold with sustained-contact filtering (5 consecutive samples)
  - Mode 1 (Live Fire): Jerk-based detection with 1.5× multiplier

**6-Phase Shot Analysis:**
| Phase | Window | Samples | Description |
|-------|--------|---------|-------------|
| Pre-Shot Routine | T-20s to T-12s | 800 | NPA setup, breathing pattern |
| Approach | T-12s to T-4s | 800 | Settling to aim center |
| Hold | T-4s to T-1s | 300 | Respiratory pause stability |
| Press | T-1s to T-0 | 100 | Trigger squeeze mechanics |
| Break | T-0 | 1 | Sear release moment |
| Follow-Through | T-0 to T+3s | 300 | Recoil recovery |

**Dual Scoring System:**
- **Stability Score (0–100):** MantisX-style, weighted by phase importance
  - Pre-Shot: 10%, Approach: 20%, Hold: 25%, Press: 30%, Follow-Through: 15%
- **Shooting Score (0–100):** SCATT-style, measures group deviation from hold center

**Error Classification:** Detects and reports:
- ANTICIPATION — pushing during press phase
- FLINCH — jerk spike before shot (piezo before movement)
- HEEL_PRESS — low hand pressure causing muzzle flip
- THUMB_PUSH — thumb overpressure causing muzzle rise
- FOLLOWTHROUGH — poor recoil recovery
- BREATH — sinusoidal drift from breathing
- GUNNY — diagonal push pattern

**Auto-Tare:** Automatically re-zeros aim orientation when stationary gyro noise is detected and drift exceeds ~3° (0.05 rad).

### Data Protocol

**Packet format** (30 bytes total):
```
[0-1]     Header: 0xAA 0xBB
[2-5]     ax (float, m/s²)
[6-9]     ay (float, m/s²)
[10-13]   az (float, m/s²)
[14-17]   gx (float, rad/s)
[18-21]   gy (float, rad/s)
[22-25]   gz (float, rad/s)
[26-27]   piezo (uint16)
[28]      battery (uint8, %)
[29]      checksum (XOR of bytes 2-28)
```

**Authentication flow:**
1. ESP32 broadcasts "READY" every 500ms after boot
2. Python flushes buffer, waits 1.5s for first READY
3. Python sends 16-char random challenge string
4. ESP32 computes SHA-256(challenge + SECRET_KEY) and responds with hex digest
5. Python validates with HMAC comparison
6. Connection established at 115200 baud; up to 10 retry attempts with 2s delays

**Gyro axis mapping** (accounts for physical mounting on firearm):
- gyro[2] → wx (sign: -1.0)
- gyro[1] → wy (sign: +1.0)
- gyro[0] → wz (sign: +1.0)

### Database Schema

```sql
sessions (id, start_time, end_time, mode, shot_count, notes)
shot_traces (id, session_id, shot_number, stability_score, shooting_score,
             phase_scores_json, aim_trace_json, error_type, impact_x, impact_y, timestamp)
device_calibrations (id, com_port, gyro_bias_x/y/z, accel_bias_x/y/z,
                     quaternion_w/x/y/z, last_updated)
```

### Key Features

- **Real-time aim canvas** with phosphor trail and smooth animations (lerp camera following)
- **Phase-colored shot trace** with scroll-to-zoom and playback animation
- **Playback controls** — play/pause, step forward/back, speed selector (0.5×, 1×, 2×)
- **Bullet impact prediction** — A2C (Aim to Center) vector at configurable target distance (default 10m)
- **Firearm profiles** with score multipliers: Pistol (1.0×), Rifle (0.7×), Archery (1.3×), Shotgun (0.9×)
- **Training mode multipliers:** Dry Fire (1.0×), Live Fire (0.8×)

### Dependencies

```
PyQt5          # GUI framework
pyqtgraph      # Visualization components
pyserial       # Bluetooth/COM port communication
numpy          # Array operations and statistics
sqlite3        # Session persistence
```

## Communication Protocol Summary

| Property | Value |
|----------|-------|
| Transport | Bluetooth Classic SPP (Serial Port Profile) |
| Baud Rate | 115200 |
| Packet Rate | 100Hz (10ms intervals) |
| Packet Size | 30 bytes |
| Auth | SHA-256 HMAC challenge-response |

## Key Implementation Notes

- **Firmware I2C burst-read** starts at register 0x3B to grab all 14 bytes (accel + temp + gyro) in one transaction.
- **Accel raw → m/s²:** divide by 8192 LSB/G, multiply by 9.81.
- **Gyro raw → rad/s:** divide by 65.5 LSB/(°/s), multiply by 0.0174533.
- **Oversampling loop:** `delayMicroseconds(400)` compensates for I2C (~0.4ms) + ADC (~0.1ms) latency to approximate 1ms intervals.
- **`loop()`** only contains `vTaskDelay` — all firmware logic runs in FreeRTOS tasks.
- **`analogSetAttenuation(ADC_11db)`** enables full 0–3.3V ADC range for battery and piezo reads.
- **Python `ShotDetector.calibrate()`** captures 100 samples for gyro/accelerometer bias estimation.
- **Python `ShotDetector.tare()`** zeros current orientation as screen center.
- **Python circular buffer trigger** is fixed at center index 2000 to ensure full pre-shot capture.