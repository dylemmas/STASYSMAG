// ============================================
// File: screens/tabs/shot_timer_tab.dart
// MantisX-Style Shot Timer
// ============================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/sensor_data_provider.dart';
import '../../providers/bluetooth_provider.dart';

class ShotTimerTab extends StatefulWidget {
  const ShotTimerTab({super.key});

  @override
  State<ShotTimerTab> createState() => _ShotTimerTabState();
}

class _ShotTimerTabState extends State<ShotTimerTab> {
  // Timer states
  ShotTimerState _timerState = ShotTimerState.ready; // ready, countdown, running, stopped
  int _countdownSeconds = 3;
  int _selectedCountdown = 3;
  int _elapsedMs = 0;
  Timer? _timer;

  // Shot tracking
  final List<_ShotTime> _shots = [];
  int _shotCount = 0;
  int _lastShotMs = 0;

  // Session
  DateTime? _startTime;

  // Calibrated flag
  bool _isCalibrated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sensor = context.read<SensorDataProvider>();
      setState(() {
        _isCalibrated = sensor.isCalibrated;
      });
      sensor.addListener(_onSensorUpdate);
      // Wire shot detection callback
      sensor.onShotDetected = _onShotDetected;
    });
  }

  void _onSensorUpdate() {
    final sensor = context.read<SensorDataProvider>();
    final wasCalibrated = _isCalibrated;
    _isCalibrated = sensor.isCalibrated;
    if (!wasCalibrated && _isCalibrated) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final sensor = context.read<SensorDataProvider>();
    sensor.onShotDetected = null;
    sensor.removeListener(_onSensorUpdate);
    super.dispose();
  }

  void _startCountdown() {
    if (!_isCalibrated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calibrate sensor first!')),
      );
      return;
    }

    setState(() {
      _timerState = ShotTimerState.countdown;
      _countdownSeconds = _selectedCountdown;
      _shots.clear();
      _shotCount = 0;
      _lastShotMs = 0;
      _elapsedMs = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() => _countdownSeconds--);
      } else {
        // GO!
        timer.cancel();
        _startTimer();
      }
    });
  }

  void _startTimer() {
    setState(() {
      _timerState = ShotTimerState.running;
      _startTime = DateTime.now();
    });

    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (_timerState != ShotTimerState.running) {
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(_startTime!).inMilliseconds;
      setState(() => _elapsedMs = elapsed);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() => _timerState = ShotTimerState.stopped);
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _timerState = ShotTimerState.ready;
      _elapsedMs = 0;
      _shots.clear();
      _shotCount = 0;
      _lastShotMs = 0;
    });
  }

  // Called when a shot is detected (from sensor data)
  void _onShotDetected() {
    if (_timerState != ShotTimerState.running) return;

    final now = DateTime.now();
    final elapsed = now.difference(_startTime!).inMilliseconds;

    final split = _lastShotMs == 0 ? elapsed : elapsed - _lastShotMs;
    _lastShotMs = elapsed;

    setState(() {
      _shotCount++;
      _shots.add(_ShotTime(
        number: _shotCount,
        totalMs: elapsed,
        splitMs: split,
      ));
    });
  }

  String _formatMs(int ms) {
    final secs = ms ~/ 1000;
    final millis = (ms % 1000) ~/ 10;
    return '$secs.${millis.toString().padLeft(2, '0')}';
  }

  String _formatElapsed() {
    final secs = _elapsedMs ~/ 1000;
    final millis = (_elapsedMs % 1000) ~/ 10;
    return '$secs.${millis.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Connection Status
            _buildConnectionStatus(),
            const SizedBox(height: 16),

            // Main timer display
            Expanded(
              flex: 2,
              child: _buildTimerDisplay(),
            ),

            const SizedBox(height: 16),

            // Shot list
            Expanded(
              flex: 1,
              child: _buildShotList(),
            ),

            const SizedBox(height: 16),

            // Controls
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Consumer<BluetoothProvider>(
      builder: (context, bt, child) {
        return Row(
          children: [
            Icon(
              bt.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: bt.isConnected ? Colors.green : Colors.red,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              bt.isConnected ? 'Connected: ${bt.selectedDevice?.name ?? 'STASYS'}' : 'Not Connected',
              style: TextStyle(
                color: bt.isConnected ? Colors.green : Colors.red,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            if (!_isCalibrated)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text(
                  '⚠️ Calibrate First',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '✓ Calibrated',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTimerDisplay() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Countdown mode
          if (_timerState == ShotTimerState.countdown)
            Text(
              '$_countdownSeconds',
              style: const TextStyle(
                fontSize: 120,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

          // Ready mode
          if (_timerState == ShotTimerState.ready)
            Column(
              children: [
                const Text(
                  'READY',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Shots fired: $_shotCount',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),

          // Running mode
          if (_timerState == ShotTimerState.running)
            Column(
              children: [
                const Text(
                  'TIME',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.green,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  _formatElapsed(),
                  style: const TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getShotCountColor(_shotCount).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getShotCountColor(_shotCount)),
                  ),
                  child: Text(
                    '$_shotCount SHOTS',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _getShotCountColor(_shotCount),
                    ),
                  ),
                ),
              ],
            ),

          // Stopped mode
          if (_timerState == ShotTimerState.stopped)
            Column(
              children: [
                const Text(
                  'FINISHED',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatElapsed(),
                  style: const TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_shotCount shots',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Color _getShotCountColor(int count) {
    if (count == 0) return Colors.grey;
    if (count <= 3) return Colors.blue;
    if (count <= 6) return Colors.green;
    return Colors.amber;
  }

  Widget _buildShotList() {
    if (_shots.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'No shots recorded',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: const [
                SizedBox(width: 40, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(child: Text('TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 80, child: Text('SPLIT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _shots.length,
              itemBuilder: (context, index) {
                final shot = _shots[_shots.length - 1 - index]; // Most recent first
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${shot.number}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _formatMs(shot.totalMs),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          _formatMs(shot.splitMs),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            color: shot.splitMs < 500 ? Colors.green : shot.splitMs > 2000 ? Colors.red : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      children: [
        // Countdown selector
        if (_timerState == ShotTimerState.ready)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Countdown: ', style: TextStyle(fontSize: 13)),
              for (final secs in [3, 5, 10])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text('${secs}s'),
                    selected: _selectedCountdown == secs,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedCountdown = secs);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),

        const SizedBox(height: 12),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (_timerState == ShotTimerState.ready || _timerState == ShotTimerState.stopped)
              _actionButton(
                'START',
                Colors.green,
                Icons.play_arrow,
                _startCountdown,
              ),

            if (_timerState == ShotTimerState.countdown)
              _actionButton(
                'CANCEL',
                Colors.orange,
                Icons.close,
                _resetTimer,
              ),

            if (_timerState == ShotTimerState.running)
              _actionButton(
                'STOP',
                Colors.red,
                Icons.stop,
                _stopTimer,
              ),

            if (_timerState == ShotTimerState.stopped)
              _actionButton(
                'RESET',
                Colors.blue,
                Icons.refresh,
                _resetTimer,
              ),
          ],
        ),
      ],
    );
  }

  Widget _actionButton(String label, Color color, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}

enum ShotTimerState { ready, countdown, running, stopped }

class _ShotTime {
  final int number;
  final int totalMs;
  final int splitMs;

  _ShotTime({
    required this.number,
    required this.totalMs,
    required this.splitMs,
  });
}
