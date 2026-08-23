// ============================================
// File: services/export_service.dart
// ============================================
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ssa_app/providers/session_logger.dart';

/// Service untuk export session data ke CSV via Share Sheet.
class ExportService {
  /// Generate CSV string dari semua sessions.
  String exportSessionsToCSV(List<SessionLog> sessions) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    // --- SESSION SUMMARY ---
    buffer.writeln('# SESSIONS');
    buffer.writeln(
      'session_date,firearm_type,training_mode,duration_sec,'
      'avg_score,best_score,worst_score,shot_count'
    );

    for (final session in sessions) {
      buffer.writeln(
        '${dateFormat.format(session.date)},'
        '${session.firearmType.name},'
        '${session.trainingMode.name},'
        '${session.duration.toStringAsFixed(1)},'
        '${session.averageScore.toStringAsFixed(2)},'
        '${session.bestScore.toStringAsFixed(2)},'
        '${session.worstScore.toStringAsFixed(2)},'
        '${session.shots.length}'
      );
    }

    buffer.writeln();

    // --- SHOT DETAILS ---
    buffer.writeln('# SHOTS');
    buffer.writeln(
      'session_date,firearm_type,training_mode,shot_timestamp,'
      'total_score,hold_score,press_score,recoil_score,'
      'elevation_score,windage_score,travel_distance,peak_jerk'
    );

    for (final session in sessions) {
      for (final shot in session.shots) {
        buffer.writeln(
          '${dateFormat.format(session.date)},'
          '${session.firearmType.name},'
          '${session.trainingMode.name},'
          '${dateFormat.format(shot.timestamp)},'
          '${shot.totalScore.toStringAsFixed(2)},'
          '${shot.holdScore.toStringAsFixed(2)},'
          '${shot.pressScore.toStringAsFixed(2)},'
          '${shot.recoilScore.toStringAsFixed(2)},'
          '${shot.elevationScore.toStringAsFixed(2)},'
          '${shot.windageScore.toStringAsFixed(2)},'
          '${shot.travelDistance.toStringAsFixed(6)},'
          '${shot.peakJerk.toStringAsFixed(6)}'
        );
      }
    }

    return buffer.toString();
  }

  /// Export dan share CSV via Share Sheet.
  Future<void> shareSessionsCSV(List<SessionLog> sessions) async {
    if (sessions.isEmpty) {
      throw Exception('No sessions to export');
    }

    final csv = exportSessionsToCSV(sessions);
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'STASYS_export_$timestamp.csv';

    // Save to temp directory
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(csv);

    // Share via Share Sheet
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'STASYS Session Export - $timestamp',
      subject: 'STASYS Training Data',
    );
  }

  /// Export single session.
  Future<void> shareSingleSessionCSV(SessionLog session) async {
    await shareSessionsCSV([session]);
  }
}
