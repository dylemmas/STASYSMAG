// ============================================
// File: services/trajectory/replay_models.dart
// Offline post-shot replay data models. Pure data, no logic.
// ============================================

/// A single per-sample snapshot in the reconstructed barrel trace.
class ReplayFrame {
  final int tIndex;
  final double tSeconds;
  /// Barrel angular displacement in radians (atan2 projection).
  final double barrelX;
  final double barrelY;
  /// Barrel target-plane offset in millimeters at the configured distance.
  final double targetXmm;
  final double targetYmm;
  final double gyroMagnitude;
  final ReplayShot? shotMarker;

  const ReplayFrame({
    required this.tIndex,
    required this.tSeconds,
    required this.barrelX,
    required this.barrelY,
    required this.targetXmm,
    required this.targetYmm,
    required this.gyroMagnitude,
    this.shotMarker,
  });
}

/// Reconstructed per-shot data: segments + scores + factor breakdown.
class ReplayShot {
  final int breakIndex;
  final double breakTSeconds;
  final List<double> holdX, holdY, pressX, pressY, recoilX, recoilY;
  final double holdScore, pressScore, recoilScore;
  final double elevationScore, windageScore, totalScore;
  final double travelDistance, peakJerk;
  final String firearmType, trainingMode;
  final DateTime timestamp;

  const ReplayShot({
    required this.breakIndex,
    required this.breakTSeconds,
    required this.holdX, required this.holdY,
    required this.pressX, required this.pressY,
    required this.recoilX, required this.recoilY,
    required this.holdScore, required this.pressScore, required this.recoilScore,
    required this.elevationScore, required this.windageScore, required this.totalScore,
    required this.travelDistance, required this.peakJerk,
    required this.firearmType, required this.trainingMode,
    required this.timestamp,
  });
}

/// Result of replaying a session.
class ReplayTrace {
  final List<ReplayFrame> frames;
  final List<ReplayShot> shots;
  final double totalDurationSeconds;
  final int sampleRateHz;
  /// Target distance used for this replay (metres). Read from settings.
  final double targetDistanceM;

  const ReplayTrace({
    required this.frames,
    required this.shots,
    required this.totalDurationSeconds,
    required this.sampleRateHz,
    required this.targetDistanceM,
  });

  bool get hasShots => shots.isNotEmpty;
  bool get isEmpty => frames.isEmpty;
}
