// ============================================
// File: providers/sensor_data_isolate.dart
// MantisX-Style Shot Detection & Scoring
// Aligned with Python stasysz.py live tracking logic
// ============================================
import 'dart:isolate';
import 'package:ssa_app/Utils/ring_buffer.dart';
import '../models/data_models.dart';
import 'dart:math' as math;

// ============================================
// MPU6050 AXIS CONFIGURATION (from stasysz.py)
// ============================================
// Gyro axis remapping for MPU6050 orientation
const int kGyroAxisX = 2;   // gz in raw data
const int kGyroAxisY = 1;   // gy in raw data
const int kGyroAxisZ = 0;   // gx in raw data

// Gyro sign correction
const double kGyroSignX = -1.0;
const double kGyroSignY = 1.0;
const double kGyroSignZ = 1.0;

// Barrel direction vector (pointing forward, +Z)
const _kBarrelVector = [0.0, 0.0, 1.0];

// Screen coordinate signs (from stasysz.py)
const double kScreenXSign = 1.0;
const double kScreenYSign = 1.0;

// ============================================
// QUATERNION MATH (from stasysz.py)
// ============================================

class _Quaternion {
  double w, x, y, z;
  _Quaternion(this.w, this.x, this.y, this.z);

  static _Quaternion identity() => _Quaternion(1.0, 0.0, 0.0, 0.0);

  _Quaternion copy() => _Quaternion(w, x, y, z);
}

_Quaternion _quatMultiply(_Quaternion a, _Quaternion b) {
  return _Quaternion(
    a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
  );
}

_Quaternion _quatNormalize(_Quaternion q) {
  final norm = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z);
  if (norm < 1e-10) return _Quaternion.identity();
  return _Quaternion(q.w / norm, q.x / norm, q.y / norm, q.z / norm);
}

_Quaternion _quatConjugate(_Quaternion q) {
  return _Quaternion(q.w, -q.x, -q.y, -q.z);
}

List<double> _quatRotateVector(_Quaternion q, List<double> v) {
  // Pure quaternion from vector
  final pure = _Quaternion(0.0, v[0], v[1], v[2]);
  // q * pure * q_conjugate, then take vector part
  final rotated = _quatMultiply(_quatMultiply(q, pure), _quatConjugate(q));
  return [rotated.x, rotated.y, rotated.z];
}

_Quaternion _quatIntegrate(_Quaternion q, double wx, double wy, double wz, double dt) {
  // omega_pure = [0, wx, wy, wz]
  final qDot = _Quaternion(
    -0.5 * (q.x * wx + q.y * wy + q.z * wz),
    0.5 * (q.w * wx + q.y * wz - q.z * wy),
    0.5 * (q.w * wy - q.x * wz + q.z * wx),
    0.5 * (q.w * wz + q.x * wy - q.y * wx),
  );
  return _quatNormalize(_Quaternion(
    q.w + qDot.w * dt,
    q.x + qDot.x * dt,
    q.y + qDot.y * dt,
    q.z + qDot.z * dt,
  ));
}

_Quaternion _quatFromAccel(double ax, double ay, double az) {
  // g = [ax, ay, az]
  var norm = math.sqrt(ax * ax + ay * ay + az * az);
  if (norm < 1e-6) return _Quaternion.identity();
  ax /= norm;
  ay /= norm;
  az /= norm;

  // World up = [0, 0, 1]
  final dot = az; // [ax, ay, az] · [0, 0, 1]

  if (dot >= 0.9999) return _Quaternion.identity();

  if (dot <= -0.9999) {
    // Pointing straight down - use any perpendicular axis
    var axis = [1.0, 0.0, 0.0];
    var cross = ax * axis[2] - az * axis[0];
    if (cross.abs() < 1e-6) {
      axis = [0.0, 1.0, 0.0];
      cross = ax * axis[2] - az * axis[0];
    }
    final len = cross.abs();
    if (len > 1e-6) {
      axis = [axis[1] * az - axis[2] * ay, axis[2] * ax - axis[0] * az, axis[0] * ay - axis[1] * ax];
      norm = math.sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
      if (norm > 1e-6) {
        axis = [axis[0] / norm, axis[1] / norm, axis[2] / norm];
      }
    }
    return _Quaternion(0.0, axis[0], axis[1], axis[2]);
  }

  // Cross product for rotation axis
  var axisX = 0.0 - ay * 1.0 - az * 0.0; // cross([ax,ay,az], [0,0,1])[0]
  var axisY = ax * 1.0 - 0.0 - az * 0.0;  // cross([ax,ay,az], [0,0,1])[1]
  var axisZ = ax * 0.0 - ay * 0.0 - 0.0;  // cross([ax,ay,az], [0,0,1])[2]

  norm = math.sqrt(axisX * axisX + axisY * axisY + axisZ * axisZ);
  if (norm > 1e-6) {
    axisX /= norm;
    axisY /= norm;
    axisZ /= norm;
  } else {
    axisX = 1.0;
    axisY = 0.0;
    axisZ = 0.0;
  }

  final angle = math.acos(dot.clamp(-1.0, 1.0));
  final s = math.sin(angle / 2.0);
  return _Quaternion(
    math.cos(angle / 2.0),
    axisX * s,
    axisY * s,
    axisZ * s,
  );
}

