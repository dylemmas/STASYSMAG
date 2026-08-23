// ============================================
// File: services/trajectory/replay_engine.dart
// Re-runs the ShotDetector trace pipeline offline on a saved SessionLog.
// ============================================
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../providers/session_logger.dart' show SessionLog;
import 'projection.dart';
import 'replay_models.dart';

class ReplayEngine {
  static const double dt = 0.01;
  static const int holdDurationIdx = 150;
  static const int pressDurationIdx = 30;
  static const int recoilDurationIdx = 10;
  static const int totalHistoryNeeded = holdDurationIdx + recoilDurationIdx + 10;
  static const double stabilityWindowMs = 200.0;
  static const double stabilityGyroLimit = 4.0;
  static const int kGyroAxisX = 2;
  static const int kGyroAxisY = 1;
  static const int kGyroAxisZ = 0;
  static const double kGyroSignX = -1.0;
  static const double kGyroSignY = 1.0;
  static const double kGyroSignZ = 1.0;
  static const _kBarrelVector = [0.0, 0.0, 1.0];
  static const double kScreenXSign = 1.0;
  static const double kScreenYSign = 1.0;

  ReplayTrace replay(SessionLog session, {double targetDistanceM = 10.0}) {
    final samples = _mergeAccelGyro(session);
    debugPrint('[REPLAY] gyroX=${session.gyroX.length} gyroY=${session.gyroY.length} gyroZ=${session.gyroZ.length} '
        'accelX=${session.accelX.length} accelY=${session.accelY.length} accelZ=${session.accelZ.length} '
        'shots=${session.shots.length}');
    debugPrint('[REPLAY] merged samples: ${samples.length}');
    if (samples.isEmpty) {
      return ReplayTrace(
        frames: [],
        shots: [],
        totalDurationSeconds: 0,
        sampleRateHz: 100,
        targetDistanceM: targetDistanceM,
      );
    }
    // Log gyro stats for first few samples
    if (samples.length > 5) {
      double maxGx = 0, maxGy = 0, maxGz = 0;
      for (int i = 0; i < samples.length; i++) {
        if (samples[i].gx.abs() > maxGx) maxGx = samples[i].gx.abs();
        if (samples[i].gy.abs() > maxGy) maxGy = samples[i].gy.abs();
        if (samples[i].gz.abs() > maxGz) maxGz = samples[i].gz.abs();
      }
      debugPrint('[REPLAY] max abs gyro: gx=$maxGx gy=$maxGy gz=$maxGz');
    }

    // Calibrate: mean of first 50 samples (or all if fewer)
    final calibLen = math.min(50, samples.length);
    double offsetGx = 0, offsetGy = 0, offsetGz = 0;
    for (int i = 0; i < calibLen; i++) {
      offsetGx += samples[i].gx;
      offsetGy += samples[i].gy;
      offsetGz += samples[i].gz;
    }
    offsetGx /= calibLen;
    offsetGy /= calibLen;
    offsetGz /= calibLen;

    var q = Quaternion.identity();
    final qTare = Quaternion.identity();

    final traceX = <double>[];
    final traceY = <double>[];
    final traceGyroMag = <double>[];
    final shots = <_ShotCandidate>[];

    var state = _ReplayState.idle;
    var stateTimer = 0.0;
    var gatherCounter = 0;

    double prevAx = 0, prevAy = 0, prevAz = 0;

    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];

      final gxBc = s.gx - offsetGx;
      final gyBc = s.gy - offsetGy;
      final gzBc = s.gz - offsetGz;

      final rawGyros = [gxBc, gyBc, gzBc];
      final wx = kGyroSignX * rawGyros[kGyroAxisX];
      final wy = kGyroSignY * rawGyros[kGyroAxisY];
      final wz = kGyroSignZ * rawGyros[kGyroAxisZ];

      q = q.integrate(wx, wy, wz, dt);
      final qRel = (qTare.conjugate() * q).normalized();

      final v = qRel.rotateVector(_kBarrelVector);
      final currX = math.atan2(-v[1], v[2]) * kScreenXSign;
      final currY = math.atan2(v[0], v[2]) * kScreenYSign;

      traceX.add(currX);
      traceY.add(currY);
      final rotMag = math.sqrt(wx * wx + wy * wy + wz * wz);
      traceGyroMag.add(rotMag);

      final jerk = (i == 0)
          ? 0.0
          : math.sqrt(
                math.pow(s.ax - prevAx, 2) +
                math.pow(s.ay - prevAy, 2) +
                math.pow(s.az - prevAz, 2),
              ) / dt;
      prevAx = s.ax; prevAy = s.ay; prevAz = s.az;

