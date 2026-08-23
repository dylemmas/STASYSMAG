// ============================================
// File: services/trajectory/target_geometry.dart
// Pure SCATT-target geometry. No Flutter dependency.
// Used by the TrajectoryCanvas painter (Task 9) AND for SCATT-style ring scoring.
// ============================================
import 'dart:math' as math;

/// 2D offset on the target plane, in millimeters.
class OffsetMm {
  final double x, y;
  const OffsetMm(this.x, this.y);

  double get magnitude => math.sqrt(x * x + y * y);
}

/// SCATT-style concentric-ring target.
///
/// Default constructor is the standard 10m air-rifle target:
/// 10 rings scored 10 → 1, 10-ring diameter 45.5 mm, 1-ring diameter ~112.5 mm.
/// Ring radii are spaced evenly between the inner and outer radius (10 bands).
class ScattTargetGeometry {
  /// Score per ring, indexed 0..9 (ring 0 is the innermost = 10).
  final List<int> ringScores;

  /// Radius of the 10-ring (innermost scoring ring) in mm.
  final double tenRingRadiusMm;

  /// Radius of the 1-ring (outermost scoring ring) in mm.
  final double oneRingRadiusMm;

  /// Total number of scoring rings (typically 10 for SCATT).
  final int ringCount;

  const ScattTargetGeometry({
    required this.ringScores,
    required this.tenRingRadiusMm,
    required this.oneRingRadiusMm,
    required this.ringCount,
  });

  /// Private no-arg const constructor supplying the standard SCATT 10m defaults.
  const ScattTargetGeometry._default10m()
      : ringScores = const [10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
        tenRingRadiusMm = 22.75,
        oneRingRadiusMm = 56.25,
        ringCount = 10;

  /// Standard SCATT 10m air-rifle paper target:
  /// 10-ring diameter 45.5 mm (so radius 22.75 mm).
  /// 1-ring diameter 112.5 mm (radius 56.25 mm).
  /// 10 scoring rings, scored 10 down to 1.
  const factory ScattTargetGeometry.default10m() = ScattTargetGeometry._default10m;

  /// Compute the SCATT-style ring score for a hit offset.
  ///
  /// Returns 0 if the hit is outside the 1-ring (a miss).
  /// Boundaries are inclusive toward the *higher* score (closer to center),
  /// matching how SCATT optical sensors report ring scores.
  int scoreRing({required OffsetMm offsetMm}) {
    final r = offsetMm.magnitude;
    if (r > oneRingRadiusMm) return 0;

    // Linear interpolation between 10-ring and 1-ring radii.
    // 10 rings total → 9 boundaries between them.
    final span = oneRingRadiusMm - tenRingRadiusMm;
    final step = span / (ringCount - 1); // distance per ring boundary

    for (int i = 0; i < ringCount; i++) {
      final boundary = tenRingRadiusMm + step * i;
      if (r <= boundary) {
        return ringScores[i];
      }
    }
    return ringScores.last; // hit at outer edge still scores 1
  }
}