/// Message untuk komunikasi dengan isolate
class SensorDataMessage {
  final String type;
  final Map<String, dynamic>? data;

  SensorDataMessage(this.type, [this.data]);
}

/// Config untuk inisialisasi isolate
class SensorIsolateConfig {
  final SendPort mainSendPort;
  final int displayWindowSeconds;
  final int uiUpdateIntervalMs;

  SensorIsolateConfig({
    required this.mainSendPort,
    this.displayWindowSeconds = 5,
    this.uiUpdateIntervalMs = 16, // 60 Hz for smooth 60fps UI updates
  });
}

// ============================================
// SCORING CONFIGURATION (MantisX-Style)
// ============================================

class ScoringConfig {
  // Detection thresholds
  static const double stabilityWindowMs = 200.0;
  static const double stabilityGyroLimit = 4.0; // rad/s threshold

  // Phase durations (in samples @ 100Hz)
  static const int holdDurationIdx = 150;  // 1.5s hold
  static const int pressDurationIdx = 30; // 0.3s press
  static const int recoilDurationIdx = 10; // 0.1s recoil
  static const int totalHistoryNeeded = holdDurationIdx + recoilDurationIdx + 10;

  // Trigger thresholds
  static const double defaultPiezoMin = 100.0;
  static const double defaultAccelThresh = 8.0;
  static const double piezoMaxLimit = 2500.0;

  // MantisX-style scoring: SOFT CURVE (more forgiving than Hardcore)
  // Score drop-off is gradual, not punishing

  // Difficulty multipliers per firearm type
  static double getDifficultyMultiplier(FirearmType type) {
    switch (type) {
      case FirearmType.pistol:
        return 1.0;    // Baseline
      case FirearmType.rifle:
        return 0.7;    // More stable platform, stricter
      case FirearmType.archery:
        return 1.3;    // High precision needed
      case FirearmType.shotgun:
        return 0.9;    // Follow-through focus
    }
  }

  // Training mode adjustments
  static double getModeMultiplier(TrainingMode mode) {
    switch (mode) {
      case TrainingMode.dryFire:
        return 1.0;  // Baseline
      case TrainingMode.liveFire:
        return 0.8;  // More forgiving due to recoil
    }
  }

  // Soft curve scoring: uses sqrt for gentle drop-off
  // Total penalty is proportional to sqrt(travel), not linear
  // This means scores are achievable for intermediate shooters
  static double calculateScore({
    required double totalTravel,
    required double peakJerk,
    required FirearmType firearmType,
    required TrainingMode trainingMode,
    required double elevTravel,
    required double windTravel,
    required List<double> holdDeltas,
    required List<double> pressDeltas,
    required List<double> recoilDeltas,
  }) {
    final difficulty = getDifficultyMultiplier(firearmType);
    final modeMult = getModeMultiplier(trainingMode);
    final baseMultiplier = difficulty * modeMult;

    // Soft curve: sqrt-based penalties
    // Travel penalty: sqrt(total_travel) * multiplier
    // This means 0.01 degrees → small penalty, 0.1 degrees → noticeable but not devastating
    final travelPenalty = math.sqrt(totalTravel) * 30.0 * baseMultiplier;

    // Jerk penalty: sqrt(peak_jerk) * multiplier
    // Single large spike is punished but not catastrophic
    final jerkPenalty = math.sqrt(peakJerk) * 25.0 * baseMultiplier;

    // Per-phase penalties (softer)
    double holdPenalty = 0;
    double pressPenalty = 0;
    double recoilPenalty = 0;

    if (holdDeltas.isNotEmpty) {
      final avgHold = holdDeltas.reduce((a, b) => a + b) / holdDeltas.length;
      holdPenalty = math.sqrt(avgHold) * 10.0 * baseMultiplier;
    }

    if (pressDeltas.isNotEmpty) {
      final avgPress = pressDeltas.reduce((a, b) => a + b) / pressDeltas.length;
      pressPenalty = math.sqrt(avgPress) * 15.0 * baseMultiplier;
    }

    if (recoilDeltas.isNotEmpty) {
      final avgRecoil = recoilDeltas.reduce((a, b) => a + b) / recoilDeltas.length;
      recoilPenalty = math.sqrt(avgRecoil) * 5.0 * baseMultiplier;
    }

    // Per-axis penalties (softer)
    final elevPenalty = math.sqrt(elevTravel) * 15.0 * baseMultiplier;
    final windPenalty = math.sqrt(windTravel) * 15.0 * baseMultiplier;

    // Combined score
    final totalPenalty =
        travelPenalty + jerkPenalty +
        holdPenalty + pressPenalty + recoilPenalty +
        elevPenalty + windPenalty;

    final rawScore = 100.0 - totalPenalty;
    final score = math.max(0.0, math.min(100.0, rawScore));

    return score;
  }

