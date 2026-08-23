// ============================================
// Test file: test/unit/services/trajectory/quaternion_test.dart
// ============================================
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/services/trajectory/quaternion.dart';

void main() {
  group('Quaternion', () {
    test('identity quaternion equals [1, 0, 0, 0]', () {
      final q = Quaternion.identity();
      expect(q.w, 1.0);
      expect(q.x, 0.0);
      expect(q.y, 0.0);
      expect(q.z, 0.0);
    });

    test('multiply: i * j = k', () {
      // Hamilton convention: i*j = k, j*k = i, k*i = j
      final i = Quaternion(0, 1, 0, 0);
      final j = Quaternion(0, 0, 1, 0);
      final k = i * j;
      expect(k.w, closeTo(0, 1e-9));
      expect(k.x, closeTo(0, 1e-9));
      expect(k.y, closeTo(0, 1e-9));
      expect(k.z, closeTo(1.0, 1e-9));
    });

    test('normalize: zero quaternion returns identity', () {
      final q = Quaternion(0, 0, 0, 0);
      final n = q.normalized();
      expect(n.w, 1.0);
      expect(n.x, 0.0);
      expect(n.y, 0.0);
      expect(n.z, 0.0);
    });

    test('conjugate negates vector parts', () {
      final q = Quaternion(0.5, 0.5, 0.5, 0.5);
      final c = q.conjugate();
      expect(c.w, 0.5);
      expect(c.x, -0.5);
      expect(c.y, -0.5);
      expect(c.z, -0.5);
    });

    test('integrate: small rotation around z gives nearly-z result', () {
      final q = Quaternion.identity();
      // 0.1 rad/s for 0.01s = 0.001 rad rotation around z
      final rotated = q.integrate(0, 0, 0.1, 0.01);
      // After small rotation around z: cos(0.0005) ≈ 1, sin(0.0005) ≈ 0.0005
      expect(rotated.w, closeTo(0.99999987, 1e-6));
      expect(rotated.z, closeTo(0.0005, 1e-4));
    });

    test('rotateVector: barrel pointing +Z rotated 90deg around Y points to +X', () {
      // Rotate +Z by 90deg around +Y axis: right-handed Hamilton gives +X
      // (matches the live-tracking _quatRotateVector in sensor_data_isolate.dart)
      final q = Quaternion.fromAxisAngle(0, 1, 0, 1.5707963); // 90deg
      final v = q.rotateVector([0, 0, 1]);
      expect(v[0], closeTo(1.0, 1e-4));
      expect(v[1], closeTo(0.0, 1e-4));
      expect(v[2], closeTo(0.0, 1e-4));
    });

    test('fromAccel: gravity-aligned accel returns identity', () {
      // Accelerometer at rest pointing up: az = +1g, ax = ay = 0
      final q = Quaternion.fromAccel(0, 0, 1);
      // The world up = +Z, so identity orientation (no rotation needed)
      expect(q.w, closeTo(1.0, 1e-4));
      expect(q.x, closeTo(0.0, 1e-4));
      expect(q.y, closeTo(0.0, 1e-4));
      expect(q.z, closeTo(0.0, 1e-4));
    });
  });
}
