# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

STASYS is a battery-powered shooting training sensor system inspired by commercial products like MantisX and SCATT. It streams 9-axis IMU (MPU6050 + QMC5883P magnetometer) + piezo knock sensor data over Bluetooth Classic to a Python receiver application at 100Hz, enabling professional-grade aim analysis and shot coaching.

**Hardware:** ESP32 DEVKITV1 + MPU6050 IMU + QMC5883P magnetometer + piezo knock sensor + Li-Ion battery with TP4056 charger

**Use cases:** Dry fire and live fire training for pistol, rifle, archery, and shotgun (attached on the bottom of the gun)

## Build Commands

### ESP32 Firmware
```bash
pio run              # Build firmware
pio run --target upload   # Build and flash to ESP32
pio run --target monitor  # Build and open serial monitor (115200 baud)
pio run -e esp32dev  # Build specific environment
```

### Python Receiver
```bash
python stasys_app/SL.py  # Run the PyQt5 receiver application
```

### Tests
```bash
python -m pytest test/ -v                    # Run all tests
python -m pytest test/test_issf_target.py -v  # Run a single test file
python -m pytest test/ --ignore=test/test_aim_trail.py  # Skip broken Qt tests
```

**Known test issue:** Tests import from `base` or `stasys_app.base`, but the main application module is `stasys_app/SL.py`. Tests need their import statements updated to use `from SL import ...` or `from stasys_app.SL import ...` respectively. The application itself uses PyQt5 (not PyQt6 as some tests assume).

## Hardware Architecture

| Pin | Role |
|-----|------|
| GPIO 39 (ADC1_CH3) | Battery voltage via 100k/100k divider |
| GPIO 35 (ADC1_CH7) | Piezo knock/vibration sensor |
| GPIO 21 / 22 | I2C SDA / SCL for MPU6050 |
| GPIO 21 / 22 | I2C SDA / SCL for QMC5883P (shared bus) |

**MPU6050 configuration:** 4G accel range, 500dps gyro, DLPF bandwidth 260Hz (register 0x1A = 0x00).

**QMC5883P configuration:** +/-30 Gauss full-scale, ~655 LSB/Gauss sensitivity, continuous measurement mode at 200Hz. Mag readings are raw LSB units - convert to mG by dividing by 0.655.

**Packet format** (`<ffffffhhhHB`): 6 floats (acc/gyro) + 3 shorts (mag) + 1 ushort (piezo) + 1 byte (bat) = 33 bytes payload. Total 36 bytes with 2-byte header + 1-byte checksum.

## Firmware Architecture

Single-file Arduino sketch (`src/main.cpp`). Two FreeRTOS tasks, no external dependencies beyond ESP32 core libraries:

- **sensorTask** (Core 1, priority 1) — Reads MPU6050 raw registers via I2C, QMC5883P magnetometer (once per packet at 100Hz), and piezo ADC 10x per packet (1kHz oversampling). Extracts peak acceleration (for click detection via jerk) and peak piezo value, averages gyro. Sends binary `DataPacket` over Bluetooth at 100Hz. Challenge-response auth via SHA-256 HMAC on first connection.
- **batteryMonitorTask** (Core 0, priority 1) — Polls battery voltage every 2s, publishes percentage to shared `batteryPercentage` variable when delta >= 2%.

## Software Architecture — Python Receiver

Single-file PyQt5 GUI application (`stasys_app/SL.py`, ~4300 lines) with 4-tab interface:

1. **Live Monitor** — Real-time aim canvas with phosphor trail, sensor status, calibration controls
2. **Shot Analysis** — Phase-colored shot trace visualization, per-shot stats, session summary
3. **Session History** — Browser for past sessions with playback
4. **Settings** — Firearm profile, training mode, COM port, detection thresholds

Data persisted in SQLite (`stasys_app/shooter_data.db`). Settings stored in `stasys_app/settings.json`.

### Core Components

**ShotDetector class** (line 1178) — Heart of the application. Handles all sensor processing:
- State machine: IDLE -> ARMING -> ARMED -> POST_GATHER -> COOLDOWN -> IDLE
- Mahony 9-DOF AHRS filter: Fuses gyro + accelerometer + magnetometer into quaternion orientation at 100Hz
- Magnetometer handling: hard-iron bias subtraction during calibration, auto-disable when norm deviates >40% from calibrated reference
- 40-second circular buffer (4000 samples at 100Hz); trigger at index 2000 (center) for complete pre/post-shot analysis
- Dual-mode shot detection: Mode 0 (Dry Fire) uses piezo threshold; Mode 1 (Live Fire) uses jerk-based detection

**Mahony filter** (`_mahony_step` at line 413): Uses fixed world-frame magnetic reference to avoid circular-reference bugs.

**ISSF Target scoring** (`ISSFTargetSpec` at line 213, `calculate_issf_score` at line 254): Decimal scoring for ISSF target types (10m_air_pistol, 20m_pistol, 50m_free_pistol).

### Key Constants
- `DT = 0.01` (10ms, 100Hz)
- `HOLD_DURATION_IDX = 300` (3.0s pre-shot stability window)
- `PRESS_DURATION_IDX = 20` (0.2s trigger-pull window)
- `RECOIL_DURATION_IDX = 100` (1.0s follow-through window)
- `SHOT_PHASE_TOTAL = 420` (total phase samples)

## Communication Protocol Summary

| Property | Value |
|----------|-------|
| Transport | Bluetooth Classic SPP |
| Baud Rate | 115200 |
| Packet Rate | 100Hz |
| Packet Size | 36 bytes |
| Auth | SHA-256 HMAC challenge-response |

## Known Issues

- **Test import paths broken:** Tests reference `base` or `stasys_app.base` but the actual module is `stasys_app.SL`. Tests also use PyQt6 while the application uses PyQt5.
- **Authentication timeout:** `AUTH_TIMEOUT` is 12s to match the firmware's 10s window. First connection must complete within this window.