  // Phase scores
  static double calculatePhaseScore(List<double> deltas, double multiplier) {
    if (deltas.isEmpty) return 100.0;
    final total = deltas.reduce((a, b) => a + b);
    final avg = total / deltas.length;
    final penalty = math.sqrt(avg) * 15.0 * multiplier;
    return math.max(0.0, math.min(100.0, 100.0 - penalty));
  }

  // Axis scores
  static double calculateAxisScore(double travel) {
    final penalty = math.sqrt(travel) * 15.0;
    return math.max(0.0, math.min(100.0, 100.0 - penalty));
  }
}

// ============================================
// SHOT DETECTOR STATE MACHINE (aligned with stasysz.py)
// ============================================

enum ShotState { idle, arming, armed, postGather, cooldown }

class ShotDetector {
  // Settings (from provider)
  FirearmType firearmType = FirearmType.pistol;
  TrainingMode trainingMode = TrainingMode.dryFire;
  MountDirection mountDirection = MountDirection.forward;
  double accelThresh = ScoringConfig.defaultAccelThresh;
  double piezoThresh = ScoringConfig.defaultPiezoMin;

  // State
  ShotState state = ShotState.idle;
  double stateTimer = 0;
  int gatherCounter = 0;
  int lastTriggerPiezo = 0;

  // History buffers for trace analysis (quaternion-based projection)
  final List<double> _traceX = []; // Screen X from atan2 projection
  final List<double> _traceY = []; // Screen Y from atan2 projection

  // Quaternion state for orientation tracking
  _Quaternion _q = _Quaternion.identity();
  _Quaternion _qTare = _Quaternion.identity(); // Tare reference

  // Calibration
  double offsetGx = 0;
  double offsetGy = 0;
  double offsetGz = 0;

  // Auto-tare parameters (same as Python stasysz.py)
  bool isCalibrated = false;
  double driftThreshold = 0.02;     // ~1.1° trigger re-tare (was 0.05)
  double stationaryThreshold = 0.15; // rad/s — MPU6050 noise floor at true rest (~8.6 deg/s)
  double autoTareInterval = 3.0;     // seconds between auto-tares (was 5s)
  double lastAutoTare = 0.0;
  int stationaryCount = 0;
  int stationaryNeeded = 50;         // ~0.5s of stillness at 100Hz
  double gxRaw = 0.0, gyRaw = 0.0, gzRaw = 0.0;  // raw gyro for stationary detection

  // Previous accelerometer for jerk calculation
  double _prevAx = 0, _prevAy = 0, _prevAz = 0;

  // Buffer size for trace history
  int get _bufferSize => (ScoringConfig.holdDurationIdx +
                         ScoringConfig.recoilDurationIdx + 10) * 2;

  static const double dt = 0.01; // 100Hz = 10ms

  void calibrate(List<double> gx, List<double> gy, List<double> gz) {
    if (gx.isEmpty) return;
    offsetGx = gx.reduce((a, b) => a + b) / gx.length;
    offsetGy = gy.reduce((a, b) => a + b) / gy.length;
    offsetGz = gz.reduce((a, b) => a + b) / gz.length;
  }

  void tare() {
    // Initialize tare quaternion from current orientation
    _qTare = _q.copy();
  }

  void setQuaternion(_Quaternion q) {
    _q = q;
  }

  void reset() {
    _traceX.clear();
    _traceY.clear();
    _q = _Quaternion.identity();
    _qTare = _Quaternion.identity();
    state = ShotState.idle;
    stateTimer = 0;
    gatherCounter = 0;
  }

  void updateMountDirection(MountDirection dir) {
    mountDirection = dir;
  }

