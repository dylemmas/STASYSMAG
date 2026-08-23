// ============================================
// File: models/data_models.dart
// ============================================

// --- Firearm & Training Mode Enums ---

enum FirearmType {
  pistol('Pistol'),
  rifle('Rifle'),
  shotgun('Shotgun'),
  archery('Archery');

  final String displayName;
  const FirearmType(this.displayName);

  static FirearmType fromString(String value) {
    return FirearmType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FirearmType.pistol,
    );
  }
}

enum TrainingMode {
  dryFire('Dry Fire'),
  liveFire('Live Fire');

  final String displayName;
  const TrainingMode(this.displayName);

  static TrainingMode fromString(String value) {
    return TrainingMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TrainingMode.dryFire,
    );
  }
}

enum MountDirection {
  forward('FW'),
  backward('BW');

  final String shortCode;
  const MountDirection(this.shortCode);

  static MountDirection fromString(String value) {
    return MountDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MountDirection.forward,
    );
  }
}

enum MountPosition {
  top('TOP'),
  bottom('BOT'),
  left('LEFT'),
  right('RIGHT');

  final String displayName;
  const MountPosition(this.displayName);

  static MountPosition fromString(String value) {
    return MountPosition.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MountPosition.top,
    );
  }
}

// --- Shot Result Model (for scoring & analysis) ---
class ShotResult {
  final DateTime timestamp;
  final double totalScore;       // 0-100
  final double holdScore;       // 0-100
  final double pressScore;       // 0-100
  final double recoilScore;      // 0-100
  final double elevationScore;   // 0-100
  final double windageScore;     // 0-100
  final double travelDistance;   // radians
  final double peakJerk;         // max single jump
  final FirearmType firearmType;
  final TrainingMode trainingMode;

  // Phase trace data — normalized to break point (m radians)
  final List<double>? holdX;
  final List<double>? holdY;
  final List<double>? pressX;
  final List<double>? pressY;
  final List<double>? recoilX;
  final List<double>? recoilY;

  ShotResult({
    required this.timestamp,
    required this.totalScore,
    required this.holdScore,
    required this.pressScore,
    required this.recoilScore,
    required this.elevationScore,
    required this.windageScore,
    required this.travelDistance,
    required this.peakJerk,
    required this.firearmType,
    required this.trainingMode,
    this.holdX,
    this.holdY,
    this.pressX,
    this.pressY,
    this.recoilX,
    this.recoilY,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'totalScore': totalScore,
      'holdScore': holdScore,
      'pressScore': pressScore,
      'recoilScore': recoilScore,
      'elevationScore': elevationScore,
      'windageScore': windageScore,
      'travelDistance': travelDistance,
      'peakJerk': peakJerk,
      'firearmType': firearmType.name,
      'trainingMode': trainingMode.name,
      'holdX': holdX,
      'holdY': holdY,
      'pressX': pressX,
      'pressY': pressY,
      'recoilX': recoilX,
      'recoilY': recoilY,
    };
  }

  factory ShotResult.fromMap(Map<String, dynamic> map) {
    return ShotResult(
      timestamp: DateTime.parse(map['timestamp']),
      totalScore: (map['totalScore'] as num).toDouble(),
      holdScore: (map['holdScore'] as num).toDouble(),
      pressScore: (map['pressScore'] as num).toDouble(),
      recoilScore: (map['recoilScore'] as num).toDouble(),
      elevationScore: (map['elevationScore'] as num).toDouble(),
      windageScore: (map['windageScore'] as num).toDouble(),
      travelDistance: (map['travelDistance'] as num).toDouble(),
      peakJerk: (map['peakJerk'] as num).toDouble(),
      firearmType: FirearmType.fromString(map['firearmType'] ?? 'pistol'),
      trainingMode: TrainingMode.fromString(map['trainingMode'] ?? 'dryFire'),
      holdX: _listFromDynamic(map['holdX']),
      holdY: _listFromDynamic(map['holdY']),
      pressX: _listFromDynamic(map['pressX']),
      pressY: _listFromDynamic(map['pressY']),
      recoilX: _listFromDynamic(map['recoilX']),
      recoilY: _listFromDynamic(map['recoilY']),
    );
  }

  static List<double>? _listFromDynamic(dynamic list) {
    if (list == null) return null;
    return (list as List).map((e) => (e as num).toDouble()).toList();
  }
}

// --- DataPoint & SessionData ---

class DataPoint {
  final double x; // Timestamp
  final double y; // Values

  DataPoint(this.x, this.y);

  DataPoint.fromTimestamp({required double timestamp, required double value})
      : x = timestamp,
        y = value;

  double get timestamp => x;
  double get value => y;

  Map<String, dynamic> toMap() {
    return {'x': x, 'y': y};
  }

  factory DataPoint.fromMap(Map<String, dynamic> map) {
    return DataPoint(map['x'], map['y']);
  }
}

class SessionData {
  final String id;
  final DateTime date;
  final int duration; // dalam menit
  final String title;

  SessionData({
    required this.id,
    required this.date,
    required this.duration,
    required this.title,
  });
}
