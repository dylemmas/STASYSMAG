// ============================================
// Test file: test/unit/services/trajectory/projection_test.dart
// ============================================
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/services/trajectory/projection.dart';

void main() {
  group('projectToTarget', () {
    test('identity orientation, 10m distance: bullet goes straight to (0,10)', () {
      // Identity orientation: barrel points along +Z.
      // At distance d along +Z, bullet is at (0, 0, d).
      final hit = projectToTarget(
        barrelOrientation: Quaternion.identity(),
        targetDistanceM: 10.0,
      );
      expect(hit[0], closeTo(0.0, 1e-9));
      expect(hit[1], closeTo(0.0, 1e-9));
      expect(hit[2], closeTo(10.0, 1e-9));
    });

    test('barrel yawed 5deg: hit offset on +X at 10m', () {
      // Yaw 5° around +Y: right-handed Hamilton rotates [0,0,1] toward +X.
      // hit = direction * d where direction = rotate([0,0,1]).
      //   x = sin(5°) * 10 ≈ 0.8716
      //   z = cos(5°) * 10 ≈ 9.9624
      final q = Quaternion.fromAxisAngle(0, 1, 0, 0.0872665); // 5 deg
      final hit = projectToTarget(
        barrelOrientation: q,
        targetDistanceM: 10.0,
      );
      expect(hit[0], closeTo(0.8716, 1e-3));
      expect(hit[1], closeTo(0.0, 1e-9));
      expect(hit[2], closeTo(9.9624, 1e-3));
    });

    test('barrel pitched 5deg around +X: hit offset on -Y at 10m', () {
      // Pitch 5° around +X (right-handed Hamilton): rotates [0,0,1] toward -Y.
      //   y = -sin(5°) * 10 ≈ -0.8716
      //   z = cos(5°) * 10 ≈ 9.9624
      final q = Quaternion.fromAxisAngle(1, 0, 0, 0.0872665);
      final hit = projectToTarget(
        barrelOrientation: q,
        targetDistanceM: 10.0,
      );
      expect(hit[0], closeTo(0.0, 1e-9));
      expect(hit[1], closeTo(-0.8716, 1e-3));
      expect(hit[2], closeTo(9.9624, 1e-3));
    });

    test('returns 3-element list', () {
      final hit = projectToTarget(
        barrelOrientation: Quaternion.identity(),
        targetDistanceM: 5.0,
      );
      expect(hit.length, 3);
    });
  });
}