  ShotResult? process({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required int piezo,
  }) {
    // 0. Store raw gyros for stationary detection
    gxRaw = gx;
    gyRaw = gy;
    gzRaw = gz;

    // 1. Bias-correct raw gyros
    final gxBc = gx - offsetGx;
    final gyBc = gy - offsetGy;
    final gzBc = gz - offsetGz;

    // 2. Remap gyro axes (MPU6050 orientation)
    final rawGyros = [gxBc, gyBc, gzBc];
    final wx = kGyroSignX * rawGyros[kGyroAxisX];
    final wy = kGyroSignY * rawGyros[kGyroAxisY];
    final wz = kGyroSignZ * rawGyros[kGyroAxisZ];

    // 3. Integrate orientation quaternion
    _q = _quatIntegrate(_q, wx, wy, wz, dt);

    // 4. Relative (tared) quaternion
    final qRel = _quatNormalize(
      _quatMultiply(_quatConjugate(_qTare), _q));

    // 5. Project barrel direction to 2D screen coordinates
    //    Using atan2 projection (from stasysz.py)
    final v = _quatRotateVector(qRel, _kBarrelVector);
    final currX = math.atan2(-v[1], v[2]) * kScreenXSign;
    final currY = math.atan2(v[0], v[2]) * kScreenYSign;

    // 6. Store trace
    _traceX.add(currX);
    _traceY.add(currY);

    // Trim to needed length
    if (_traceX.length > _bufferSize) {
      _traceX.removeRange(0, _traceX.length - _bufferSize);
      _traceY.removeRange(0, _traceY.length - _bufferSize);
    }

    // 7. Calculate rotation magnitude for shot detection
    final rotMag = math.sqrt(wx * wx + wy * wy + wz * wz);

    // 8. Calculate jerk from accelerometer
    final jerk = _calculateJerk(ax, ay, az);

    ShotResult? result;

    switch (state) {
      case ShotState.cooldown:
        stateTimer -= dt;
        if (stateTimer <= 0) state = ShotState.idle;
        break;

      case ShotState.idle:
        if (rotMag < ScoringConfig.stabilityGyroLimit) {
          state = ShotState.arming;
          stateTimer = 0;
        }
        break;

      case ShotState.arming:
        if (rotMag > ScoringConfig.stabilityGyroLimit) {
          state = ShotState.idle;
        } else {
          stateTimer += dt * 1000; // ms
          if (stateTimer >= ScoringConfig.stabilityWindowMs) {
            state = ShotState.armed;
          }
        }
        break;

      case ShotState.armed:
        bool triggered = false;

        if (trainingMode == TrainingMode.liveFire) {
          // Live fire: trigger on jerk/accel spike
          if (jerk > (accelThresh * 1.5)) triggered = true;
        } else {
          // Dry fire: trigger on piezo
          if (piezo >= piezoThresh && piezo <= ScoringConfig.piezoMaxLimit) {
            if (rotMag < 6.0) triggered = true; // Still relatively stable
          }
        }

        if (triggered) {
          lastTriggerPiezo = piezo;
          state = ShotState.postGather;
          gatherCounter = ScoringConfig.recoilDurationIdx;
        }

        if (rotMag > (ScoringConfig.stabilityGyroLimit * 3.0)) {
          state = ShotState.idle;
        }
        break;

      case ShotState.postGather:
        gatherCounter -= 1;
        if (gatherCounter <= 0) {
          result = _analyzeShot();
          state = ShotState.cooldown;
          stateTimer = 0.5;
        }
        break;
    }

    // Silent auto-tare if drift accumulated (same as Python stasysz.py)
    // Auto-tare triggers when: stationary for ~0.5s AND drift > 1.1°
    autoTare();

    return result;
  }

  bool _isStationary() {
    final gxBc = gxRaw - offsetGx;
    final gyBc = gyRaw - offsetGy;
    final gzBc = gzRaw - offsetGz;
    final mag = math.sqrt(gxBc * gxBc + gyBc * gyBc + gzBc * gzBc);
    return mag < stationaryThreshold;
  }

  void autoTare() {
    if (!isCalibrated) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    if (now - lastAutoTare < autoTareInterval) return;

    // Check if stationary using bias-corrected gyro
    final gxBc = gxRaw - offsetGx;
    final gyBc = gyRaw - offsetGy;
    final gzBc = gzRaw - offsetGz;
    final mag = math.sqrt(gxBc * gxBc + gyBc * gyBc + gzBc * gzBc);

    if (mag < stationaryThreshold) {
      stationaryCount++;
    } else {
      stationaryCount = 0;
    }
    if (stationaryCount < stationaryNeeded) return;

    // Check if drift is significant
    final aimOffset = math.sqrt(lastTraceX * lastTraceX + lastTraceY * lastTraceY);
    if (aimOffset >= driftThreshold) {
      // CRITICAL: Reset qTare to stop drift accumulation (same as Python _apply_tare)
      _qTare = _q.copy();
      _traceX.clear();
      _traceY.clear();
      lastAutoTare = now;
      stationaryCount = 0;
    }
  }

  double _calculateJerk(double ax, double ay, double az) {
    final jx = ax - _prevAx;
    final jy = ay - _prevAy;
    final jz = az - _prevAz;
    _prevAx = ax;
    _prevAy = ay;
    _prevAz = az;
    return math.sqrt(jx * jx + jy * jy + jz * jz) / dt;
  }

  // Public getters for trace coordinates (used by widget)
  List<double> get traceX => List.unmodifiable(_traceX);
  List<double> get traceY => List.unmodifiable(_traceY);
  double get lastTraceX => _traceX.isNotEmpty ? _traceX.last : 0.0;
  double get lastTraceY => _traceY.isNotEmpty ? _traceY.last : 0.0;

