// ============================================
// File: services/database_service.dart
// ============================================
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import '../models/data_models.dart';
import '../providers/session_logger.dart';
import 'database_helper.dart';

/// Service layer for session/shots persistence with SQLite.
/// Uses binary BLOB encoding for time series and phase trace data.
class DatabaseService {
  final DatabaseHelper _dbHelper;

  DatabaseService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  // ==========================================
  // Encoding helpers (time series)
  // ==========================================

  /// Encode list of DataPoints to binary BLOB.
  /// Format: pointCount(int32) + [relTimestamp(float32) + value(float32)] * N
  Uint8List _encodeTimeSeries(List<DataPoint> points) {
    if (points.isEmpty) return Uint8List(0);

    final buf = ByteData(4 + points.length * 8);
    buf.setInt32(0, points.length, Endian.little);
    for (int i = 0; i < points.length; i++) {
      buf.setFloat32(4 + i * 8, points[i].x, Endian.little);
      buf.setFloat32(4 + i * 8 + 4, points[i].y, Endian.little);
    }
    return buf.buffer.asUint8List();
  }

  /// Decode binary BLOB back to list of DataPoints.
  List<DataPoint> _decodeTimeSeries(Uint8List data) {
    if (data.isEmpty) return [];
    final buf = ByteData.sublistView(data);
    final count = buf.getInt32(0, Endian.little);
    final result = <DataPoint>[];
    for (int i = 0; i < count; i++) {
      final ts = buf.getFloat32(4 + i * 8, Endian.little);
      final val = buf.getFloat32(4 + i * 8 + 4, Endian.little);
      result.add(DataPoint(ts, val));
    }
    return result;
  }

  // ==========================================
  // Encoding helpers (phase traces)
  // ==========================================

  /// Encode a list of doubles to binary BLOB.
  Uint8List _encodeDoubleList(List<double>? list) {
    if (list == null || list.isEmpty) return Uint8List(0);
    final buf = ByteData(4 + list.length * 8);
    buf.setInt32(0, list.length, Endian.little);
    for (int i = 0; i < list.length; i++) {
      buf.setFloat64(4 + i * 8, list[i], Endian.little);
    }
    return buf.buffer.asUint8List();
  }

  /// Decode binary BLOB back to list of doubles.
  List<double> _decodeDoubleList(Uint8List data) {
    if (data.isEmpty) return [];
    final buf = ByteData.sublistView(data);
    final count = buf.getInt32(0, Endian.little);
    final result = <double>[];
    for (int i = 0; i < count; i++) {
      result.add(buf.getFloat64(4 + i * 8, Endian.little));
    }
    return result;
  }

  // ==========================================
  // Session CRUD
  // ==========================================

