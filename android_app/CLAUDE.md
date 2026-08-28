# STASYS Flutter App - Development Guide

> **Note**: This is the Flutter-specific companion to the root `CLAUDE.md`.
> For firmware architecture, communication protocol details, and firmware build
> instructions, see the parent `CLAUDE.md` at the project root.

## Project Purpose

Mobile companion app for the STASYS shooter stability analyzer. Primary platform for live training sessions.

---

## Architecture

```
android_app/
├── lib/
│   ├── main.dart                    # App entry, MultiProvider + GoRouter
│   ├── router/app_router.dart       # GoRouter configuration (ShellRoute)
│   ├── theme/app_theme.dart         # Dark STSYS theme (#FFB693 primary, #131313 bg, Manrope/Inter fonts)
│   ├── services/
│   │   ├── database_helper.dart     # SQLite singleton, schema creation, migrations
│   │   ├── database_service.dart    # CRUD operations, binary BLOB encoding
│   │   ├── export_service.dart      # CSV export via Share Sheet
│   │   ├── firmware_service.dart    # OTA firmware loading + chunking + SHA256
│   │   └── trajectory/
│   │       ├── replay_engine.dart   # Offline replay: SessionLog → ReplayTrace
│   │       ├── replay_models.dart   # ReplayFrame, ReplayShot, ReplayTrace
│   │       ├── quaternion.dart      # Quaternion ops (extracted from isolate)
│   │       └── barrel_projection.dart # Right-handed barrel projection + tests
│   ├── providers/
│   │   ├── bluetooth_provider.dart  # Text auth (READY→challenge→SHA256 hex) + dual-mode parser
│   │   │                              # Binary: 0xAA 0xBB + 6 floats + piezo + battery + CRC16
│   │   │                              # 3-state parser: waitingForReady → waitingForHash → streaming
│   │   │                              # + OTA command methods: sendOtaStart, sendOtaChunk, sendOtaFinish,
│   │   │                              #   sendRebootCommand, getFirmwareVersion
│   │   ├── sensor_data_provider.dart  # UI state, isolate communication, demo mode
│   │   ├── sensor_data_isolate.dart    # Shot detection + 3-phase analysis (hold/press/recoil)
│   │   │                              # + auto-calibration on first 50 samples (gyro zero-offset)
│   │   ├── settings_provider.dart      # Firearm type, training mode, demo mode, target distance (5–25m)
│   │   │                              # + autoUpdateFirmware (bool, default false)
│   │   ├── session_provider.dart       # Session list management
│   │   ├── session_logger.dart         # Delegates to DatabaseService (SQLite)
│   │   └── ota_provider.dart           # OTA state machine: idle→loading→sending→verifying→rebooting→completed/failed
│   ├── screens/
│   │   ├── splash_screen.dart        # STSYS branding, 2s auto-navigate
│   │   ├── connection_screen.dart     # BT scan/connect + Explore App demo mode + firmware version check
│   │   ├── main_shell.dart           # Bottom 3-tab navigation shell
│   │   ├── tracking_screen.dart      # Mode selection (4 firearm cards)
│   │   ├── tracking_mode_view.dart   # Live graph with mode change dialog
│   │   ├── history_screen.dart       # Session list + export CSV + clear all + refresh
│   │   ├── settings_screen.dart      # BT scan overlay + settings + target distance slider
│   │   ├── session_detail_screen.dart # POST SHOT + ANALYSIS toggle + shot chips
│   │   ├── replay_screen.dart        # Full-screen replay (legacy, logic moved to AnalysisTab)
│   │   ├── ota_update_screen.dart    # Full-screen OTA progress UI (route /ota-update)
│   │   └── ota_prompt_dialog.dart    # Modal dialog: version compare + Skip/Update buttons
│   ├── screens/tabs/
│   │   ├── graph_tab.dart            # TRACE (muzzle trace) + POST SHOT (3-phase analysis)
│   │   ├── home_tab.dart             # Dashboard (STSYSStyle)
│   │   ├── connection_tab.dart        # Bluetooth device selection
│   │   ├── settings_tab.dart         # Firearm type, training mode
│   │   └── shot_timer_tab.dart       # Shot timer with countdown & splits
│   ├── widgets/
│   │   ├── muzzle_trace_widget.dart  # MantisX-style live trace
│   │   ├── shot_analysis_panel.dart  # 3-phase post-shot chart with ring overlay
│   │   ├── shot_history_list.dart    # Session shot list with tappable cards
│   │   ├── gyro_realtime_chart.dart  # Real-time gyro chart
│   │   ├── interactive_chart.dart
│   │   ├── control_panel.dart
│   │   ├── status_bar.dart
│   │   ├── benchmark_analysis_widget.dart
│   │   ├── debug_overlay.dart
│   │   └── analysis/                  # New: offline trajectory replay widgets
│   │       ├── analysis_tab.dart     # Composite: BarrelTraceCanvas + Scrubber + PhaseSummary + FactorBreakdown
│   │       ├── trajectory_canvas.dart    # Barrel trace + target overlay + shot markers
│   │       ├── trajectory_scrubber.dart  # Timeline scrubber + shot chip selector
│   │       ├── phase_summary_card.dart   # Per-shot 3-phase chart
│   │       └── factor_breakdown_card.dart # Stability/smoothness/harmonics factor scores
│   └── models/
│       └── data_models.dart          # DataPoint, SessionLog, ShotResult
│                                        FirearmType, TrainingMode, MountDirection, MountPosition
```

