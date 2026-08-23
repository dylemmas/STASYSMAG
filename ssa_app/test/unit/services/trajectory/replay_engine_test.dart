import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/data_models.dart';
import 'package:ssa_app/providers/session_logger.dart' show SessionLog;
import 'package:ssa_app/services/trajectory/replay_engine.dart';

/// Build a session with a deterministic "shot-like" motion profile:
///
/// - Samples 0..199: quiet (rotMag < 4) — this is the "arming" period (200ms)
/// - Samples 200..209: rotMag > 8 (trigger, exceeds 2x stability limit)
/// - Samples 210..end: quiet again (postGather completes after 10 samples)
///
/// Result: engine transitions idle → arming (completes) → armed (triggered at 200)
/// → postGather (10 samples, completes at ~210) → idle. We get 1 shot at break=210-10=200.
///
/// The state machine's postGather decrement of 10 samples means: after trigger,
/// engine waits for gatherCounter (10) to reach 0, then analyzes shot with
/// current traceX.length as idxRecoilEnd. So break = idxRecoilEnd - 10.
SessionLog _buildSession({int sampleCount = 400}) {
  final gx = <DataPoint>[], gy = <DataPoint>[], gz = <DataPoint>[];
  final ax = <DataPoint>[], ay = <DataPoint>[], az = <DataPoint>[];
  for (int i = 0; i < sampleCount; i++) {
    final t = i * 0.01;
    double g = 0.0;
    if (i >= 200 && i < 210) g = 10.0; // trigger
    gx.add(DataPoint(t, g));
    gy.add(DataPoint(t, 0.0));
    gz.add(DataPoint(t, 0.0));
    ax.add(DataPoint(t, 0.0));
    ay.add(DataPoint(t, 0.0));
    az.add(DataPoint(t, 0.0));
  }
  return SessionLog(
    id: 'test',
    date: DateTime(2024, 1, 1),
    duration: sampleCount * 0.01,
    gyroX: gx, gyroY: gy, gyroZ: gz,
    accelX: ax, accelY: ay, accelZ: az,
    firearmType: FirearmType.pistol,
    trainingMode: TrainingMode.dryFire,
  );
}

void main() {
  group('ReplayEngine.replay', () {
    test('empty session produces empty trace', () {
      final engine = ReplayEngine();
      final s = SessionLog(
        id: 'x', date: DateTime(2024), duration: 0,
        gyroX: const [], gyroY: const [], gyroZ: const [],
        accelX: const [], accelY: const [], accelZ: const [],
      );
      final trace = engine.replay(s);
      expect(trace.frames, isEmpty);
      expect(trace.shots, isEmpty);
      expect(trace.totalDurationSeconds, 0);
    });

    test('session with no detectable motion produces 0 shots', () {
      final engine = ReplayEngine();
      final trace = engine.replay(_buildSession(sampleCount: 200));
      expect(trace.shots, isEmpty);
      // 200 samples = 2.0 sec
      expect(trace.totalDurationSeconds, closeTo(2.0, 0.05));
      expect(trace.frames.length, 200);
    });

    test('session with single shot-like motion produces 1 shot', () {
      final engine = ReplayEngine();
      final trace = engine.replay(_buildSession(sampleCount: 400));
      expect(trace.shots.length, 1, reason: 'expected exactly 1 shot, got ${trace.shots.length}');
      final shot = trace.shots.first;
      expect(shot.breakIndex, greaterThan(0));
      expect(shot.holdX.length, greaterThan(0));
      expect(shot.pressX.length, greaterThan(0));
      expect(shot.recoilX.length, greaterThan(0));
      expect(shot.totalScore, greaterThanOrEqualTo(0));
      expect(shot.totalScore, lessThanOrEqualTo(100));
    });

    test('ReplayFrame marker aligns with shot breakIndex', () {
      final engine = ReplayEngine();
      final trace = engine.replay(_buildSession(sampleCount: 400));
      expect(trace.shots.length, 1);
      final shot = trace.shots.first;
      final marked = trace.frames.firstWhere((f) => f.shotMarker != null);
      expect(marked.tIndex, shot.breakIndex);
    });
  });
}
