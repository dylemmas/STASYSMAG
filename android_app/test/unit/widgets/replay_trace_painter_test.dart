// ============================================
// Test: test/unit/widgets/replay_trace_painter_test.dart
// ============================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/widgets/replay_trace_painter.dart';
import 'package:ssa_app/services/trajectory/replay_models.dart';

ReplayFrame _frame(int idx, double x, double y, {ReplayShot? marker}) {
  return ReplayFrame(
    tIndex: idx,
    tSeconds: idx / 100.0,
    barrelX: x,
    barrelY: y,
    targetXmm: 0.0,
    targetYmm: 0.0,
    gyroMagnitude: 0.1,
    shotMarker: marker,
  );
}

ReplayShot _shot(int idx, double score) {
  return ReplayShot(
    breakIndex: idx,
    breakTSeconds: idx / 100.0,
    holdX: const [],
    holdY: const [],
    pressX: const [],
    pressY: const [],
    recoilX: const [],
    recoilY: const [],
    holdScore: score,
    pressScore: score,
    recoilScore: score,
    elevationScore: score,
    windageScore: score,
    totalScore: score,
    travelDistance: 1.0,
    peakJerk: 0.5,
    firearmType: 'pistol',
    trainingMode: 'dryFire',
    timestamp: DateTime(2026, 6, 6, 12, 0, 0),
  );
}

Color _scoreColor(double score) => Colors.green;

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 300, height: 300, child: child),
    ),
  );
}

void main() {
  group('ReplayTracePainter', () {
    testWidgets('renders without throwing on empty trace', (tester) async {
      final empty = ReplayTrace(
        frames: const [],
        shots: const [],
        totalDurationSeconds: 0,
        sampleRateHz: 100,
        targetDistanceM: 10.0,
      );

      await tester.pumpWidget(
        _wrap(CustomPaint(
          painter: ReplayTracePainter(
            trace: empty,
            selectedShot: null,
            getScoreColor: _scoreColor,
          ),
          size: const Size(300, 300),
        )),
      );
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without throwing on populated trace with shots',
        (tester) async {
      final s1 = _shot(50, 88.0);
      final s2 = _shot(150, 72.0);
      final trace = ReplayTrace(
        frames: [
          for (int i = 0; i < 200; i++)
            _frame(i, (i - 100) / 5000.0, (i % 30 - 15) / 8000.0,
                marker: i == 50 ? s1 : (i == 150 ? s2 : null)),
        ],
        shots: [s1, s2],
        totalDurationSeconds: 2.0,
        sampleRateHz: 100,
        targetDistanceM: 10.0,
      );

      await tester.pumpWidget(
        _wrap(CustomPaint(
          painter: ReplayTracePainter(
            trace: trace,
            selectedShot: s1,
            getScoreColor: _scoreColor,
          ),
          size: const Size(300, 300),
        )),
      );
      expect(tester.takeException(), isNull);
    });

    test('shouldRepaint returns true when trace changes', () {
      final t1 = ReplayTrace(frames: const [], shots: const [],
          totalDurationSeconds: 0, sampleRateHz: 100, targetDistanceM: 10.0);
      final t2 = ReplayTrace(
        frames: [_frame(0, 0, 0)],
        shots: const [],
        totalDurationSeconds: 0,
        sampleRateHz: 100,
        targetDistanceM: 10.0,
      );

      final p1 = ReplayTracePainter(
        trace: t1, selectedShot: null, getScoreColor: _scoreColor,
      );
      final p2 = ReplayTracePainter(
        trace: t2, selectedShot: null, getScoreColor: _scoreColor,
      );
      expect(p2.shouldRepaint(p1), isTrue);
    });

    test('shouldRepaint returns false when trace unchanged', () {
      final t = ReplayTrace(
        frames: [_frame(0, 0.01, 0.02)],
        shots: const [],
        totalDurationSeconds: 0.01,
        sampleRateHz: 100,
        targetDistanceM: 10.0,
      );
      final p1 = ReplayTracePainter(
        trace: t, selectedShot: null, getScoreColor: _scoreColor,
      );
      final p2 = ReplayTracePainter(
        trace: t, selectedShot: null, getScoreColor: _scoreColor,
      );
      expect(p2.shouldRepaint(p1), isFalse);
    });
  });
}
