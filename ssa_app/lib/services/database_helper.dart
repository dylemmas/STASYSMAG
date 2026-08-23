// ============================================
// File: services/database_helper.dart
// ============================================
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Singleton database helper — manages DB lifecycle and schema.
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'stasys_sessions.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    // Sessions table (renamed from recordings)
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        date INTEGER NOT NULL,
        duration REAL NOT NULL,
        firearm_type TEXT NOT NULL,
        training_mode TEXT NOT NULL,
        gyro_x BLOB,
        gyro_y BLOB,
        gyro_z BLOB,
        accel_x BLOB,
        accel_y BLOB,
        accel_z BLOB
      )
    ''');

    // Shots table
    await db.execute('''
      CREATE TABLE shots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        total_score REAL NOT NULL,
        hold_score REAL NOT NULL,
        press_score REAL NOT NULL,
        recoil_score REAL NOT NULL,
        elevation_score REAL NOT NULL,
        windage_score REAL NOT NULL,
        travel_distance REAL NOT NULL,
        peak_jerk REAL NOT NULL,
        firearm_type TEXT NOT NULL,
        training_mode TEXT NOT NULL,
        hold_x BLOB,
        hold_y BLOB,
        press_x BLOB,
        press_y BLOB,
        recoil_x BLOB,
        recoil_y BLOB,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    // Indexes
    await db.execute(
      'CREATE INDEX idx_sessions_date ON sessions(date DESC)'
    );
    await db.execute(
      'CREATE INDEX idx_sessions_firearm ON sessions(firearm_type)'
    );
    await db.execute(
      'CREATE INDEX idx_shots_session ON shots(session_id)'
    );
    await db.execute(
      'CREATE INDEX idx_shots_score ON shots(total_score DESC)'
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
