// ============================================
// File: services/trajectory/projection.dart
// Pure barrel-projection math, no Flutter dependency.
// Extracted from sensor_data_isolate.dart (was inline _orientGun + _projectToTarget).
// Used by BOTH live tracking and post-shot replay so they share one source of truth.
// ============================================
import 'quaternion.dart';
export 'quaternion.dart';

/// Project a barrel ray from origin to a target plane at distance [targetDistanceM].
///
/// `barrelOrientation` is the orientation of the gun body. The barrel is assumed
/// to point along the gun's local +Z axis. We rotate [0,0,1] by this orientation
/// to get the world-space barrel direction, then scale to `targetDistanceM`.
///
/// Returns `[x, y, z]` in world coordinates where the bullet would intersect a
/// target plane perpendicular to the barrel at that range.
List<double> projectToTarget({
  required Quaternion barrelOrientation,
  required double targetDistanceM,
}) {
  final direction = barrelOrientation.rotateVector([0, 0, 1]);
  return [
    direction[0] * targetDistanceM,
    direction[1] * targetDistanceM,
    direction[2] * targetDistanceM,
  ];
}
