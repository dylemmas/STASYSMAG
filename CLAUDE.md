# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Project Overview

STASYS is a battery-powered shooting-training sensor system. An ESP32 DEVKITV1 reads a 6-axis MPU6050 IMU, a QMC5883P magnetometer, a piezo vibration sensor, and battery voltage, then streams sensor packets over Bluetooth Classic SPP. The receiver performs orientation estimation, shot detection, ISSF scoring, live visualization, and session analysis.

**Hardware:** ESP32 DEVKITV1, MPU6050, QMC5883P, piezo knock sensor, Li-Ion battery with TP4056 charger

**Use cases:** Dry-fire and live-fire training for pistol, rifle, archery, and shotgun

## Repository Layout

- `firmware/src/main.cpp` — native ESP-IDF firmware entry point and FreeRTOS tasks
- `firmware/components/sensors/` — MPU6050, QMC5883P, piezo, and battery HAL
- `firmware/components/app_protocol/` — packet serialization and authentication digest
- `firmware/components/system_config/` — shared GPIO, sensor, and packet constants
- `firmware/legacy/` — historical Arduino sketches and legacy firmware image
- `python_app/stasys_app/` — modular PyQt5 receiver application
- `python_app/stasys_app/SL.py` — executable entry point and compatibility façade
- `python_app/stasys_app/core.py` — current implementation façade containing the larger legacy-compatible application surface
- `python_app/test/` — Python protocol, filter, detector, scoring, replay, and module-boundary tests
- `android_app/` — Flutter Android companion application
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — design and implementation records
- `firmware/platformio.ini`, `firmware/CMakeLists.txt` — PlatformIO/ESP-IDF build configuration

The supported receiver in this checkout is the Python application. The Flutter Android app is maintained separately under `android_app/`.

## Build Commands

### ESP32 Firmware

```bash
cd firmware
pio run                              # Build the esp32dev environment
pio run --target upload              # Build and flash the board
pio run --target monitor             # Open the 115200-baud serial monitor
pio run -e esp32dev                  # Explicit environment selection
```

The firmware uses `espressif32@6.12.0`, the ESP-IDF framework, a 240 MHz CPU, and release build settings. Native ESP-IDF builds can also use `firmware/CMakeLists.txt` when `IDF_PATH` is configured.

### Python Receiver

```bash
python python_app/stasys_app/SL.py
```

The receiver opens a connection dialog, supports simulation mode, and then launches the main window. It persists session data in `python_app/stasys_app/shooter_data.db` and settings in `python_app/stasys_app/settings.json`.

### Python Tests

```bash
python -m pytest python_app/test/ -v
python -m pytest python_app/test/test_issf_target.py -v
python -m pytest python_app/test/ --ignore=python_app/test/test_aim_trail.py
```

### Android App

```bash
cd android_app
flutter pub get
flutter test
```

Tests are written for pytest. In environments without pytest installed, test collection cannot run; install the project test dependencies before treating that as a code failure. Some historical tests may still contain legacy import assumptions, so verify imports against the current `python_app/stasys_app` module layout.

## Hardware Architecture

| Pin | Role |
|-----|------|
| GPIO 39 (ADC1_CH3) | Battery voltage through a 100k/100k divider |
| GPIO 35 (ADC1_CH7) | Piezo knock/vibration sensor |
| GPIO 21 / 22 | Shared I2C SDA / SCL for MPU6050 and QMC5883P |

Firmware sensor constants are defined in `firmware/components/system_config/system_config.h`:

- MPU6050 address `0x68`; QMC5883P address `0x2C`
- 10 sensor oversampling iterations per packet
- 100 Hz packet period (`10,000` microseconds)
- MPU6050 scale: ±4 g accelerometer and ±500 dps gyroscope
- Battery range: 3.0–4.2 V with a 2:1 divider

The QMC5883P is optional at runtime. Firmware records `qmc_present` during initialization and sends zero/raw-last magnetometer values when the device is unavailable.

## Firmware Architecture

The firmware is native ESP-IDF C/C++ rather than the previous monolithic Arduino sketch. `app_main()` initializes NVS, the sensor HAL, Bluetooth Classic SPP, and two pinned FreeRTOS tasks:

- **`sensor_task` (Core 1):** waits for authentication, samples MPU6050 and piezo data, tracks peak acceleration/jerk and averaged gyro values, reads the magnetometer, serializes a packet, and sends it at 100 Hz while the SPP link is not congested.
- **`battery_task` (Core 0):** averages 16 ADC readings every 2 seconds and publishes the calculated battery percentage.

Bluetooth advertises a device name in the `STASYS-XXXX` form and exposes an SPP service named `STASYS`. Connection and authentication state are guarded with FreeRTOS event bits; sensor packet writes are protected by the SPP spinlock.

## Communication Protocol

The packet constants and serialization contract live in `firmware/components/app_protocol/include/app_protocol.h` and `firmware/components/app_protocol/app_protocol.cpp`.

| Property | Value |
|----------|-------|
| Transport | Bluetooth Classic SPP |
| Packet rate | 100 Hz |
| Serialized packet size | 36 bytes |
| Header | `0xAA 0xBB` |
| Payload | 6 little-endian float32 values, 3 little-endian int16 magnetometer values, uint16 piezo, uint8 battery |
| Checksum | XOR of serialized bytes 2 through 34 |
| Authentication | SHA-256 of challenge bytes followed by the device secret; lowercase 64-character hex response |

The payload is 33 bytes; the remaining 3 bytes are the 2-byte header and 1-byte checksum. Keep the firmware serializer and Python parser tests synchronized when changing this contract.

## Python Receiver Architecture

The receiver is PyQt5-based and currently exposes four main workflows:

1. **Live Monitor** — real-time aim canvas, phosphor trail, sensor status, and calibration controls
2. **Shot Analysis** — phase-colored trajectory, per-shot metrics, and session summary
3. **Session History** — persisted session browsing and replay
4. **Settings** — firearm profile, training mode, serial device, and detection thresholds

### Core Components

- **`ShotDetector`** — state machine `IDLE -> ARMING -> ARMED -> POST_GATHER -> COOLDOWN -> IDLE`; combines piezo/jerk detection with the AHRS pipeline and maintains the circular sample buffer.
- **Mahony filter** — fuses gyro, accelerometer, and optional magnetometer data at 100 Hz. Magnetometer calibration subtracts hard-iron bias and disables magnetic correction when the field norm deviates by more than 40% from the calibrated reference.
- **ISSF scoring** — `ISSFTargetSpec` and `calculate_issf_score` support the configured pistol and rifle target profiles, including `10m_air_pistol`, `10m_air_rifle`, `20m_pistol`, and `50m_free_pistol`.
- **Database/settings helpers** — SQLite session storage and JSON settings persistence.
- **Canvas/widgets/pages** — PyQt5 visualization and page composition extracted from the original receiver UI.

Important processing constants remain in the Python application and tests:

- `DT = 0.01` (100 Hz)
- `HOLD_DURATION_IDX = 300` (3.0 seconds)
- `PRESS_DURATION_IDX = 20` (0.2 seconds)
- `RECOIL_DURATION_IDX = 100` (1.0 second)
- `SHOT_PHASE_TOTAL = 420` samples

## Development Guidelines

- Keep the firmware packet format compatible with the Python receiver and native protocol tests.
- Put hardware access in `firmware/components/sensors`; keep protocol encoding in `firmware/components/app_protocol`.
- Preserve `python_app/stasys_app/SL.py` as the supported command-line entry point and compatibility façade.
- Follow the repository Python rules: PEP 8, type annotations for new function signatures, black, isort, and ruff where available.
- Add or update pytest coverage for changes to scoring, filtering, packet parsing, detection, persistence, or module boundaries.
- Do not commit generated build output, Python bytecode, local databases, or device credentials.

## Known Issues and Constraints

- Pytest may not be installed in the development environment; a missing test runner is an environment issue, not a failing assertion.
- Some legacy tests/import paths may need migration to `stasys_app.SL` or the extracted modules.
- The receiver currently has a 12-second authentication timeout; keep it aligned with the handshake behavior when changing authentication or connection setup.
- The protocol currently uses a shared firmware secret and a plain SHA-256 construction; treat changes to authentication as security-sensitive and update both sides together.