---

## Navigation Flow (GoRouter)

```
App Launch
  └── SplashScreen (STSYS branding, 2s auto-navigate)
        └── ConnectionScreen
              ├── Scan Bluetooth → connect → [firmware check] → /tracking or /ota-update
              └── Explore App → demo mode → /tracking

MainShell (3-tab bottom nav):
  ├── /tracking → TrackingScreen
  │     ├── ModeSelectionView (4 firearm cards)
  │     └── TrackingModeView (live graph + mode change dialog)
  ├── /history → HistoryScreen
  │     └── Session list + swipe delete + clear all + refresh
  └── /settings → SettingsScreen
        └── BT scan overlay + firearm type + training mode
```

---

## Demo Mode

Implemented in `sensor_data_provider.dart`:

- `setDemoMode(bool)` — enable/disable demo mode
- `_startDemoTimer()` — Timer.periodic(33ms) generates random gyro/accel data
- `_triggerDemoShot()` — auto-generates shot every 4-8s with score 60-95
- `isDemoMode` getter in `SettingsProvider`

**BT scan in demo mode**: Redirects to `/connection` screen.
**Connect in demo mode**: Auto-disables demo mode, switches to real sensor data.

**Trace data** (2026-04-26): Demo mode integrates gyro → trace coordinates stored in `_demoTracePoints`. Provider assigns `_traceXData`/`_traceYData`/`_liveTraceX`/`_liveTraceY` from these points every tick so the muzzle trace widget renders correctly. Cleared on demo mode stop.

---

## Communication Protocol (STASYS_FW)

> **Updated** (2026-05-05): Flutter app now uses STASYS_FW protocol from `dylemmas/STASYSFW`.
> Source: https://github.com/dylemmas/STASYSFW

### Binary Packet Format (31 bytes)

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | Sync0 | `0xAA` |
| 1 | 1 | Sync1 | `0xBB` |
| 2 | 4 | ax | float m/s² |
| 6 | 4 | ay | float m/s² |
| 10 | 4 | az | float m/s² |
| 14 | 4 | gx | float rad/s |
| 18 | 4 | gy | float rad/s |
| 22 | 4 | gz | float rad/s |
| 26 | 2 | piezo | uint16 ADC peak |
| 28 | 1 | battery | uint8 % |
| 29 | 2 | crc16 | CRC-16 CCITT over bytes 2-28 |

**Checksum**: CRC-16 CCITT (was XOR in older firmware)
- Initial: `0xFFFF`
- Polynomial: `0x1021`
- Coverage: bytes 2-28 (27 bytes)

### Authentication Protocol (unchanged)

```
Flutter → ESP32: "AUTH_CHALLENGE\n"
ESP32 → Flutter: SHA256("AUTH_CHALLENGE" + SECRET_KEY) hex (64 chars)
Flutter → ESP32: verifies hash
```

**Secret Key**: `12ebaf10h12fa9123z21sti`

### Firmware Features (STASYS_FW)

- **AHRS**: Madgwick filter for orientation
- **ZUPT**: Zero Velocity Update for runtime gyro bias correction
- **Factory Calibration**: 500 samples on first boot, offsets saved to NVS
- **Battery Monitoring**: 100Hz normal, 20Hz low battery, deep sleep at <5%
- **Session Timeout**: 5 minutes inactivity auto-disconnect

---

## Scoring System

> **See parent `CLAUDE.md`: Key Algorithms > MantisX-Style Scoring**

Flutter app uses **MantisX-style soft curve** scoring (sqrt-based penalties).

---

## Shot Detection State Machine

> Flutter implementation: `providers/sensor_data_isolate.dart` → `ShotDetector` class.

### Thresholds
- **Stability Window**: 200ms
- **Gyro Limit**: 4.0 rad/s (ARMING state)
- **Trigger**: Piezo > 100 (dry fire) or jerk > 12.0 (live fire)
- **Cooldown**: 500ms