      switch (state) {
        case _ReplayState.idle:
          if (rotMag < stabilityGyroLimit) {
            state = _ReplayState.arming;
            stateTimer = 0;
          }
          break;
        case _ReplayState.arming:
          if (rotMag > stabilityGyroLimit) {
            state = _ReplayState.idle;
          } else {
            stateTimer += dt * 1000;
            if (stateTimer >= stabilityWindowMs) {
              state = _ReplayState.armed;
            }
          }
          break;
        case _ReplayState.armed:
          if (rotMag > (stabilityGyroLimit * 2.0) || jerk > 20.0) {
            state = _ReplayState.postGather;
            gatherCounter = recoilDurationIdx;
          }
          break;
        case _ReplayState.postGather:
          gatherCounter -= 1;
          if (gatherCounter <= 0) {
            final candidate = _analyzeShot(traceX, traceY);
            if (candidate != null) shots.add(candidate);
            state = _ReplayState.idle;
            stateTimer = 0;
          }
          break;
      }
    }

    final replayShots = <ReplayShot>[];
    for (final c in shots) {
      replayShots.add(ReplayShot(
        breakIndex: c.breakIndex,
        breakTSeconds: c.breakIndex * dt,
        holdX: c.holdX, holdY: c.holdY,
        pressX: c.pressX, pressY: c.pressY,
        recoilX: c.recoilX, recoilY: c.recoilY,
        holdScore: c.holdScore, pressScore: c.pressScore, recoilScore: c.recoilScore,
        elevationScore: c.elevationScore, windageScore: c.windageScore, totalScore: c.totalScore,
        travelDistance: c.travelDistance, peakJerk: c.peakJerk,
        firearmType: session.firearmType.name,
        trainingMode: session.trainingMode.name,
        timestamp: session.date.add(Duration(milliseconds: (c.breakIndex * dt * 1000).round())),
      ));
    }

    // Re-run quaternion integration for target-plane projection (mm offset).
    // Reuse calibration offsets and qTare from the first pass.
    var qProj = Quaternion.identity();
    final frames = <ReplayFrame>[];
    for (int i = 0; i < traceX.length; i++) {
      final s = samples[i];
      final gxBc = s.gx - offsetGx;
      final gyBc = s.gy - offsetGy;
      final gzBc = s.gz - offsetGz;
      final wx = kGyroSignX * gxBc;
      final wy = kGyroSignY * gyBc;
      final wz = kGyroSignZ * gzBc;
      qProj = qProj.integrate(wx, wy, wz, dt);
      final qRel = (qTare.conjugate() * qProj).normalized();
      final proj = projectToTarget(
        barrelOrientation: qRel,
        targetDistanceM: targetDistanceM,
      );
      // Convert from metres to millimetres for target overlay.
      final targetXmm = proj[0] * 1000.0;
      final targetYmm = proj[1] * 1000.0;

      ReplayShot? marker;
      for (final shot in replayShots) {
        if (shot.breakIndex == i) { marker = shot; break; }
      }
      frames.add(ReplayFrame(
        tIndex: i,
        tSeconds: i * dt,
        barrelX: traceX[i],
        barrelY: traceY[i],
        targetXmm: targetXmm,
        targetYmm: targetYmm,
        gyroMagnitude: traceGyroMag[i],
        shotMarker: marker,
      ));
    }

    debugPrint('[REPLAY] finished: frames=${frames.length} shots=${replayShots.length}');
    return ReplayTrace(
      frames: frames,
      shots: replayShots,
      totalDurationSeconds: traceX.length * dt,
      sampleRateHz: 100,
      targetDistanceM: targetDistanceM,
    );
  }

  // --- private helpers ---

  _ShotCandidate? _analyzeShot(List<double> traceX, List<double> traceY) {
    if (traceX.length < totalHistoryNeeded) return null;

    final idxRecoilEnd = traceX.length;
    final idxBreak = idxRecoilEnd - recoilDurationIdx;
    final idxPressStart = idxBreak - pressDurationIdx;
    final idxHoldStart = idxBreak - holdDurationIdx;
    if (idxHoldStart < 0) return null;

    final breakX = traceX[idxBreak];
    final breakY = traceY[idxBreak];

    final holdX = traceX.sublist(idxHoldStart, idxPressStart).map((v) => v - breakX).toList();
    final holdY = traceY.sublist(idxHoldStart, idxPressStart).map((v) => v - breakY).toList();
    final pressX = traceX.sublist(idxPressStart, idxBreak + 1).map((v) => v - breakX).toList();
    final pressY = traceY.sublist(idxPressStart, idxBreak + 1).map((v) => v - breakY).toList();
    final recoilX = traceX.sublist(idxBreak, idxRecoilEnd).map((v) => v - breakX).toList();
    final recoilY = traceY.sublist(idxBreak, idxRecoilEnd).map((v) => v - breakY).toList();

    final totalTravel = _travel(pressX, pressY);
    final pressDeltas = _deltas(pressX, pressY);
    final peakJerk = _peak(pressDeltas);
    final elevTravel = _axisTravel(pressY);
    final windTravel = _axisTravel(pressX);
    final holdDeltas = _deltas(holdX, holdY);
    final recoilDeltas = _deltas(recoilX, recoilY);

    return _ShotCandidate(
      breakIndex: idxBreak,
      holdX: holdX, holdY: holdY,
      pressX: pressX, pressY: pressY,
      recoilX: recoilX, recoilY: recoilY,
      holdScore: _phaseScore(holdDeltas),
      pressScore: _phaseScore(pressDeltas),
      recoilScore: _phaseScore(recoilDeltas),
      elevationScore: _axisScore(elevTravel),
      windageScore: _axisScore(windTravel),
      totalScore: _totalScore(totalTravel, peakJerk, holdDeltas, pressDeltas, recoilDeltas, elevTravel, windTravel),
      travelDistance: totalTravel,
      peakJerk: peakJerk,
    );
  }

  static double _travel(List<double> x, List<double> y) {
    double t = 0;
    for (int i = 1; i < x.length; i++) {
      t += math.sqrt(math.pow(x[i] - x[i - 1], 2) + math.pow(y[i] - y[i - 1], 2));
    }
    return t;
  }
  static double _axisTravel(List<double> v) {
    double t = 0;
    for (int i = 1; i < v.length; i++) {
      t += (v[i] - v[i - 1]).abs();
    }
    return t;
  }
  static List<double> _deltas(List<double> x, List<double> y) {
    final r = <double>[];
    for (int i = 1; i < x.length; i++) {
      r.add(math.sqrt(math.pow(x[i] - x[i - 1], 2) + math.pow(y[i] - y[i - 1], 2)));
    }
    return r;
  }
  static double _peak(List<double> d) => d.isEmpty ? 0 : d.reduce(math.max);
  static double _phaseScore(List<double> deltas) {
    if (deltas.isEmpty) return 100.0;
    final avg = deltas.reduce((a, b) => a + b) / deltas.length;
    return math.max(0.0, math.min(100.0, 100.0 - math.sqrt(avg) * 15.0));
  }
  static double _axisScore(double travel) =>
      math.max(0.0, math.min(100.0, 100.0 - math.sqrt(travel) * 15.0));
  static double _totalScore(
    double totalTravel, double peakJerk,
    List<double> holdDeltas, List<double> pressDeltas, List<double> recoilDeltas,
    double elevTravel, double windTravel,
  ) {
    final travelPenalty = math.sqrt(totalTravel) * 30.0;
    final jerkPenalty = math.sqrt(peakJerk) * 25.0;
    double hp = 0, pp = 0, rp = 0;
    if (holdDeltas.isNotEmpty) hp = math.sqrt(holdDeltas.reduce((a, b) => a + b) / holdDeltas.length) * 10.0;
    if (pressDeltas.isNotEmpty) pp = math.sqrt(pressDeltas.reduce((a, b) => a + b) / pressDeltas.length) * 15.0;
    if (recoilDeltas.isNotEmpty) rp = math.sqrt(recoilDeltas.reduce((a, b) => a + b) / recoilDeltas.length) * 5.0;
    final ep = math.sqrt(elevTravel) * 15.0;
    final wp = math.sqrt(windTravel) * 15.0;
    return math.max(0.0, math.min(100.0, 100.0 - (travelPenalty + jerkPenalty + hp + pp + rp + ep + wp)));
  }

  static List<_MergedSample> _mergeAccelGyro(SessionLog session) {
    // BUG FIX: timestamps are epoch ms (e.g. 1770000000000), NOT time-since-start.
    // Using (p.x / dt).round() as bucket produces bucket ~1.77e14 per sample,
    // all unique, so gyro and accel never match.
    //
    // Fix: pair by LIST INDEX. In the isolate, gyroX[i], gyroY[i], gyroZ[i],
    // accelX[i], accelY[i], accelZ[i] are ALL created at the same timestamp
    // in the same loop iteration (lines 963-968 of sensor_data_isolate.dart).
    // So index i is the correct sync point.
    final len = session.gyroX.length;
    if (len == 0) return [];
    final result = <_MergedSample>[];
    for (int i = 0; i < len; i++) {
      result.add(_MergedSample(
        bucket: i,
        gx: session.gyroX[i].y,
        gy: session.gyroY[i].y,
        gz: session.gyroZ[i].y,
        ax: session.accelX[i].y,
        ay: session.accelY[i].y,
        az: session.accelZ[i].y,
      ));
    }
    return result;
  }
}

enum _ReplayState { idle, arming, armed, postGather }

class _MergedSample {
  final int bucket;
  final double gx, gy, gz, ax, ay, az;
  const _MergedSample({
    required this.bucket,
    required this.gx, required this.gy, required this.gz,
    required this.ax, required this.ay, required this.az,
  });
}

class _ShotCandidate {
  final int breakIndex;
  final List<double> holdX, holdY, pressX, pressY, recoilX, recoilY;
  final double holdScore, pressScore, recoilScore;
  final double elevationScore, windageScore, totalScore;
  final double travelDistance, peakJerk;
  const _ShotCandidate({
    required this.breakIndex,
    required this.holdX, required this.holdY,
    required this.pressX, required this.pressY,
    required this.recoilX, required this.recoilY,
    required this.holdScore, required this.pressScore, required this.recoilScore,
    required this.elevationScore, required this.windageScore, required this.totalScore,
    required this.travelDistance, required this.peakJerk,
  });
}