  ShotResult? _analyzeShot() {
    if (_traceX.length < ScoringConfig.totalHistoryNeeded) return null;

    final fullX = List<double>.from(_traceX);
    final fullY = List<double>.from(_traceY);

    final idxRecoilEnd = fullX.length;
    final idxBreak = idxRecoilEnd - ScoringConfig.recoilDurationIdx;
    final idxPressStart = idxBreak - ScoringConfig.pressDurationIdx;
    final idxHoldStart = idxBreak - ScoringConfig.holdDurationIdx;

    if (idxHoldStart < 0) return null;

    // Reference point at break
    final breakX = fullX[idxBreak];
    final breakY = fullY[idxBreak];

    // Normalized segments
    final holdX = fullX.sublist(idxHoldStart, idxPressStart).map((v) => v - breakX).toList();
    final holdY = fullY.sublist(idxHoldStart, idxPressStart).map((v) => v - breakY).toList();
    final pressX = fullX.sublist(idxPressStart, idxBreak + 1).map((v) => v - breakX).toList();
    final pressY = fullY.sublist(idxPressStart, idxBreak + 1).map((v) => v - breakY).toList();
    final recoilX = fullX.sublist(idxBreak, idxRecoilEnd).map((v) => v - breakX).toList();
    final recoilY = fullY.sublist(idxBreak, idxRecoilEnd).map((v) => v - breakY).toList();

    // Calculate total travel for press phase
    double totalTravel = 0;
    double peakJerk = 0;
    double elevTravel = 0;
    double windTravel = 0;

    final allDeltas = <double>[];
    for (int i = 1; i < pressX.length; i++) {
      final dx = pressX[i] - pressX[i - 1];
      final dy = pressY[i] - pressY[i - 1];
      final dist = math.sqrt(dx * dx + dy * dy);
      allDeltas.add(dist);
      totalTravel += dist;
      if (dist > peakJerk) peakJerk = dist;
    }

    // Elevation = integrated Y (up/down)
    for (int i = 1; i < pressY.length; i++) {
      final d = (pressY[i] - pressY[i - 1]).abs();
      elevTravel += d;
    }

    // Windage = integrated X (left/right)
    for (int i = 1; i < pressX.length; i++) {
      final d = (pressX[i] - pressX[i - 1]).abs();
      windTravel += d;
    }

    // Phase deltas
    final holdDeltas = _getDeltas(holdX, holdY);
    final recoilDeltas = _getDeltas(recoilX, recoilY);

    // Calculate all scores
    final multiplier = ScoringConfig.getDifficultyMultiplier(firearmType) *
        ScoringConfig.getModeMultiplier(trainingMode);

    final totalScore = ScoringConfig.calculateScore(
      totalTravel: totalTravel,
      peakJerk: peakJerk,
      firearmType: firearmType,
      trainingMode: trainingMode,
      elevTravel: elevTravel,
      windTravel: windTravel,
      holdDeltas: holdDeltas,
      pressDeltas: allDeltas,
      recoilDeltas: recoilDeltas,
    );

    final holdScore = ScoringConfig.calculatePhaseScore(holdDeltas, multiplier);
    final pressScore = ScoringConfig.calculatePhaseScore(allDeltas, multiplier);
    final recoilScore = ScoringConfig.calculatePhaseScore(recoilDeltas, multiplier);
    final elevScore = ScoringConfig.calculateAxisScore(elevTravel);
    final windScore = ScoringConfig.calculateAxisScore(windTravel);

    return ShotResult(
      timestamp: DateTime.now(),
      totalScore: totalScore,
      holdScore: holdScore,
      pressScore: pressScore,
      recoilScore: recoilScore,
      elevationScore: elevScore,
      windageScore: windScore,
      travelDistance: totalTravel,
      peakJerk: peakJerk,
      firearmType: firearmType,
      trainingMode: trainingMode,
      holdX: holdX,
      holdY: holdY,
      pressX: pressX,
      pressY: pressY,
      recoilX: recoilX,
      recoilY: recoilY,
    );
  }

  List<double> _getDeltas(List<double> x, List<double> y) {
    final deltas = <double>[];
    for (int i = 1; i < x.length; i++) {
      final dx = x[i] - x[i - 1];
      final dy = y[i] - y[i - 1];
      deltas.add(math.sqrt(dx * dx + dy * dy));
    }
    return deltas;
  }
}

// ============================================
// SENSOR DATA ISOLATE
// ============================================

class SensorDataIsolate {
  static const int _assumedDataRateHz = 100;

  // Ring buffers
  late RingBuffer<DataPoint> _fullGyroX;
  late RingBuffer<DataPoint> _fullGyroY;
  late RingBuffer<DataPoint> _fullGyroZ;
  late RingBuffer<DataPoint> _fullAccelX;
  late RingBuffer<DataPoint> _fullAccelY;
  late RingBuffer<DataPoint> _fullAccelZ;

  // Diff buffers
  final List<DataPoint> _newGyroX = [];
  final List<DataPoint> _newGyroY = [];
  final List<DataPoint> _newGyroZ = [];
  final List<DataPoint> _newAccelX = [];
  final List<DataPoint> _newAccelY = [];
  final List<DataPoint> _newAccelZ = [];

  // Session buffers
  final List<DataPoint> _sessionGyroX = [];
  final List<DataPoint> _sessionGyroY = [];
  final List<DataPoint> _sessionGyroZ = [];
  final List<DataPoint> _sessionAccelX = [];
  final List<DataPoint> _sessionAccelY = [];
  final List<DataPoint> _sessionAccelZ = [];

  // Shot detector
  final ShotDetector _shotDetector = ShotDetector();

  // Settings
  FirearmType _firearmType = FirearmType.pistol;
  TrainingMode _trainingMode = TrainingMode.dryFire;
  MountDirection _mountDirection = MountDirection.forward;

  // State
  late SendPort _mainSendPort;
  late int _uiUpdateIntervalMs;
  late int _displayWindowSeconds;
  int _lastUiUpdateMs = 0;

  bool _isRecording = false;
  bool _isCalibrating = false;
  int _calibrationSamplesCount = 0;
  final int _samplesToCollect = 50;