> Shot detection runs in **Flutter isolate**, NOT in firmware.
> Full 3-phase analysis (hold/press/recoil) is computed in isolate.

---

## Calibration

Located in `providers/sensor_data_isolate.dart`.

**Auto-calibration on startup**: First 50 samples collected while sensor is stationary → compute gyro zero-offset (X/Y/Z). No manual calibration button needed. `_autoCalibrating` flag auto-triggers on first data, sends `calibration_complete` when done.

Legacy manual calibration: `CalibrationManager` class sends `calibration_progress` every 10 samples, `calibration_complete` with offsets when done. Requires `btProvider.isAuthenticated == true` before enabling. Calibration offsets subtracted from raw gyro data in isolate processing.

---

## Live Tracking (MantisX-Style)

### Architecture
- **Isolate** (`sensor_data_isolate.dart`): Gyro integration → quaternion → atan2 projection → trace coordinates
- **Widget** (`muzzle_trace_widget.dart`): 60fps ticker, dot lerp, camera follow, auto-zoom, trace painting

### Quaternion Projection (from stasysz.py)
1. Bias-correct raw gyro (`gx - offsetGx`)
2. Remap MPU6050 axes: `kGyroAxisX=2, kGyroAxisY=1, kGyroAxisZ=0`
3. Integrate quaternion: `_quatIntegrate(q, wx, wy, wz, dt)`
4. Compute relative quaternion: `qRel = normalize(qTare_conj * q)`
5. Project barrel vector `[0,0,1]` through `qRel` → screen coords via `atan2(-v[1], v[2])`, `atan2(v[0], v[2])`

### Auto-Tare (ShotDetector.autoTare)
Triggers when: hardware stationary for ~0.5s (gyro magnitude < 1.0 rad/s) AND trace drift > 0.02 rad (~1.1°)
- Resets `_qTare = _q.copy()` and clears trace buffer
- `stationaryThreshold = 1.0 rad/s`, `driftThreshold = 0.02 rad`, `autoTareInterval = 3.0s`
- **Critical**: `process()` receives **raw** gyro (not pre-corrected) — bias correction happens exactly once inside `process()` to avoid double-subtraction drift bug

### Camera Follow + Auto-Zoom
- Camera lerp: `_cameraLerp = 0.03` (~500ms delay)
- Auto-zoom: tracks max trace extent relative to camera center, zooms between `_minZoom=0.015` and `_maxZoom=0.12` with lerp `_autoZoomLerp=0.02`
- Dot lerp: `t = deltaMs/16.0` toward target position (smooth 60fps movement)

### Bug Fixed (2026-04-26)
Isolate was calling `fixedGx = gx - _offsetGyroX` then passing `fixedGx` to `process()`. Inside `process()`, it would `gxBc = gx - offsetGx` (where `offsetGx == _offsetGyroX`) → effectively `gx - 2*offsetGx`. This systematic double subtraction caused trace drift. Fixed by passing raw `gx/gy/gz` to `process()`.

---

## Session & Shot Data

### SessionLog (session_logger.dart → DatabaseService/SQLite)
Per-session data stored in SQLite with binary BLOB encoding.
`session_provider.dart` manages session list with `loadSessions()`, `deleteSession()`.

### ShotResult (data_models.dart)
Per-shot scoring:
- `totalScore`, `holdScore`, `pressScore`, `recoilScore`
- `elevationScore`, `windageScore`
- `travelDistance`, `peakJerk`
- `firearmType`, `trainingMode`, `timestamp`
- `holdX/Y`, `pressX/Y`, `recoilX/Y` trace lists for 3-phase analysis plotting

### Session Detail Screen
- POST SHOT 3-phase chart (H/P/R + ELEV/WIND)
- Horizontal shot chips (tap → chart updates)
- Delete session with confirmation
- **POST SHOT | ANALYSIS toggle** — pill-shaped toggle in header. POST SHOT = 3-phase chart. ANALYSIS = offline trajectory replay (replay_engine.dart) rendering barrel trace + target overlay + timeline scrubber + factor breakdown cards.

## Trajectory Replay Pipeline (2026-06-21) — Updated 2026-07-08

Offline replay engine: `SessionLog` (SQLite) ��� `ReplayEngine.replay()` → `ReplayTrace` (frames + shots). Uses extracted modules.