  /// Save a complete session (with shots) to DB.
  Future<void> saveSession(SessionLog session) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // Insert session
      await txn.insert(
        'sessions',
        {
          'id': session.id,
          'date': session.date.millisecondsSinceEpoch,
          'duration': session.duration,
          'firearm_type': session.firearmType.name,
          'training_mode': session.trainingMode.name,
          'gyro_x': _encodeTimeSeries(session.gyroX),
          'gyro_y': _encodeTimeSeries(session.gyroY),
          'gyro_z': _encodeTimeSeries(session.gyroZ),
          'accel_x': _encodeTimeSeries(session.accelX),
          'accel_y': _encodeTimeSeries(session.accelY),
          'accel_z': _encodeTimeSeries(session.accelZ),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Insert shots (batch)
      final batch = txn.batch();
      for (final shot in session.shots) {
        batch.insert(
          'shots',
          {
            'session_id': session.id,
            'timestamp': shot.timestamp.millisecondsSinceEpoch,
            'total_score': shot.totalScore,
            'hold_score': shot.holdScore,
            'press_score': shot.pressScore,
            'recoil_score': shot.recoilScore,
            'elevation_score': shot.elevationScore,
            'windage_score': shot.windageScore,
            'travel_distance': shot.travelDistance,
            'peak_jerk': shot.peakJerk,
            'firearm_type': shot.firearmType.name,
            'training_mode': shot.trainingMode.name,
            'hold_x': _encodeDoubleList(shot.holdX),
            'hold_y': _encodeDoubleList(shot.holdY),
            'press_x': _encodeDoubleList(shot.pressX),
            'press_y': _encodeDoubleList(shot.pressY),
            'recoil_x': _encodeDoubleList(shot.recoilX),
            'recoil_y': _encodeDoubleList(shot.recoilY),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Load all sessions (sorted by date DESC) with shots.
  Future<List<SessionLog>> loadAllSessions() async {
    final db = await _dbHelper.database;
    final sessionRows = await db.query(
      'sessions',
      orderBy: 'date DESC',
    );

    final result = <SessionLog>[];
    for (final row in sessionRows) {
      final session = await _sessionFromRow(row);
      if (session != null) {
        result.add(session);
      }
    }
    return result;
  }

  /// Load a single session by ID with its shots.
  Future<SessionLog?> getSession(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return await _sessionFromRow(rows.first);
  }

  /// Delete a session and all its shots (CASCADE).
  Future<void> deleteSession(String sessionId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Decode the raw sensor time series for a session from the DB.
  /// Returns a map with keys 'gyroX/Y/Z' and 'accelX/Y/Z'.
  /// Each value is the decoded List<DataPoint>.
  /// Returns an empty map if the session doesn't exist.
  Future<Map<String, List<DataPoint>>> decodeRawSession(String sessionId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    if (rows.isEmpty) return {};
    final row = rows.first;
    return {
      'gyroX': _decodeBlob(row['gyro_x']),
      'gyroY': _decodeBlob(row['gyro_y']),
      'gyroZ': _decodeBlob(row['gyro_z']),
      'accelX': _decodeBlob(row['accel_x']),
      'accelY': _decodeBlob(row['accel_y']),
      'accelZ': _decodeBlob(row['accel_z']),
    };
  }

  // ==========================================
  // Row → SessionLog reconstruction
  // ==========================================

  Future<SessionLog?> _sessionFromRow(Map<String, Object?> row) async {
    try {
      final sessionId = row['id'] as String;
      final shots = await _loadShotsForSession(sessionId);

      return SessionLog(
        id: sessionId,
        date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int),
        duration: (row['duration'] as num).toDouble(),
        firearmType: FirearmType.fromString(row['firearm_type'] as String),
        trainingMode: TrainingMode.fromString(row['training_mode'] as String),
        gyroX: _decodeBlob(row['gyro_x']),
        gyroY: _decodeBlob(row['gyro_y']),
        gyroZ: _decodeBlob(row['gyro_z']),
        accelX: _decodeBlob(row['accel_x']),
        accelY: _decodeBlob(row['accel_y']),
        accelZ: _decodeBlob(row['accel_z']),
        shots: shots,
      );
    } catch (e) {
      return null;
    }
  }

  List<DataPoint> _decodeBlob(Object? blob) {
    if (blob == null) return [];
    if (blob is Uint8List) return _decodeTimeSeries(blob);
    if (blob is List<int>) return _decodeTimeSeries(Uint8List.fromList(blob));
    return [];
  }

  Future<List<ShotResult>> _loadShotsForSession(String sessionId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'shots',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );

    return rows.map(_shotFromRow).whereType<ShotResult>().toList();
  }

  ShotResult? _shotFromRow(Map<String, Object?> row) {
    try {
      return ShotResult(
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
        totalScore: (row['total_score'] as num).toDouble(),
        holdScore: (row['hold_score'] as num).toDouble(),
        pressScore: (row['press_score'] as num).toDouble(),
        recoilScore: (row['recoil_score'] as num).toDouble(),
        elevationScore: (row['elevation_score'] as num).toDouble(),
        windageScore: (row['windage_score'] as num).toDouble(),
        travelDistance: (row['travel_distance'] as num).toDouble(),
        peakJerk: (row['peak_jerk'] as num).toDouble(),
        firearmType: FirearmType.fromString(row['firearm_type'] as String),
        trainingMode: TrainingMode.fromString(row['training_mode'] as String),
        holdX: _decodeDoubleBlob(row['hold_x']),
        holdY: _decodeDoubleBlob(row['hold_y']),
        pressX: _decodeDoubleBlob(row['press_x']),
        pressY: _decodeDoubleBlob(row['press_y']),
        recoilX: _decodeDoubleBlob(row['recoil_x']),
        recoilY: _decodeDoubleBlob(row['recoil_y']),
      );
    } catch (e) {
      return null;
    }
  }

  List<double> _decodeDoubleBlob(Object? blob) {
    if (blob == null) return [];
    if (blob is Uint8List) return _decodeDoubleList(blob);
    if (blob is List<int>) return _decodeDoubleList(Uint8List.fromList(blob));
    return [];
  }
}
