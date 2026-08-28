// ============================================
// File: services/trajectory/quaternion.dart
// Pure quaternion math, no Flutter dependency.
// Extracted from providers/sensor_data_isolate.dart (was inline _Quaternion).
// Aligned with Python stasysz.py conventions.
// ============================================
import 'dart:math' as math;

/// Hamilton-convention quaternion. Operations are non-mutating.
class Quaternion {
  final double w, x, y, z;

  const Quaternion(this.w, this.x, this.y, this.z);

  factory Quaternion.identity() => const Quaternion(1.0, 0.0, 0.0, 0.0);

  Quaternion normalized() {
    final n = math.sqrt(w * w + x * x + y * y + z * z);
    if (n < 1e-10) return Quaternion.identity();
    return Quaternion(w / n, x / n, y / n, z / n);
  }

  Quaternion conjugate() => Quaternion(w, -x, -y, -z);

  /// Hamilton product a * b.
  Quaternion operator *(Quaternion b) => Quaternion(
        w * b.w - x * b.x - y * b.y - z * b.z,
        w * b.x + x * b.w + y * b.z - z * b.y,
        w * b.y - x * b.z + y * b.w + z * b.x,
        w * b.z + x * b.y - y * b.x + z * b.w,
      );

  /// Integrate angular velocity [wx,wy,wz] (rad/s) over dt seconds.
  /// First-order quaternion integration with renormalize.
  Quaternion integrate(double wx, double wy, double wz, double dt) {
    final qDot = Quaternion(
      -0.5 * (x * wx + y * wy + z * wz),
      0.5 * (w * wx + y * wz - z * wy),
      0.5 * (w * wy - x * wz + z * wx),
      0.5 * (w * wz + x * wy - y * wx),
    );
    return Quaternion(
      w + qDot.w * dt,
      x + qDot.x * dt,
      y + qDot.y * dt,
      z + qDot.z * dt,
    ).normalized();
  }

  /// Rotate vector [vx,vy,vz] by this quaternion (assumes unit quaternion).
  List<double> rotateVector(List<double> v) {
    final pure = Quaternion(0.0, v[0], v[1], v[2]);
    final r = this * pure * conjugate();
    return [r.x, r.y, r.z];
  }

  /// Construct from axis-angle. Axis need not be normalized (we normalize internally).
  factory Quaternion.fromAxisAngle(double ax, double ay, double az, double angle) {
    final n = math.sqrt(ax * ax + ay * ay + az * az);
    if (n < 1e-10) return Quaternion.identity();
    final nx = ax / n, ny = ay / n, nz = az / n;
    final s = math.sin(angle / 2.0);
    return Quaternion(math.cos(angle / 2.0), nx * s, ny * s, nz * s);
  }

  /// Construct from accelerometer reading (gravity vector). Returns the
  /// orientation that aligns the world up [0,0,1] with the measured gravity.
  /// Mirrors the inline `_quatFromAccel` from sensor_data_isolate.dart.
  factory Quaternion.fromAccel(double ax, double ay, double az) {
    final n = math.sqrt(ax * ax + ay * ay + az * az);
    if (n < 1e-6) return Quaternion.identity();
    ax /= n; ay /= n; az /= n;

    final dot = az; // [ax,ay,az] · [0,0,1]

    if (dot >= 0.9999) return Quaternion.identity();

    if (dot <= -0.9999) {
      // Pointing straight down — pick any perpendicular axis
      var axis = [1.0, 0.0, 0.0];
      var cross = ax * axis[2] - az * axis[0];
      if (cross.abs() < 1e-6) {
        axis = [0.0, 1.0, 0.0];
        cross = ax * axis[2] - az * axis[0];
      }
      final len = cross.abs();
      if (len > 1e-6) {
        axis = [
          axis[1] * az - axis[2] * ay,
          axis[2] * ax - axis[0] * az,
          axis[0] * ay - axis[1] * ax,
        ];
        final nn = math.sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
        if (nn > 1e-6) {
          axis = [axis[0] / nn, axis[1] / nn, axis[2] / nn];
        }
      }
      return Quaternion(0.0, axis[0], axis[1], axis[2]);
    }

    final axisX = -ay;
    final axisY = ax;
    final axisZ = 0.0;
    var axisXn = axisX, axisYn = axisY, axisZn = axisZ;
    final an = math.sqrt(axisXn * axisXn + axisYn * axisYn + axisZn * axisZn);
    if (an > 1e-6) {
      axisXn /= an; axisYn /= an; axisZn /= an;
    } else {
      axisXn = 1.0; axisYn = 0.0; axisZn = 0.0;
    }

    final angle = math.acos(dot.clamp(-1.0, 1.0));
    return Quaternion.fromAxisAngle(axisXn, axisYn, axisZn, angle);
  }
}