### Modules
1. **quaternion.dart** — extracted from isolate: `Quaternion.identity()`, `normalize()`, `conjugate()`, `multiply()`, `integrate()`, `applyEulerAngle()`. Header-only, no dependency on isolate context.
2. **barrel_projection.dart** — right-handed frame (X=right, Y=down, Z=back). Exports `project(barRel, targetXDeg, targetYDeg)` → `(float x, float y)`. Barrel vector: `(0, 0, -1)`.
3. **replay_engine.dart** — full pipeline:
   - `_mergeAccelGyro(session)` **pairs by list index** (gyroX[i] ↔ accelX[i]). See "Critical Fix" below.
   - `replay(session)` → iterates merged samples:
     - Integrates gyro quaternion
     - Auto-tare when stable (threshold=0.02 rad, stationary=1.0 rad/s)
     - Applies barrel rotation + target offset
     - Detects shots via hold/press/recoil state machine (same params as isolate)
     - Produces `ReplayTrace` with `frames` (x,y,z=distance) and `shots` (scores per phase)

### Critical Fix (2026-07-08): Index-Based Merge, NOT Timestamp Buckets

`DataPoint.x` from the isolate is **epoch milliseconds** (`DateTime.now().millisecondsSinceEpoch.toDouble()`), NOT time-since-start. The original `_mergeAccelGyro` used `(p.x / dt).round()` with `dt=0.01`, which produced buckets of magnitude ~1.77e14 — every sample landed in a unique bucket, so gyro and accel never matched → 0 merged samples → 0 replay frames → "NO SHOTS RECORDED".

**Fix**: pair by `List<DataPoint>` index. In the isolate loop (lines 963-968 of `sensor_data_isolate.dart`), `gyroX[i]`, `gyroY[i]`, `gyroZ[i]`, `accelX[i]`, `accelY[i]`, `accelZ[i]` are all built from the same `timestamp` in the same iteration. Index `i` is the correct sync point.

If you ever switch to time-based bucketing, the timestamps need to be **relative** (e.g., seconds-since-session-start), not absolute.

### AnalysisTab Widget
Composite widget that renders the replay output:
1. **Header**: `BARREL TRACE` | `SHOT LIST` tabs (pill toggle) + target overlay geometry controls
2. **TrajectoryCanvas**: `CustomPaint` rendering barrel trace path + target rings + shot markers (numbers on target)
3. **Timeline**: Replay scrubber slider (shows frame count, time in sec)
4. **Phase Summary Card**: Per-shot 3-phase chart + score breakdown
5. **Factor Breakdown**: Aggregate scores for stability, smoothness, harmonics, trigger quality

### Target Overlay Geometry
- Target rings: outer → inner based on `targetRadiusDegrees` (default 5°) and `targetDistanceM` (default 10m, settings)
- Formula: `radius_px = (distanceM / tan(degrees_to_radians(targetRadiusDegrees))) * scale`
- Shot markers: numbered dots placed at projected target position per shot

### Known Issues
- **`ReplayEngine._mergeAccelGyro()`** — empty `gyroX/Y/Z` or `accelX/Y/Z` → "NO IMU DATA TO REPLAY" shown in AnalysisTab. All 6 lists must be non-empty (BLOB decode from SQLite).
- **Detected shot count may be 0 even with valid merged samples** — if `max abs gyro < 4.0 rad/s` (ARMING threshold in `ShotDetector`), no shots trigger. Live-fire and demo-mode trigger sharp gyro spikes; dry-fire without trigger pull may not.

---

## Settings Persistence

- **SharedPreferences** for app settings only
- **SQLite** for session/shots persistence (stasys_sessions.db)
- **Key strings**: `firearmType`, `trainingMode`, `maxSamples`, `mountDirection`, `mountPosition`
- **`maxSamples` clamp**: Di-load dengan `.clamp(2, 10)` di `SettingsProvider._loadSettings`. Nilai corrupt (misal 15 dari slider lama) auto-di-fix dan di-overwrite ke SharedPreferences.

---

## Export Service

`services/export_service.dart` exports all sessions to CSV via Share Sheet.

**CSV Format**:
```csv
# SESSIONS
session_date,firearm_type,training_mode,duration_sec,avg_score,best_score,worst_score,shot_count

# SHOTS
session_date,firearm_type,training_mode,shot_timestamp,total_score,hold_score,press_score,recoil_score,elevation_score,windage_score,travel_distance,peak_jerk
```

Export button in HistoryScreen header (visible when sessions exist).

---

## Dependencies (pubspec.yaml)

