import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/services/trajectory/replay_models.dart';

void main() {
  test('ReplayFrame default fields', () {
    const f = ReplayFrame(
      tIndex: 0, tSeconds: 0.0,
      barrelX: 0.0, barrelY: 0.0,
      targetXmm: 0.0, targetYmm: 0.0,
      gyroMagnitude: 0.0,
    );
    expect(f.tIndex, 0);
    expect(f.shotMarker, isNull);
  });

  test('ReplayShot holds 6 segment lists and a total score', () {
    final s = ReplayShot(
      breakIndex: 170, breakTSeconds: 1.7,
      holdX: const [0.0], holdY: const [0.0],
      pressX: const [0.0], pressY: const [0.0],
      recoilX: const [0.0], recoilY: const [0.0],
      holdScore: 95, pressScore: 90, recoilScore: 85,
      elevationScore: 92, windageScore: 88, totalScore: 90,
      travelDistance: 0.05, peakJerk: 0.01,
      firearmType: 'pistol', trainingMode: 'dryFire',
      timestamp: DateTime(2024, 1, 1),
    );
    expect(s.totalScore, 90);
    expect(s.holdX.length, 1);
    expect(s.pressY.length, 1);
    expect(s.recoilX.length, 1);
  });

  test('ReplayTrace.isEmpty true when frames empty', () {
    const t = ReplayTrace(frames: [], shots: [], totalDurationSeconds: 0, sampleRateHz: 100, targetDistanceM: 10.0);
    expect(t.isEmpty, true);
    expect(t.hasShots, false);
  });

  test('ReplayTrace.hasShots true when shots present', () {
    final t = ReplayTrace(
      frames: const [],
      shots: [
        ReplayShot(
          breakIndex: 0, breakTSeconds: 0,
          holdX: const [], holdY: const [], pressX: const [], pressY: const [], recoilX: const [], recoilY: const [],
          holdScore: 0, pressScore: 0, recoilScore: 0,
          elevationScore: 0, windageScore: 0, totalScore: 0,
          travelDistance: 0, peakJerk: 0,
          firearmType: 'pistol', trainingMode: 'dryFire',
          timestamp: DateTime(2024, 1, 1),
        ),
      ],
      totalDurationSeconds: 0,
      sampleRateHz: 100,
      targetDistanceM: 10.0,
    );
    expect(t.isEmpty, true);
    expect(t.hasShots, true);
  });
}
