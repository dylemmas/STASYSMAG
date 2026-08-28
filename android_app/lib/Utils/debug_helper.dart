// ============================================
// File: utils/debug_helper.dart
// ============================================
import 'package:flutter/material.dart';
import 'dart:async';

class DebugHelper {
  static bool _debugEnabled = true;
  static final List<String> _logs = [];
  static StreamController<String>? _logStream;

  static void enableDebug(bool enabled) {
    _debugEnabled = enabled;
  }

  static Stream<String> get logStream {
    _logStream ??= StreamController<String>.broadcast();
    return _logStream!.stream;
  }

  static void log(String message) {
    if (!_debugEnabled) return;

    final timestamp = DateTime.now().toIso8601String();
    final formattedMessage = "[$timestamp] $message";

    // Print to console
    debugPrint(formattedMessage);

    // Add to internal log list
    _logs.add(formattedMessage);

    // Keep only last 1000 log entries
    if (_logs.length > 1000) {
      _logs.removeRange(0, _logs.length - 1000);
    }

    // Emit to stream for real-time monitoring
    _logStream?.add(formattedMessage);
  }

  static void logChartUpdate(String seriesName, int dataLength) {
    log("CHART_UPDATE: $seriesName with $dataLength data points");
  }

  static void logDataReceived(String data) {
    log("DATA_RECEIVED: ${data.length} chars");
  }

  static void logError(String context, dynamic error) {
    log("ERROR in $context: $error");
  }

  static void logPerformance(String operation, Duration duration) {
    log("PERFORMANCE: $operation took ${duration.inMilliseconds}ms");
  }

  static List<String> getRecentLogs([int count = 100]) {
    if (_logs.length <= count) {
      return List.from(_logs);
    } else {
      return _logs.sublist(_logs.length - count);
    }
  }

  static void clearLogs() {
    _logs.clear();
  }

  static void dispose() {
    _logStream?.close();
    _logStream = null;
  }
}

// Widget untuk menampilkan log real-time
class DebugLogViewer extends StatefulWidget {
  const DebugLogViewer({super.key});

  @override
  State<DebugLogViewer> createState() => _DebugLogViewerState();
}

class _DebugLogViewerState extends State<DebugLogViewer> {
  final ScrollController _scrollController = ScrollController();
  late StreamSubscription _logSubscription;
  final List<String> _displayedLogs = [];

  @override
  void initState() {
    super.initState();

    // Load existing logs
    _displayedLogs.addAll(DebugHelper.getRecentLogs(50));

    // Listen for new logs
    _logSubscription = DebugHelper.logStream.listen((log) {
      if (mounted) {
        setState(() {
          _displayedLogs.add(log);
          if (_displayedLogs.length > 50) {
            _displayedLogs.removeAt(0);
          }
        });

        // Auto-scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Debug Logs',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white, size: 16),
                  onPressed: () {
                    setState(() {
                      _displayedLogs.clear();
                    });
                    DebugHelper.clearLogs();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _displayedLogs.length,
              itemBuilder: (context, index) {
                final log = _displayedLogs[index];
                Color textColor = Colors.black;

                // Color coding for different log types
                if (log.contains('ERROR')) {
                  textColor = Colors.red;
                } else if (log.contains('WARNING')) {
                  textColor = Colors.orange;
                } else if (log.contains('CHART_UPDATE')) {
                  textColor = Colors.blue;
                } else if (log.contains('DATA_RECEIVED')) {
                  textColor = Colors.green;
                } else if (log.contains('PERFORMANCE')) {
                  textColor = Colors.purple;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  child: Text(
                    log,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: textColor,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