```yaml
flutter_bluetooth_serial: ^0.4.0      # Bluetooth Classic
syncfusion_flutter_charts: ^30.2.7   # Charts
fl_chart: ^1.0.0                      # Alternative charts
provider: ^6.1.2                      # State management
shared_preferences: ^2.2.2            # App settings only
sqflite: ^2.3.2                       # Session/shots persistence (SQLite)
path: ^1.9.0                          # Path utilities for DB
share_plus: ^10.0.0                  # CSV export via Share Sheet
permission_handler: ^12.0.1           # Android permissions
path_provider: ^2.1.1                  # File paths
crypto: ^3.0.3                        # SHA256 auth + OTA checksum
intl: ^0.19.0                         # Formatting
go_router: ^15.1.0                    # Navigation routing
mime: ^2.0.0                          # MIME type for export
```

**Assets:**
```yaml
flutter:
  assets:
    - assets/firmware/stasys_fw.bin  # OTA firmware binary (update on each release)
```

---

## OTA Firmware Update (Bluetooth Classic)

### Architecture

```
Flutter App                    ESP32 Firmware
    │                               │
    │ GET_VERSION ──────────────►   │
    │ ◄──────────── VERSION=1.0.0   │
    │                               │
    │ Compare: device vs APK        │
    │                               │
    │ OTA_START:size=1726576 ──►   │
    │ ◄──────────── OTA_READY       │
    │                               │
    │ (512-byte chunks × 3372)      │
    │ OTA_DATA:seq=0:base64=... ─► │
    │ ◄──────────── OTA_ACK:seq=0   │
    │ ...repeat...                  │
    │                               │
    │ OTA_FINISH:sha256=... ─────► │
    │ (ESP32 verifies SHA256)       │
    │ ◄──────────── OTA_COMPLETE   │
    │                               │
    │ REBOOT ──────────────────────►│ esp_restart()
    │                               │
    └─ ESP32 boots new firmware ────┘
```

### Key Files

| File | Role |
|------|------|
| `services/firmware_service.dart` | Load `.bin` from assets, compute SHA256, chunk into 512-byte pieces |
| `providers/ota_provider.dart` | State machine: idle→loading→sending→verifying→rebooting→completed/failed. 3 retries per chunk |
| `providers/bluetooth_provider.dart` | `sendOtaStart()`, `sendOtaChunk()`, `sendOtaFinish()`, `getFirmwareVersion()` |
| `screens/ota_update_screen.dart` | Full-screen progress UI (circular %, step indicators) |
| `screens/ota_prompt_dialog.dart` | Modal dialog: version compare + Skip/Update buttons |
| `screens/connection_screen.dart` | After auth, calls `_checkFirmwareUpdate()` → shows dialog or navigates to `/tracking` |
| `router/app_router.dart` | Route `/ota-update` (full-screen, outside ShellRoute) |
| `assets/firmware/stasys_fw.bin` | Bundled firmware binary (updated on each release) |
| `pubspec.yaml` | Declares `assets/firmware/stasys_fw.bin` |

### State Machine (OtaProvider)

```
OtaState.idle → loading → sending → verifying → rebooting → completed
                ↓                    ↓                      ↓
             failed (on error)   failed (OTA_FINISH fail)  failed
```

### Version Logic

- ESP32 firmware version: compile-time `FIRMWARE_VERSION` macro (storage.h) + NVS (`config` namespace, key `fw_version`)
- APK assets version: `firmware_service.dart` → `expectedVersion = '1.3.0'` (update on release)
- Dialog appears when `currentFw != newFw.version`

## OTA Firmware Update (Bluetooth Classic) — ✅ WORKING (2026-05-23)

### Architecture

```
Flutter App                    ESP32 Firmware
    │                               │
    │ GET_VERSION ──────────────►   │
    │ ◄──────────── VERSION=X.Y.Z   │
    │                               │
    │ Compare: device vs APK        │
    │                               │
    │ OTA_START:size=1728512 ──►   │
    │ ◄──────────── OTA_READY       │
    │                               │
    │ (128-byte chunks × 13473)     │
    │ OTA_DATA:seq=0:base64=... ─► │
    │ ◄──────────── OTA_ACK:seq=0   │
    │ ...repeat...                  │
    │                               │
    │ OTA_FINISH:sha256=... ─────► │
    │ (ESP32 verifies SHA256)       │
    │ ◄──────────── OTA_COMPLETE   │
    │                               │
    │ REBOOT ──────────────────────►│ esp_restart()
    │                               │
    └─ ESP32 boots new firmware ────┘
```

### Key Files

