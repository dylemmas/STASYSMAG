// ============================================
// Debug Overlay - Tambahkan ke graph_tab.dart
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bluetooth_provider.dart';
import '../../providers/sensor_data_provider.dart';
import 'dart:async';

class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  Timer? _updateTimer;
  int _fps = 0;
  int _frameCount = 0;
  DateTime? _lastFpsCheck;

  @override
  void initState() {
    super.initState();
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() {
          _frameCount++;
          final now = DateTime.now();
          if (_lastFpsCheck == null || now.difference(_lastFpsCheck!).inSeconds >= 1) {
            _fps = _frameCount;
            _frameCount = 0;
            _lastFpsCheck = now;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<BluetoothProvider, SensorDataProvider>(
      builder: (context, bluetooth, sensor, child) {
        return Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(80),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.cyan, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🔍 DEBUG',
                  style: TextStyle(
                    color: Colors.cyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const Divider(color: Colors.cyan, height: 8),

                _buildDebugRow('UI FPS', '$_fps Hz',
                  _fps >= 15 ? Colors.green : Colors.red),

                _buildDebugRow('Total Packets', '${bluetooth.totalPacketsReceived}',
                  Colors.white),

                _buildDebugRow('Packet Loss',
                  '${bluetooth.packetLossPercentage.toStringAsFixed(1)}%',
                  bluetooth.packetLossPercentage < 5 ? Colors.green : Colors.red),

                _buildDebugRow('Buffer Size', '${sensor.gyroXData.length} pts',
                  sensor.gyroXData.length < 180 ? Colors.green : Colors.orange),

                _buildDebugRow('Invalid', '${bluetooth.invalidPacketsCount}',
                  bluetooth.invalidPacketsCount < 10 ? Colors.white : Colors.orange),

                _buildDebugRow('Checksum Err', '${bluetooth.checksumErrorsCount}',
                  bluetooth.checksumErrorsCount < 5 ? Colors.white : Colors.red),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebugRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// CARA PAKAI: Update graph_tab.dart
// ============================================
/*

Di graph_tab.dart, ganti body: Column(...) menjadi:

body: Stack(
  children: [
    Column(
      children: [
        _buildStatusBar(),
        const Expanded(
          flex: 3,
          child: RepaintBoundary(
            child: GyroRealtimeChart(),
          ),
        ),
        _buildControlPanel(),
      ],
    ),

    // TAMBAHKAN INI
    const DebugOverlay(),
  ],
)

*/
