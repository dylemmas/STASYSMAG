// ============================================
// File: providers/session_provider.dart
// ============================================
import 'package:flutter/material.dart';
import './session_logger.dart';

class SessionProvider extends ChangeNotifier {
  final SessionLogger _logger;
  List<SessionLog> _sessions = [];

  List<SessionLog> get sessions => List.unmodifiable(_sessions);

  SessionProvider({required SessionLogger logger}) : _logger = logger {
    loadSessions();
  }

  Future<void> loadSessions() async {
    final loadedSessions = await _logger.loadAllSessions();
    _sessions = loadedSessions;
    // Urutkan dari yang terbaru
    _sessions.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  Future<void> deleteSession(SessionLog session) async {
    // Remove from local list
    _sessions.removeWhere((s) => s.id == session.id);

    // Update in storage
    await _logger.deleteSession(session.id);

    // Notify listeners to update UI
    notifyListeners();
  }
}