| File | Role |
|------|------|
| `services/firmware_service.dart` | Load `.bin` from assets, compute SHA256, chunk into 128-byte pieces |
| `providers/ota_provider.dart` | State machine: idle→loading→sending→verifying→rebooting→completed/failed. 3 retries per chunk, 200ms delay between chunks |
| `providers/bluetooth_provider.dart` | Dedicated `_otaMode` phase, `_otaTextBuffer` (no 2048 trim), `sendOtaStart()`, `sendOtaChunk()`, `sendOtaFinish()`, `getFirmwareVersion()` |
| `screens/ota_update_screen.dart` | Full-screen progress UI (circular %, step indicators) |
| `screens/ota_prompt_dialog.dart` | Modal dialog: version compare + Skip/Update buttons |
| `screens/connection_screen.dart` | After auth, calls `_checkFirmwareUpdate()` → shows dialog or navigates to `/tracking` |
| `router/app_router.dart` | Route `/ota-update` (full-screen, outside ShellRoute) |
| `assets/firmware/stasys_fw.bin` | Bundled firmware binary (updated on each release) |
| `pubspec.yaml` | Declares `assets/firmware/stasys_fw.bin` |

### State Machine (OtaProvider)

```
OtaState.idle → loading → sending → verifying → rebooting → completed
                ↓                    ↓                      ↓
             failed (on error)   failed (OTA_FINISH fail)  failed
```

### Version Logic

- ESP32 firmware version: compile-time `FIRMWARE_VERSION` macro (storage.h) + NVS (`config` namespace, key `fw_version`)
- APK assets version: `firmware_service.dart` → `expectedVersion = '1.4.0'` (update on release)
- Dialog appears when `currentFw != newFw.version`

### Implementation Details (2026-05-23)

**Flutter side**:
- `_connectionPhase = _ConnectionPhase.otaMode` — dedicated OTA parsing, no binary collision
- `_otaTextBuffer = ''` cleared BEFORE switching phase (prevents RangeError)
- `_waitForOtaResponse()` uses `_otaTextBuffer` in OTA mode (unlimited, no 2048 trim)
- 200ms delay between chunks (prevents ESP32 BT RX buffer overflow)
- 3 retries per chunk, 5000ms timeout per response

**ESP32 side**:
- Dual-task FreeRTOS: drain task (priority 2, Core 0) + write task (priority 1, Core 0)
- Drain task: reads SerialBT, parses text commands, sends ACKs. `taskYIELD()` after every byte prevents buffer overflow.
- Write task: receives chunks from queue, calls `esp_ota_write()` (~500ms blocking), updates SHA256
- Binary semaphore: write task signals drain task when chunk is done
- Queue size: 4 entries (128 bytes each = 512 bytes total)
- `btOtaReset()` called on disconnect, auth fail, or OTA_ABORT

**Speed**: ~13,500 chunks @ 200ms delay + esp_ota_write ~500ms per chunk = ~45 minutes for 1.7MB. See pending optimization below.

### Auto-Update Toggle

`settings_screen.dart` has switch for "Auto-update firmware" → stored in SharedPreferences as `autoUpdateFirmware` (bool, default false).

### Build Process for Release

1. Update `Firmware_STASYS32/src/storage/storage.h` → `#define FIRMWARE_VERSION "X.Y.Z"`
2. Build firmware: `cd Firmware_STASYS32 && python -m platformio run -e esp32dev`
3. Copy binary: `cp .pio/build/esp32dev/firmware.bin ../android_app/assets/firmware/stasys_fw.bin`
4. Update `firmware_service.dart` → `expectedVersion = 'X.Y.Z'`
5. Build APK: `cd android_app && flutter build apk --debug`

---

## Active Branches

| Branch | Status | Description |
|--------|---------|-------------|
| `PreProduction_0` | **Active** | TDD + STASYS_FW: CRC-16 checksum, 31-byte packets, OTA working, unit tests (27 passing), lifecycle-aware ticker |
| `trajectory_refactor` | **In Progress** | Offline trajectory replay pipeline: quaternion extraction, barrel projection, replay engine, analysis tab |
| `migrasi_firmware_awal_v1` | Backup | Previous version with XOR checksum (30-byte packets) |
| `migrasi_firmware_awal` | Backup | Snapshot of earlier version |
| `backup-dark-theme-redesign` | Backup | Full backup of all uncommitted changes pushed to remote |
| `develop` | Staged | Dark theme elements pending merge |
| `main` | Base | Initial commit only |

---

## Known Issues / TODOs

### Pending
- [ ] **OTA Speed Optimization** — Current: 45 min for 1.7MB. Target: 10-15 min. Approaches: larger chunks (256 bytes), burst mode (batched ACKs), reduced delay. Needs incremental testing (test each chunk size change).
- [ ] **Trace window sync with Python** — Flutter 2s window vs Python 0.5s cursor-normalized.
- [ ] **MantisX feature parity** — drill modes, trend analysis, split time, session notes, etc.
- [ ] **Frame freeze / gralloc4 GPU failure** — GPU/driver incompatibility with Impeller rendering engine. **Not app code issue**. Test on different device.

