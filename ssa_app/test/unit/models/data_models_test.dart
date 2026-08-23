// ============================================
// Test file: test/unit/models/data_models_test.dart
// ============================================
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/models/data_models.dart';

void main() {
  group('FirearmType', () {
    test('fromString returns correct enum for valid input', () {
      expect(FirearmType.fromString('pistol'), FirearmType.pistol);
      expect(FirearmType.fromString('rifle'), FirearmType.rifle);
      expect(FirearmType.fromString('shotgun'), FirearmType.shotgun);
      expect(FirearmType.fromString('archery'), FirearmType.archery);
    });

    test('fromString returns pistol for invalid input', () {
      expect(FirearmType.fromString('unknown'), FirearmType.pistol);
      expect(FirearmType.fromString(''), FirearmType.pistol);
    });

    test('displayName returns human-readable name', () {
      expect(FirearmType.pistol.displayName, 'Pistol');
      expect(FirearmType.rifle.displayName, 'Rifle');
      expect(FirearmType.shotgun.displayName, 'Shotgun');
      expect(FirearmType.archery.displayName, 'Archery');
    });
  });

  group('TrainingMode', () {
    test('fromString returns correct enum for valid input', () {
      expect(TrainingMode.fromString('dryFire'), TrainingMode.dryFire);
      expect(TrainingMode.fromString('liveFire'), TrainingMode.liveFire);
    });

    test('fromString returns dryFire for invalid input', () {
      expect(TrainingMode.fromString('unknown'), TrainingMode.dryFire);
      expect(TrainingMode.fromString(''), TrainingMode.dryFire);
    });

    test('displayName returns human-readable name', () {
      expect(TrainingMode.dryFire.displayName, 'Dry Fire');
      expect(TrainingMode.liveFire.displayName, 'Live Fire');
    });
  });

  group('DataPoint', () {
    test('creates with x and y values', () {
      final point = DataPoint(1.5, 2.5);
      expect(point.x, 1.5);
      expect(point.y, 2.5);
      expect(point.timestamp, 1.5);
      expect(point.value, 2.5);
    });

    test('creates from timestamp and value', () {
      final point = DataPoint.fromTimestamp(timestamp: 10.0, value: 20.0);
      expect(point.x, 10.0);
      expect(point.y, 20.0);
    });

    test('toMap returns correct map', () {
      final point = DataPoint(1.0, 2.0);
      final map = point.toMap();
      expect(map['x'], 1.0);
      expect(map['y'], 2.0);
    });

    test('fromMap creates correct DataPoint', () {
      final map = {'x': 3.0, 'y': 4.0};
      final point = DataPoint.fromMap(map);
      expect(point.x, 3.0);
      expect(point.y, 4.0);
    });
  });

  group('ShotResult', () {
    late ShotResult shot;

    setUp(() {
      shot = ShotResult(
        timestamp: DateTime(2026, 5, 5, 10, 30),
        totalScore: 85.0,
        holdScore: 80.0,
        pressScore: 85.0,
        recoilScore: 90.0,
        elevationScore: 88.0,
        windageScore: 82.0,
        travelDistance: 0.05,
        peakJerk: 15.0,
        firearmType: FirearmType.pistol,
        trainingMode: TrainingMode.dryFire,
        holdX: [1.0, 2.0, 3.0],
        holdY: [0.5, 0.6, 0.7],
        pressX: [0.1, 0.2],
        pressY: [0.3, 0.4],
        recoilX: [0.5],
        recoilY: [0.6],
      );
    });

    test('creates with all required fields', () {
      expect(shot.timestamp, DateTime(2026, 5, 5, 10, 30));
      expect(shot.totalScore, 85.0);
      expect(shot.holdScore, 80.0);
      expect(shot.pressScore, 85.0);
      expect(shot.recoilScore, 90.0);
      expect(shot.elevationScore, 88.0);
      expect(shot.windageScore, 82.0);
      expect(shot.travelDistance, 0.05);
      expect(shot.peakJerk, 15.0);
      expect(shot.firearmType, FirearmType.pistol);
      expect(shot.trainingMode, TrainingMode.dryFire);
    });

    test('phase trace lists are accessible', () {
      expect(shot.holdX, [1.0, 2.0, 3.0]);
      expect(shot.holdY, [0.5, 0.6, 0.7]);
      expect(shot.pressX, [0.1, 0.2]);
      expect(shot.pressY, [0.3, 0.4]);
      expect(shot.recoilX, [0.5]);
      expect(shot.recoilY, [0.6]);
    });

    test('toMap serializes all fields correctly', () {
      final map = shot.toMap();
      expect(map['timestamp'], '2026-05-05T10:30:00.000');
      expect(map['totalScore'], 85.0);
      expect(map['holdScore'], 80.0);
      expect(map['pressScore'], 85.0);
      expect(map['recoilScore'], 90.0);
      expect(map['elevationScore'], 88.0);
      expect(map['windageScore'], 82.0);
      expect(map['travelDistance'], 0.05);
      expect(map['peakJerk'], 15.0);
      expect(map['firearmType'], 'pistol');
      expect(map['trainingMode'], 'dryFire');
      expect(map['holdX'], [1.0, 2.0, 3.0]);
      expect(map['holdY'], [0.5, 0.6, 0.7]);
    });

    test('fromMap deserializes correctly', () {
      final map = {
        'timestamp': '2026-05-05T10:30:00.000',
        'totalScore': 85.0,
        'holdScore': 80.0,
        'pressScore': 85.0,
        'recoilScore': 90.0,
        'elevationScore': 88.0,
        'windageScore': 82.0,
        'travelDistance': 0.05,
        'peakJerk': 15.0,
        'firearmType': 'pistol',
        'trainingMode': 'dryFire',
        'holdX': [1.0, 2.0, 3.0],
        'holdY': [0.5, 0.6, 0.7],
        'pressX': [0.1, 0.2],
        'pressY': [0.3, 0.4],
        'recoilX': [0.5],
        'recoilY': [0.6],
      };

      final loaded = ShotResult.fromMap(map);
      expect(loaded.timestamp, DateTime(2026, 5, 5, 10, 30));
      expect(loaded.totalScore, 85.0);
      expect(loaded.holdScore, 80.0);
      expect(loaded.firearmType, FirearmType.pistol);
      expect(loaded.trainingMode, TrainingMode.dryFire);
      expect(loaded.holdX, [1.0, 2.0, 3.0]);
    });

    test('fromMap handles null phase traces', () {
      final map = {
        'timestamp': '2026-05-05T10:30:00.000',
        'totalScore': 85.0,
        'holdScore': 80.0,
        'pressScore': 85.0,
        'recoilScore': 90.0,
        'elevationScore': 88.0,
        'windageScore': 82.0,
        'travelDistance': 0.05,
        'peakJerk': 15.0,
        'firearmType': 'pistol',
        'trainingMode': 'dryFire',
        'holdX': null,
        'holdY': null,
        'pressX': null,
        'pressY': null,
        'recoilX': null,
        'recoilY': null,
      };

      final loaded = ShotResult.fromMap(map);
      expect(loaded.holdX, null);
      expect(loaded.holdY, null);
      expect(loaded.pressX, null);
    });

    test('fromMap handles missing firearm and training type', () {
      final map = {
        'timestamp': '2026-05-05T10:30:00.000',
        'totalScore': 85.0,
        'holdScore': 80.0,
        'pressScore': 85.0,
        'recoilScore': 90.0,
        'elevationScore': 88.0,
        'windageScore': 82.0,
        'travelDistance': 0.05,
        'peakJerk': 15.0,
      };

      final loaded = ShotResult.fromMap(map);
      expect(loaded.firearmType, FirearmType.pistol);
      expect(loaded.trainingMode, TrainingMode.dryFire);
    });
  });
}