  // Auto-calibration: runs on first 50 samples automatically
  bool _autoCalibrating = true;
  final List<List<double>> _autoCalSamples = [];  // [ax, ay, az, gx, gy, gz] per sample

  double _offsetGyroX = 0.0;
  double _offsetGyroY = 0.0;
  double _offsetGyroZ = 0.0;

  late DateTime _baseTime;

  // Shot storage for session
  final List<ShotResult> _sessionShots = [];

  // Performance tracking
  int _dataPointsReceived = 0;
  int _uiUpdatesSkipped = 0;

  // Calibrated flag
  bool _isCalibrated = false;

  static void entryPoint(SensorIsolateConfig config) {
    final isolate = SensorDataIsolate._internal(config);

    final receivePort = ReceivePort();
    config.mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is SensorDataMessage) {
        isolate._handleMessage(message);
      }
    });
  }

  SensorDataIsolate._internal(SensorIsolateConfig config) {
    _mainSendPort = config.mainSendPort;
    _uiUpdateIntervalMs = config.uiUpdateIntervalMs;
    _displayWindowSeconds = config.displayWindowSeconds;
    _baseTime = DateTime.now();

    final bufferSize = _displayWindowSeconds * _assumedDataRateHz;
    _fullGyroX = RingBuffer<DataPoint>(bufferSize);
    _fullGyroY = RingBuffer<DataPoint>(bufferSize);
    _fullGyroZ = RingBuffer<DataPoint>(bufferSize);
    _fullAccelX = RingBuffer<DataPoint>(bufferSize);
    _fullAccelY = RingBuffer<DataPoint>(bufferSize);
    _fullAccelZ = RingBuffer<DataPoint>(bufferSize);
  }

  void _handleMessage(SensorDataMessage message) {
    try {
      switch (message.type) {
        case 'sensor_data':
          if (message.data != null) _processSensorData(message.data!);
          break;
        case 'start_calibration':
          // Debug via isolate-to-main message is complex, skip for now
          // Just call _startCalibration which handles the flow
          _startCalibration();
          break;
        case 'start_recording':
          _startRecording();
          break;
        case 'stop_recording':
          _stopRecording();
          break;
        case 'reset':
          _reset();
          break;
        case 'get_session_data':
          _sendSessionData();
          break;
        case 'clear_session':
          _clearSessionData();
          break;
        case 'request_full_sync':
          _sendFullSync();
          break;
        case 'update_settings':
          _updateSettings(message.data!);
          break;
        case 'reset_axis':
          _resetAxis();
          break;
      }
    } catch (e) {
      // Silently catch errors to keep isolate alive
    }
  }

  void _updateSettings(Map<String, dynamic> data) {
    if (data.containsKey('firearmType')) {
      _firearmType = FirearmType.fromString(data['firearmType']);
      _shotDetector.firearmType = _firearmType;
    }
    if (data.containsKey('trainingMode')) {
      _trainingMode = TrainingMode.fromString(data['trainingMode']);
      _shotDetector.trainingMode = _trainingMode;
    }
    if (data.containsKey('displayWindowSeconds')) {
      final newWindow = data['displayWindowSeconds'] as int;
      if (newWindow != _displayWindowSeconds) {
        _displayWindowSeconds = newWindow;
        _rebuildBuffers();
      }
    }
    if (data.containsKey('mountDirection')) {
      _mountDirection = MountDirection.fromString(data['mountDirection']);
      _shotDetector.updateMountDirection(_mountDirection);
    }
  }

  void _resetAxis() {
    // Clear auto-calibration flag and offsets
    _offsetGyroX = 0.0;
    _offsetGyroY = 0.0;
    _offsetGyroZ = 0.0;
    _autoCalibrating = true;
    _autoCalSamples.clear();
    _shotDetector.reset();
    _mainSendPort.send(SensorDataMessage('reset_axis_complete'));
  }

  void _rebuildBuffers() {
    final bufferSize = _displayWindowSeconds * _assumedDataRateHz;
    _fullGyroX = RingBuffer<DataPoint>(bufferSize);
    _fullGyroY = RingBuffer<DataPoint>(bufferSize);
    _fullGyroZ = RingBuffer<DataPoint>(bufferSize);
    _fullAccelX = RingBuffer<DataPoint>(bufferSize);
    _fullAccelY = RingBuffer<DataPoint>(bufferSize);
    _fullAccelZ = RingBuffer<DataPoint>(bufferSize);
    _newGyroX.clear();
    _newGyroY.clear();
    _newGyroZ.clear();
    _newAccelX.clear();
    _newAccelY.clear();
    _newAccelZ.clear();
  }

  void _processSensorData(Map<String, dynamic> data) {
    final ax = (data['ax'] as num).toDouble();
    final ay = (data['ay'] as num).toDouble();
    final az = (data['az'] as num).toDouble();
    final gx = (data['gx'] as num).toDouble();
    final gy = (data['gy'] as num).toDouble();
    final gz = (data['gz'] as num).toDouble();
    final piezo = (data['piezo'] as num?)?.toInt() ?? 0;

    // Auto-calibration: collect samples and process them through detector after
    if (_autoCalibrating) {
      _autoCalSamples.add([ax, ay, az, gx, gy, gz]);

      if (_autoCalSamples.length >= _samplesToCollect) {
        // Compute gyro zero-offset
        double sumGx = 0, sumGy = 0, sumGz = 0;
        double sumAx = 0, sumAy = 0, sumAz = 0;
        for (final s in _autoCalSamples) {
          sumAx += s[0]; sumAy += s[1]; sumAz += s[2];
          sumGx += s[3]; sumGy += s[4]; sumGz += s[5];
        }
        final n = _autoCalSamples.length.toDouble();
        _offsetGyroX = sumGx / n;
        _offsetGyroY = sumGy / n;
        _offsetGyroZ = sumGz / n;
        _shotDetector.offsetGx = _offsetGyroX;
        _shotDetector.offsetGy = _offsetGyroY;
        _shotDetector.offsetGz = _offsetGyroZ;

        // Initialize quaternion from accelerometer average (like Python calibrate)
        final meanAx = sumAx / n;
        final meanAy = sumAy / n;
        final meanAz = sumAz / n;
        _shotDetector.setQuaternion(_quatFromAccel(meanAx, meanAy, meanAz));
        _shotDetector.tare();

        // Process ALL calibration samples through detector to build initial trace
        for (final s in _autoCalSamples) {
          _shotDetector.process(
            ax: s[0], ay: s[1], az: s[2],
            gx: s[3] - _offsetGyroX,
            gy: s[4] - _offsetGyroY,
            gz: s[5] - _offsetGyroZ,
            piezo: 0,
          );
        }

        _autoCalSamples.clear();
        _autoCalibrating = false;
        _isCalibrated = true;
        _shotDetector.isCalibrated = true;
        _mainSendPort.send(SensorDataMessage('calibration_complete', {
          'offsetGyroX': _offsetGyroX,
          'offsetGyroY': _offsetGyroY,
          'offsetGyroZ': _offsetGyroZ,
        }));
      }
      return; // Skip throttled update during calibration accumulation
    }

    // Manual calibration (user-triggered via button)
    if (_isCalibrating) {
      _offsetGyroX += gx;
      _offsetGyroY += gy;
      _offsetGyroZ += gz;
      _calibrationSamplesCount++;

      // Send progress update every 10 samples
      if (_calibrationSamplesCount % 10 == 0) {
        _mainSendPort.send(SensorDataMessage('calibration_progress', {
          'count': _calibrationSamplesCount,
          'total': _samplesToCollect,
        }));
      }

      if (_calibrationSamplesCount >= _samplesToCollect) {
        _offsetGyroX /= _samplesToCollect;
        _offsetGyroY /= _samplesToCollect;
        _offsetGyroZ /= _samplesToCollect;

        _shotDetector.offsetGx = _offsetGyroX;
        _shotDetector.offsetGy = _offsetGyroY;
        _shotDetector.offsetGz = _offsetGyroZ;
        _shotDetector.calibrate(
          _buildCalibrationList(_offsetGyroX),
          _buildCalibrationList(_offsetGyroY),
          _buildCalibrationList(_offsetGyroZ),
        );

        _isCalibrating = false;
        _isCalibrated = true;

        _mainSendPort.send(SensorDataMessage('calibration_complete', {
          'offsetGyroX': _offsetGyroX,
          'offsetGyroY': _offsetGyroY,
          'offsetGyroZ': _offsetGyroZ,
        }));
      }
      return;
    }

    // Apply offset
    final fixedGx = gx - _offsetGyroX;
    final fixedGy = gy - _offsetGyroY;
    final fixedGz = gz - _offsetGyroZ;

    final timestamp = DateTime.now().millisecondsSinceEpoch.toDouble();

    // DataPoints
    final dpAx = DataPoint.fromTimestamp(timestamp: timestamp, value: ax);
    final dpAy = DataPoint.fromTimestamp(timestamp: timestamp, value: ay);
    final dpAz = DataPoint.fromTimestamp(timestamp: timestamp, value: az);
    final dpGx = DataPoint.fromTimestamp(timestamp: timestamp, value: fixedGx);
    final dpGy = DataPoint.fromTimestamp(timestamp: timestamp, value: fixedGy);
    final dpGz = DataPoint.fromTimestamp(timestamp: timestamp, value: fixedGz);

    // Add to buffers
    _newAccelX.add(dpAx);
    _newAccelY.add(dpAy);
    _newAccelZ.add(dpAz);
    _newGyroX.add(dpGx);
    _newGyroY.add(dpGy);
    _newGyroZ.add(dpGz);

    _fullAccelX.add(dpAx);
    _fullAccelY.add(dpAy);
    _fullAccelZ.add(dpAz);
    _fullGyroX.add(dpGx);
    _fullGyroY.add(dpGy);
    _fullGyroZ.add(dpGz);

    if (_isRecording) {
      _sessionAccelX.add(dpAx);
      _sessionAccelY.add(dpAy);
      _sessionAccelZ.add(dpAz);
      _sessionGyroX.add(dpGx);
      _sessionGyroY.add(dpGy);
      _sessionGyroZ.add(dpGz);
    }

    // Shot detection — pass RAW gyro, let process() bias-correct once internally
    final shotResult = _shotDetector.process(
      ax: ax, ay: ay, az: az,
      gx: gx, gy: gy, gz: gz,  // raw sensor values (NOT fixedGx/fixedGy/fixedGz)
      piezo: piezo,
    );

    if (shotResult != null) {
      _sessionShots.add(shotResult);
      _mainSendPort.send(SensorDataMessage('shot_detected', {
        'shot': shotResult.toMap(),
      }));
    }

    _dataPointsReceived++;

    // Throttled UI update
    final currentMs = DateTime.now().millisecondsSinceEpoch;
    if (currentMs - _lastUiUpdateMs >= _uiUpdateIntervalMs) {
      _lastUiUpdateMs = currentMs;
      _sendThrottledUpdate();
    } else {
      _uiUpdatesSkipped++;
    }
  }

  List<double> _buildCalibrationList(double value) {
    return [value];
  }

  void _sendThrottledUpdate() {
    if (_newGyroX.isEmpty) return;

    _mainSendPort.send(SensorDataMessage('ui_update', {
      'gyroX': _fullGyroX.toList(),
      'gyroY': _fullGyroY.toList(),
      'gyroZ': _fullGyroZ.toList(),
      'accelX': _fullAccelX.toList(),
      'accelY': _fullAccelY.toList(),
      'accelZ': _fullAccelZ.toList(),
      'traceX': _shotDetector.traceX,
      'traceY': _shotDetector.traceY,
      'liveX': _shotDetector.lastTraceX,
      'liveY': _shotDetector.lastTraceY,
    }));

    _newGyroX.clear();
    _newGyroY.clear();
    _newGyroZ.clear();
    _newAccelX.clear();
    _newAccelY.clear();
    _newAccelZ.clear();
  }

  void _sendFullSync() {
    _mainSendPort.send(SensorDataMessage('ui_update', {
      'gyroX': _fullGyroX.toList(),
      'gyroY': _fullGyroY.toList(),
      'gyroZ': _fullGyroZ.toList(),
      'accelX': _fullAccelX.toList(),
      'accelY': _fullAccelY.toList(),
      'accelZ': _fullAccelZ.toList(),
      'traceX': _shotDetector.traceX,
      'traceY': _shotDetector.traceY,
      'liveX': _shotDetector.lastTraceX,
      'liveY': _shotDetector.lastTraceY,
    }));
  }

  void _startCalibration() {
    _isCalibrating = true;
    _calibrationSamplesCount = 0;
    _offsetGyroX = 0.0;
    _offsetGyroY = 0.0;
    _offsetGyroZ = 0.0;
    _mainSendPort.send(SensorDataMessage('calibration_started'));
  }

  void _startRecording() {
    _isRecording = true;
    _sessionShots.clear();
    // NOTE: Don't clear session data — user may have previous data they want to keep
    // _clearSessionData() called only on explicit clear or new session start
    _mainSendPort.send(SensorDataMessage('recording_started'));
  }

  void _stopRecording() {
    _isRecording = false;
    // Send session data immediately so provider can enable Save button
    _sendSessionData();
    _mainSendPort.send(SensorDataMessage('recording_stopped'));
  }

  void _reset() {
    _baseTime = DateTime.now();

    final bufferSize = _displayWindowSeconds * _assumedDataRateHz;
    _fullGyroX = RingBuffer<DataPoint>(bufferSize);
    _fullGyroY = RingBuffer<DataPoint>(bufferSize);
    _fullGyroZ = RingBuffer<DataPoint>(bufferSize);
    _fullAccelX = RingBuffer<DataPoint>(bufferSize);
    _fullAccelY = RingBuffer<DataPoint>(bufferSize);
    _fullAccelZ = RingBuffer<DataPoint>(bufferSize);

    _newGyroX.clear();
    _newGyroY.clear();
    _newGyroZ.clear();
    _newAccelX.clear();
    _newAccelY.clear();
    _newAccelZ.clear();
    _clearSessionData();

    _dataPointsReceived = 0;
    _uiUpdatesSkipped = 0;

    _mainSendPort.send(SensorDataMessage('reset_complete'));
  }

  void _sendSessionData() {
    _mainSendPort.send(SensorDataMessage('session_data', {
      'gyroX': List<DataPoint>.from(_sessionGyroX),
      'gyroY': List<DataPoint>.from(_sessionGyroY),
      'gyroZ': List<DataPoint>.from(_sessionGyroZ),
      'accelX': List<DataPoint>.from(_sessionAccelX),
      'accelY': List<DataPoint>.from(_sessionAccelY),
      'accelZ': List<DataPoint>.from(_sessionAccelZ),
      'shots': _sessionShots.map((s) => s.toMap()).toList(),
    }));
  }

  void _clearSessionData() {
    _sessionGyroX.clear();
    _sessionGyroY.clear();
    _sessionGyroZ.clear();
    _sessionAccelX.clear();
    _sessionAccelY.clear();
    _sessionAccelZ.clear();
    _sessionShots.clear();
  }
}