### Completed (2026-06-21) ✅
- [x] **Trajectory Refactor Phase 1: Module Extraction** — `quaternion.dart` (isolated from isolate), `barrel_projection.dart` (right-handed frame, exported to tests). Both header-only, no isolate dependency.
- [x] **Trajectory Refactor Phase 2: Replay Engine** — `replay_engine.dart`: offline `SessionLog` → `ReplayTrace` pipeline. Bins gyro/accel at 10ms dt, integrates quaternion, auto-tare (0.02 rad threshold, 1.0 rad/s stationary), holds target orientation, applies barrel rotation + target offset, detects shots via hold/press/recoil state machine.
- [x] **Trajectory Refactor Phase 3: AnalysisTab** — Composite widget in `session_detail_screen.dart`. Toggle between POST SHOT (3-phase chart) and ANALYSIS (offline replay). Renders barrel trace canvas with target overlay, shot markers (numbered dots), timeline scrubber, phase summary cards, and factor breakdown scores.
- [x] **Target Distance Settings** — `targetDistanceM` (5–25m, default 10m) in `SettingsProvider` + slider in `settings_screen.dart` under "TARGET DISTANCE" section.

### Completed (2026-05-23) ✅
- [x] **OTA Bluetooth Firmware Update** — ✅ WORKING! Full E2E implementation complete. See detailed implementation above. Tested E2E with 1.7MB firmware, ~45 min transfer time.

### Settings (Implemented 2026-05-09)
- [x] Mount position selector (TOP/BOT/LEFT/RIGHT) — `settings_tab.dart`, persisted via SharedPreferences
- [x] Mount direction FW/BW toggle — `_MiniToggle` bound to `SettingsProvider`, passed to isolate via `update_settings`
- [x] RESET AXIS button — triggers `SensorDataProvider.resetAxis()` → isolate `reset_axis` message → clears offsets, re-runs 50-sample auto-calibration

### Dead Code (Pending Cleanup)
- `services/sensor_data_stream.dart` — fully commented out, unused
- `providers/bluetooth_isolate.dart` — old 28-byte protocol implementation, unused
- `widgets/benchmark_analysis_widget_asli.dart` + `benchmark_anlysis_adjust.dart` — 3 versions of benchmark widget, not all in use
- `screens/main_screen.dart` — old 4-tab navigation (replaced by `main_shell.dart`)

---

## Performance Optimizations (Phase 1 & 2 — 2026-04-07)
**Goal**: Stable 60fps, production-ready code. All changes compile and APK builds successfully.

### Phase 1 — 6 fixes
- [x] **`_handleDiffUpdate` O(n) removeWhere** → immutable list assignment. Eliminated O(n) scanning on main thread.
- [x] **Data decimation** — isolate sends max 150 points (was ~500), ~70% data reduction via `_decimate()`.
- [x] **Smart `shouldRepaint`** — `_MuzzleTracePainter` compares dot position, last trace point, phase color.
- [x] **`RepaintBoundary`** — added around `MuzzleTraceWidget` CustomPaint.
- [x] **postFrameCallback consolidation** — `_PostShotTabState` uses single `_scheduleShotUpdate()` with guard flag.
- [x] **UI throttle** — reduced from 50ms (20Hz) to 33ms (~30Hz) for more headroom toward 60fps.

### Phase 2 — 9 fixes
- [x] **CustomPainter Paint/Color allocations** — All painters pre-allocate Paint/TextPainter as static fields. **~1,100 object allocations/sec eliminated.**
- [x] **`RepaintBoundary` on chart painters** — Added to `_LatestShotPanel` and `ShotAnalysisPanel`.
- [x] **ShotHistoryList cached stats** — Converted to `StatefulWidget`, avg/count computed once.
- [x] **Home tab redundant sort removed** — `SessionProvider.loadSessions()` already sorts.
- [x] **`_handleDiffUpdate` direct cast** — `List<DataPoint>.from()` → direct `as List<DataPoint>` cast. **~180 list allocations/sec eliminated.**
- [x] **`_analyzeShot()` Float64List** — Replaced `List<double>.from()`, `sublist()`, `map().toList()` with `Float64List` typed arrays. **~20 list allocations per shot eliminated.**
- [x] **Recording timer `ValueNotifier`** — `_recordingTimer` updates `recordingDurationNotifier` instead of `notifyListeners()`. No global rebuild every second.
- [x] **Timer replaces Future.delayed** — `_MuzzleTraceWidgetState` uses `Timer` with `_phaseResetTimer` cancellation.

---

