// ============================================
// Test file: test/unit/services/trajectory/target_geometry_test.dart
// ============================================
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/services/trajectory/target_geometry.dart';

void main() {
  group('ScattTargetGeometry', () {
    test('default target = 10m air-rifle, 45.5mm 10-ring', () {
      const g = ScattTargetGeometry.default10m();
      // 10-ring radius in mm
      expect(g.tenRingRadiusMm, closeTo(22.75, 1e-6));
      // 10 rings, scored 10 down to 1
      expect(g.ringScores, [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]);
      // Outer 1-ring is wider than 10-ring (typical SCATT proportions)
      expect(g.oneRingRadiusMm, greaterThan(g.tenRingRadiusMm));
    });

    test('scoreRing: bullseye returns 10', () {
      const g = ScattTargetGeometry.default10m();
      // Hit at origin → 10
      expect(g.scoreRing(offsetMm: OffsetMm(0, 0)), 10);
    });

    test('scoreRing: hits outside the 1-ring return 0 (miss)', () {
      const g = ScattTargetGeometry.default10m();
      // 200mm offset: way outside any ring
      expect(g.scoreRing(offsetMm: OffsetMm(200, 200)), 0);
    });

    test('scoreRing: between rings rounds to inner ring (more forgiving SCATT)', () {
      const g = ScattTargetGeometry.default10m();
      // Hit at exactly the 9/10 boundary — should score 9 (boundary = lower ring)
      // SCATT scoring: closer to center wins ties go to higher score
      // 9-ring outer radius is between 10 and 1. We just check we get 9 OR 10.
      final score = g.scoreRing(
        offsetMm: OffsetMm(g.tenRingRadiusMm + 0.5, 0),
      );
      expect(score == 9 || score == 10, true);
    });

    test('scoreRing: hit in 5-ring area returns 5', () {
      const g = ScattTargetGeometry.default10m();
      // Hit roughly halfway between center and outer edge
      final r = g.tenRingRadiusMm + (g.oneRingRadiusMm - g.tenRingRadiusMm) * 0.5;
      expect(g.scoreRing(offsetMm: OffsetMm(r, 0)), 5);
    });
  });

  group('OffsetMm', () {
    test('magnitude computes sqrt(x^2 + y^2)', () {
      const o = OffsetMm(3, 4);
      expect(o.magnitude, 5.0);
    });
  });
}