## Debug Logging

Bluetooth debug logs in `bluetooth_provider.dart`:
```
[BT] Sent CMD_START_SESSION
[BT] Sent CMD_AUTH with HMAC-SHA256
[BT] Auth successful
[BT] Session started: ...
[CFG] *** data_mode=N ***  (printed on connect)
```

---

## TDD Implementation & Production Readiness (2026-05-05)

### Completed Changes

#### Phase 1: Test Infrastructure ✅
- Added `mocktail: ^1.0.3` — library-based mocking (no code generation)
- Added `coverage: ^1.7.2` — coverage reporting
- Added `firebase_crashlytics: ^4.0.0` + `firebase_core: ^3.0.0` — crash reporting (pending setup)
- Created test directory structure:
  ```
  test/
  ├── unit/
  │   ├── models/data_models_test.dart
  │   └── utils/ring_buffer_test.dart
  ```

#### Phase 2: Critical Bug Fixes ✅
**Memory leak fixes:**
- `providers/sensor_data_provider.dart` — Fixed `dispose()`:
  - Added `_mainReceivePort?.close()` + null assignment
  - Added `_dataIsolate?.kill()` + null assignment
  - Added `_recordingTimer?.cancel()` + null assignment
  - Added `super.dispose()` call

- `providers/bluetooth_provider.dart` — Fixed `dispose()`:
  - Added `_dataSubscription = null` after cancel
  - Added `_connection = null` after dispose
  - Added `super.dispose()` call

**Error handling:**
- `providers/session_logger.dart` — Added try-catch to `saveSession()`:
  - Logs session ID on success
  - Logs error with stack trace on failure
  - Re-throws exception for caller handling

#### Phase 3: Unit Tests ✅
**27 tests passing:**
- `test/unit/models/data_models_test.dart` (16 tests):
  - FirearmType.fromString, displayName
  - TrainingMode.fromString, displayName
  - DataPoint creation, toMap, fromMap
  - ShotResult creation, serialization, deserialization
  - Null phase traces handling
  - Missing enum fallback handling

- `test/unit/utils/ring_buffer_test.dart` (11 tests):
  - Capacity, add, toList
  - Overflow behavior
  - Clear and resize operations
  - Edge cases (zero, negative resize)

#### Phase 4: Production Hardening ✅
**Battery efficiency:**
- `widgets/muzzle_trace_widget.dart` — Added `WidgetsBindingObserver`:
  - 60fps ticker stops when app backgrounded (AppLifecycleState.paused/inactive/hidden)
  - Ticker resumes when app foregrounded (AppLifecycleState.resumed)
  - Prevents battery drain while app not visible

### Pending Changes (TODO)

### Quick Wins (2026-05-09) ✅
- [x] Fix duplicate `@override` in `sensor_data_provider.dart:512`
- [x] Implement Mount Direction FW/BW toggle (enum + SettingsProvider + isolate + UI)
- [x] Implement RESET AXIS button (SensorDataProvider → isolate → clear offsets + re-cal)
- [x] Implement Mount Mode selector (4-position grid with active state)
- [x] Fix maxSamples slider range di settings_tab.dart (min: 3→2, max: 15→10, divisions: 4→8)
- [x] Fix slider labels di settings_tab.dart ('3s'→'2s', '15s'→'10s')
- [x] Tambah clamp di SettingsProvider._loadSettings untuk auto-fix corrupt values (15→10)

#### Firebase Crashlytics Setup (Pending)
- [ ] Create Firebase project in Firebase Console
- [ ] Download `google-services.json` to `android_app/android/app/`
- [ ] Add Firebase plugins to `android/app/build.gradle`:
  ```groovy
  plugins {
    id 'com.google.gms.google-services'
  }
  ```
- [ ] Initialize Crashlytics in `main.dart`:
  ```dart
  await Firebase.initializeApp();
  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterError(details);
    FlutterError.presentError(details);
  };
  ```

#### Additional Test Coverage
- [ ] Service tests: `database_service_test.dart`, `export_service_test.dart`
- [ ] Provider tests: `settings_provider_test.dart`, `session_provider_test.dart`
- [ ] Widget tests: `shot_history_list_test.dart`, `shot_analysis_panel_test.dart`

#### Production Enhancements
- [ ] Offline session queue — queue failed saves for retry when connectivity restored
- [ ] ErrorWidget fallback — global error boundary for widget tree crashes
- [ ] Global exception handler in `main.dart` — catch and report unhandled exceptions

### Test Execution
```bash
flutter test                    # Run all tests
flutter test --coverage         # Run with coverage report
flutter analyze --no-fatal-infos # Check for warnings/errors
```
