// ============================================
// File: providers/sensor_data_provider.dart (OPTIMIZED V3)
// UI Thread hanya menerima display window, full data di isolate
// ============================================
import 'package:flutter/material.dart';
import 'dart:isolate';
import 'dart:async';
import '../models/data_models.dart';
import './session_logger.dart';
import './settings_provider.dart';
import './sensor_data_isolate.dart';

class SensorDataProvider extends ChangeNotifier {
  final SessionLogger _sessionLogger;
  SettingsProvider? _settingsProvider;

  // Isolate components
  Isolate? _dataIsolate;
  ReceivePort? _mainReceivePort;
  SendPort? _isolateSendPort;
  Completer<void>? _isolateReadyCompleter;
  Completer<void>? _sessionFetchCompleter; // used by saveCurrentSession() when buffers are empty
  bool _isSaving = false; // prevent double-save race condition

  // Queue messages sent before isolate SendPort was received
  final List<SensorDataMessage> _pendingMessages = [];

    // Konfigurasi
  final int _displayWindowSeconds = 5;

  // Display buffers (HANYA 5 detik terakhir - immutable snapshots dari isolate)
  List<DataPoint> _gyroXData = [];
  List<DataPoint> _gyroYData = [];
  List<DataPoint> _gyroZData = [];
  List<DataPoint> _accelXData = [];
  List<DataPoint> _accelYData = [];
  List<DataPoint> _accelZData = [];

  // Trace coordinates (pre-computed atan2 projection from isolate)
  List<double> _traceXData = [];
  List<double> _traceYData = [];
  double _liveTraceX = 0;
  double _liveTraceY = 0;

  // Session data (akan diambil dari isolate saat save)
  List<DataPoint>? _sessionGyroX;
  List<DataPoint>? _sessionGyroY;
  List<DataPoint>? _sessionGyroZ;
  List<DataPoint>? _sessionAccelX;
  List<DataPoint>? _sessionAccelY;
  List<DataPoint>? _sessionAccelZ;
  List<ShotResult> _sessionShots = [];

  // Latest shot result (for UI display)
  ShotResult? _latestShot;
  ShotResult? get latestShot => _latestShot;

  // Shot detection callback (for shot timer)
  VoidCallback? onShotDetected;

  // Status
  bool _isRecording = false;
  bool _isCalibrated = false;
  bool _isCalibrating = false;
  int _batteryLevel = 100;
  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  int _calibrationSamplesCount = 0;
  final int _samplesToCollect = 50;

  // Performance metrics
  int _totalDataPoints = 0;
  int _uiUpdatesReceived = 0;
  double _currentStabilityScore = 100.0;

  // Demo mode
  bool _isDemoMode = false;
  Timer? _demoTimer;
  double _demoGyroX = 0;
  double _demoGyroY = 0;
  double _demoGyroZ = 0;
  double _demoAccelX = 0;
  double _demoAccelY = 0;
  double _demoAccelZ = 9.81;
  int _demoShotPhase = 0; // 0=idle, 1-9=recoil spike decay
  double _demoTime = 0;
  DateTime? _demoLastShotTime;
  int _demoShotCount = 0;

  // Getters
  List<DataPoint> get gyroXData => _gyroXData;
  List<DataPoint> get gyroYData => _gyroYData;
  List<DataPoint> get gyroZData => _gyroZData;
  List<DataPoint> get accelXData => _accelXData;
  List<DataPoint> get accelYData => _accelYData;
  List<DataPoint> get accelZData => _accelZData;

  List<double> get traceXData => _traceXData;
  List<double> get traceYData => _traceYData;
  double get liveTraceX => _liveTraceX;
  double get liveTraceY => _liveTraceY;

  bool get isRecording => _isRecording;
  bool get isCalibrated => _isCalibrated;
  bool get isCalibrating => _isCalibrating;
  int get batteryLevel => _batteryLevel;
  Duration get recordingDuration => _recordingDuration;
  bool get canSaveSession => !_isRecording && _sessionGyroX != null && _sessionGyroX!.isNotEmpty;
  int get calibrationSamplesCount => _calibrationSamplesCount;
  int get samplesToCollect => _samplesToCollect;
  double get stabilityScore => _currentStabilityScore;

  // Performance getters
  int get totalDataPoints => _totalDataPoints;
  int get uiUpdatesReceived => _uiUpdatesReceived;

  // Session shots (for analysis tab)
  List<ShotResult> get sessionShots => List.unmodifiable(_sessionShots);

  SensorDataProvider({
    required SessionLogger logger,
    SettingsProvider? settings,
  }) : _sessionLogger = logger,
       _settingsProvider = settings {
    _initializeIsolate();
  }

  void updateDependencies({
    required SettingsProvider settings,
    required SessionLogger logger,
  }) {
    _settingsProvider = settings;
    // Send settings to isolate
    _isolateSendPort?.send(SensorDataMessage('update_settings', {
      'firearmType': settings.firearmType.name,
      'trainingMode': settings.trainingMode.name,
      'displayWindowSeconds': settings.maxSamples,
      'mountDirection': settings.mountDirection.name,
    }));
  }

  /// Initialize background isolate
  Future<void> _initializeIsolate() async {
    _mainReceivePort = ReceivePort();

    // CRITICAL: Attach listener BEFORE spawning isolate.
    // The isolate sends SendPort synchronously on startup.
    // If we spawn first and await, the isolate might send before listener is ready.
    _mainReceivePort!.listen(_handleIsolateMessage);
    debugPrint("[PROVIDER] Listener attached, spawning isolate...");

    final config = SensorIsolateConfig(
      mainSendPort: _mainReceivePort!.sendPort,
      displayWindowSeconds: 5, // 5 detik window
      uiUpdateIntervalMs: 16, // Update setiap 16ms = 60 FPS
    );

    _dataIsolate = await Isolate.spawn(
      SensorDataIsolate.entryPoint,
      config,
    );

    debugPrint("[PROVIDER] Isolate spawned, waiting for SendPort...");
  }

  /// Handle messages dari isolate
  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      debugPrint("[PROVIDER] ✅ Received SendPort from isolate! Isolate is READY.");
      _isolateSendPort = message;
      _isolateReadyCompleter?.complete();

      // Flush any queued messages
      if (_pendingMessages.isNotEmpty) {
        debugPrint("[PROVIDER] 🔄 Flushing ${_pendingMessages.length} pending message(s)...");
        for (final msg in _pendingMessages) {
          _isolateSendPort!.send(msg);
        }
        _pendingMessages.clear();
      }
      return;
    }

    if (message is SensorDataMessage) {
      switch (message.type) {
        case 'ui_update':
          // Isolate sends 'ui_update' — determine if full sync or diff based on data
          if (_gyroXData.isEmpty) {
            _handleFullSync(message.data!);
          } else {
            _handleDiffUpdate(message.data!);
          }
          break;
        case 'full_sync':
          _handleFullSync(message.data!);
          break;
        case 'diff_update':
          _handleDiffUpdate(message.data!);
          break;
        case 'calibration_started':
          debugPrint("[PROVIDER] Received calibration_started from isolate");
          _isCalibrating = true;
          notifyListeners();
          break;
        case 'calibration_progress':
          _calibrationSamplesCount = message.data!['count'];
          debugPrint("[PROVIDER] Calibration progress: $_calibrationSamplesCount/${message.data!['total']}");
          notifyListeners();
          break;
        case 'calibration_complete':
          debugPrint("[PROVIDER] Calibration COMPLETE!");
          _isCalibrating = false;
          _isCalibrated = true;
          notifyListeners();
          break;
        case 'session_data':
          debugPrint("[PROVIDER] Received session_data from isolate. "
              "gyroX_len=${(message.data!['gyroX'] as List?)?.length ?? 0}");
          _handleSessionData(message.data!);
          // Guard against double-complete (would throw 'Bad state: Future
          // has already been completed'). This can happen if a stray
          // 'session_data' arrives while a save is still waiting for the
          // fetch response.
          final completer = _sessionFetchCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
          _sessionFetchCompleter = null;
          notifyListeners();
          break;
        case 'shot_detected':
          _handleShotDetected(message.data!);
          break;
        case 'recording_started':
          _isRecording = true;
          _sessionShots.clear();
          notifyListeners();
          break;
        case 'recording_stopped':
          _isRecording = false;
          notifyListeners();
          break;
      }
    }
  }
  /// Handle sinkronisasi penuh dari isolate
  void _handleFullSync(Map<String, dynamic> data) {
    _gyroXData = List<DataPoint>.from(data['gyroX']);
    _gyroYData = List<DataPoint>.from(data['gyroY']);
    _gyroZData = List<DataPoint>.from(data['gyroZ']);
    _accelXData = List<DataPoint>.from(data['accelX']);
    _accelYData = List<DataPoint>.from(data['accelY']);
    _accelZData = List<DataPoint>.from(data['accelZ']);

    // Extract trace coordinates from isolate
    _traceXData = List<double>.from(data['traceX'] ?? []);
    _traceYData = List<double>.from(data['traceY'] ?? []);
    _liveTraceX = (data['liveX'] as num?)?.toDouble() ?? 0.0;
    _liveTraceY = (data['liveY'] as num?)?.toDouble() ?? 0.0;

    _updateCommonMetrics(data);
    notifyListeners();
  }
  // --- FUNGSI BARU: Menangani diff_update ---
  void _handleDiffUpdate(Map<String, dynamic> data) {
    _gyroXData = List<DataPoint>.from(data['gyroX']);
    _gyroYData = List<DataPoint>.from(data['gyroY']);
    _gyroZData = List<DataPoint>.from(data['gyroZ']);
    _accelXData = List<DataPoint>.from(data['accelX']);
    _accelYData = List<DataPoint>.from(data['accelY']);
    _accelZData = List<DataPoint>.from(data['accelZ']);

    // Update trace coordinates from isolate
    if (data.containsKey('traceX') && data['traceX'] != null) {
      _traceXData = List<double>.from(data['traceX']);
      _traceYData = List<double>.from(data['traceY']);
      _liveTraceX = (data['liveX'] as num?)?.toDouble() ?? _liveTraceX;
      _liveTraceY = (data['liveY'] as num?)?.toDouble() ?? _liveTraceY;
    }

    _updateCommonMetrics(data);
    notifyListeners();
  }

  void _updateCommonMetrics(Map<String, dynamic> data) {
    if (data.containsKey('stability')) {
      _currentStabilityScore = data['stability'] as double;
    }
    if (data.containsKey('totalDataPoints')) {
      _totalDataPoints = data['totalDataPoints'] as int;
    }
    _uiUpdatesReceived++;
  }

  /// Update display buffers dari isolate (immutable assignment)
  // void _handleDisplayUpdate(Map<String, dynamic> data) {
  //   // KUNCI: Hanya assign reference baru ke display window (5 detik)
  //   // Ini sangat cepat karena hanya pointer assignment
  //   _gyroXData = List<DataPoint>.from(data['gyroX']);
  //   _gyroYData = List<DataPoint>.from(data['gyroY']);
  //   _gyroZData = List<DataPoint>.from(data['gyroZ']);
  //   _accelXData = List<DataPoint>.from(data['accelX']);
  //   _accelYData = List<DataPoint>.from(data['accelY']);
  //   _accelZData = List<DataPoint>.from(data['accelZ']);

  //   // Update metrics
  //   _currentStabilityScore = data['stability'] as double;
  //   _totalDataPoints = data['totalDataPoints'] as int;
  //   _uiUpdatesReceived++;

  //   // Debug log (hapus setelah debug)
  //   debugPrint("[PROVIDER] Display update - GyroX: ${_gyroXData.length} points");

  //   // Single notifyListeners call
  //   notifyListeners();
  // }

  /// Receive session data dari isolate
  void _handleSessionData(Map<String, dynamic> data) {
    _sessionGyroX = data['gyroX'] as List<DataPoint>;
    _sessionGyroY = data['gyroY'] as List<DataPoint>;
    _sessionGyroZ = data['gyroZ'] as List<DataPoint>;
    _sessionAccelX = data['accelX'] as List<DataPoint>;
    _sessionAccelY = data['accelY'] as List<DataPoint>;
    _sessionAccelZ = data['accelZ'] as List<DataPoint>;
    if (data.containsKey('shots')) {
      _sessionShots = (data['shots'] as List)
          .map((s) => ShotResult.fromMap(s as Map<String, dynamic>))
          .toList();
    }
  }

  /// Handle shot detection events from isolate
  void _handleShotDetected(Map<String, dynamic> data) {
    _latestShot = ShotResult.fromMap(data['shot'] as Map<String, dynamic>);
    _sessionShots.add(_latestShot!);
    onShotDetected?.call();
    notifyListeners();
  }

  /// Send settings changes to isolate
  void updateSettings() {
    if (_settingsProvider == null) return;
    _isolateSendPort?.send(SensorDataMessage('update_settings', {
      'firearmType': _settingsProvider!.firearmType.name,
      'trainingMode': _settingsProvider!.trainingMode.name,
      'mountDirection': _settingsProvider!.mountDirection.name,
    }));
  }

  void requestFullSync() {
    _isolateSendPort?.send(SensorDataMessage('request_full_sync'));
    debugPrint("[PROVIDER] Requesting full data sync...");
  }

  /// Send sensor data ke isolate (dipanggil dari BluetoothProvider)
  void updateAllData({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required int battery,
    int piezo = 0, // Peak piezo value from oversampling firmware
  }) {
    // Update battery di UI thread (simple state)
    // Hanya update jika perbedaan signifikan
    if ((_batteryLevel - battery).abs() >= 5) {
      _batteryLevel = battery;
    }

    // Forward ke isolate untuk processing
    if (_isolateSendPort != null) {
      _isolateSendPort!.send(SensorDataMessage('sensor_data', {
        'ax': ax,
        'ay': ay,
        'az': az,
        'gx': gx,
        'gy': gy,
        'gz': gz,
        'piezo': piezo,
        'battery': battery,
      }));
    }
  }

  void startCalibration() {
    debugPrint("[PROVIDER] startCalibration() called, _isolateSendPort: ${_isolateSendPort != null ? 'OK' : 'NULL'}");

    if (_isolateSendPort == null) {
      // Isolate not ready — queue message and it will be flushed when SendPort arrives
      debugPrint("[PROVIDER] ⚠️ Isolate not ready, queuing calibration message");
      _pendingMessages.add(SensorDataMessage('start_calibration'));
      return;
    }

    _isolateSendPort!.send(SensorDataMessage('start_calibration'));
  }

  void startRecording() {
    if (!_isCalibrated) return;

    _isRecording = true;
    _recordingStartTime = DateTime.now();
    _recordingDuration = Duration.zero;

    _isolateSendPort?.send(SensorDataMessage('start_recording'));

    // Timer untuk update durasi
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordingStartTime != null) {
        _recordingDuration = DateTime.now().difference(_recordingStartTime!);
      }
      notifyListeners();
    });

    notifyListeners();
  }

  void stopRecording() {
    _isRecording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    _isolateSendPort?.send(SensorDataMessage('stop_recording'));

    notifyListeners();
  }

  void toggleRecording() {
    if (_isRecording) {
      stopRecording();
    } else {
      startRecording();
    }
  }

  void resetTimeReference() {
    _isolateSendPort?.send(SensorDataMessage('reset'));
  }

  /// Reset axis — clears gyro offsets, re-runs auto-calibration
  void resetAxis() {
    _isolateSendPort?.send(SensorDataMessage('reset_axis'));
  }

  /// Save session - request data dari isolate dulu
  Future<void> saveCurrentSession() async {
    // Guard against double-save race
    if (_isSaving) {
      debugPrint("[SAVE] ALREADY SAVING — skipping duplicate call");
      return;
    }
    _isSaving = true;

    // DEBUG: log state at save time
    debugPrint("[SAVE] Entered saveCurrentSession. "
        "isRecording=$_isRecording "
        "sessionGyroX_null=${_sessionGyroX == null} "
        "sessionGyroX_len=${_sessionGyroX?.length ?? 0} "
        "sessionAccelX_len=${_sessionAccelX?.length ?? 0} "
        "sessionShots=${_sessionShots.length}");

    try {
      // If buffers are empty, wait for isolate to send fresh session_data.
      // The main listener (line ~217) will call _handleSessionData and then
      // complete _sessionFetchCompleter.  We do NOT add a second listener —
      // that throws 'Bad state: Stream is already listened to'.
      if (_sessionGyroX == null || _sessionGyroX!.isEmpty) {
        debugPrint("[SAVE] Buffers empty — requesting fresh data from isolate");
        _sessionFetchCompleter = Completer<void>();
        _isolateSendPort?.send(SensorDataMessage('get_session_data'));

        try {
          await _sessionFetchCompleter!.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException(
                  'Failed to get session data from isolate within 5s. '
                  'isolateReady=${_isolateSendPort != null}');
            },
          );
        } finally {
          // Always clear the completer reference so any stray 'session_data'
          // arriving late does not try to complete it again.
          _sessionFetchCompleter = null;
        }

        debugPrint("[SAVE] After fetch: gyroX_len=${_sessionGyroX?.length ?? 0} "
            "sessionDataReady=${_sessionGyroX != null}");
      }

      if (_sessionGyroX == null || _sessionGyroX!.isEmpty) {
        debugPrint("[SAVE] ABORT: no gyro data after fetch. "
            "Isolate may not have buffered any data during recording.");
        throw Exception('No session data available — isolate returned empty buffers');
      }

      debugPrint("[SAVE] Saving session. "
          "gyroX=${_sessionGyroX!.length} accelX=${_sessionAccelX!.length} "
          "shots=${_sessionShots.length}");

      final sessionId = "SESSION_${DateTime.now().millisecondsSinceEpoch}";
      final firearmType = _settingsProvider?.firearmType ?? FirearmType.pistol;
      final trainingMode = _settingsProvider?.trainingMode ?? TrainingMode.dryFire;

      final log = SessionLog(
        id: sessionId,
        date: DateTime.now(),
        duration: _recordingDuration.inMilliseconds / 1000.0,
        gyroX: List.from(_sessionGyroX!),
        gyroY: List.from(_sessionGyroY!),
        gyroZ: List.from(_sessionGyroZ!),
        accelX: List.from(_sessionAccelX!),
        accelY: List.from(_sessionAccelY!),
        accelZ: List.from(_sessionAccelZ!),
        firearmType: firearmType,
        trainingMode: trainingMode,
        shots: List.from(_sessionShots),
      );

      await _sessionLogger.saveSession(log);

      // Clear session data
      _sessionGyroX = null;
      _sessionGyroY = null;
      _sessionGyroZ = null;
      _sessionAccelX = null;
      _sessionAccelY = null;
      _sessionAccelZ = null;
      _sessionShots.clear();
      _latestShot = null;

      _isolateSendPort?.send(SensorDataMessage('clear_session'));

      notifyListeners();
    } finally {
      _isSaving = false;
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _demoTimer?.cancel();
    _demoTimer = null;
    _isolateSendPort?.send(SensorDataMessage('reset'));
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _isolateSendPort = null;
    _dataIsolate?.kill(priority: Isolate.immediate);
    _dataIsolate = null;
    super.dispose();
  }

  // ============================================
  // Demo Mode
  // ============================================
  void setDemoMode(bool value) {
    if (_isDemoMode == value) return;
    _isDemoMode = value;
    if (value) {
      _startDemoTimer();
    } else {
      _stopDemoTimer();
    }
    notifyListeners();
  }

  bool get isDemoMode => _isDemoMode;

  // Demo trace state (for MantisX-style direct mapping)
  double _demoTraceXPos = 0.0, _demoTraceYPos = 0.0;  // trace line position (gyro integrated)
  double _demoLiveX = 0.0, _demoLiveY = 0.0;    // live dot position (accel direct)
  final List<_DemoTracePoint> _demoTracePoints = [];   // trace line history for widget
  static const double _demoSensitivity = 0.08;   // accel → screen scale
  static const int _demoTraceMax = 200;
  static const double _demoDt = 0.01;           // ~100Hz integration

  void _startDemoTimer() {
    _demoTime = 0;
    _demoShotCount = 0;
    _demoLastShotTime = DateTime.now().subtract(const Duration(seconds: 5));
    _demoGyroX = 0;
    _demoGyroY = 0;
    _demoGyroZ = 0;
    _demoAccelX = 0.2;
    _demoAccelY = 0.1;
    _demoAccelZ = 9.81;

    _demoTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_isDemoMode) return;
      _tickDemo();
    });
  }

  void _stopDemoTimer() {
    _demoTimer?.cancel();
    _demoTimer = null;
    // Clear display buffers (UI-only, 200pt rolling window)
    _gyroXData = [];
    _gyroYData = [];
    _gyroZData = [];
    _accelXData = [];
    _accelYData = [];
    _accelZData = [];
    _traceXData = [];
    _traceYData = [];
    _liveTraceX = 0;
    _liveTraceY = 0;
    // Do NOT clear _sessionGyro* — they persist for save/replay.
    // _sessionShots are cleared here because they belong to the demo run;
    // user must re-enter demo or connect hardware to generate new shots.
    _sessionShots = [];
    _latestShot = null;
    notifyListeners();
  }

  // ============================================
  // Demo tick — MantisX-style: accel for dot, gyro integration for trace
  // ============================================

  void _tickDemo() {
    _demoTime += 0.033;
    final now = DateTime.now();

    // Apply shot recoil spike if active
    // Shot phases: arming(0) → trigger(1, gyro+accel spike) → recoil(2-9, decaying spike)
    if (_demoShotPhase > 0 && _demoShotPhase < 10) {
      _demoShotPhase++;
      // Generate realistic shot spike: gyro magnitude 8-15 rad/s, accel magnitude 15-30 m/s²
      final decay = 1.0 - (_demoShotPhase / 10.0);
      final spikeScale = decay * 12.0; // peak ~12 rad/s
      _demoGyroX = (_nextRand() - 0.5) * 2 * spikeScale;
      _demoGyroY = (_nextRand() - 0.5) * 2 * spikeScale;
      _demoGyroZ = (_nextRand() - 0.5) * 2 * spikeScale * 0.6;
      _demoAccelX = (_nextRand() - 0.5) * 2 * 20.0 * decay;
      _demoAccelY = (_nextRand() - 0.5) * 2 * 20.0 * decay;
      _demoAccelZ = 9.81 + (_nextRand() - 0.5) * 2 * 15.0 * decay;
    } else {
      // Base noise: small random gyro drift
      _demoGyroX += (_nextRand() * 0.05 - 0.025);
      _demoGyroY += (_nextRand() * 0.05 - 0.025);
      _demoGyroZ += (_nextRand() * 0.03 - 0.015);
      _demoGyroX = _demoGyroX.clamp(-2.0, 2.0);
      _demoGyroY = _demoGyroY.clamp(-2.0, 2.0);
      _demoGyroZ = _demoGyroZ.clamp(-1.0, 1.0);

      // Live dot: direct accelerometer (no integration)
      _demoAccelX = 0.2 + (_nextRand() * 0.1);
      _demoAccelY = 0.1 + (_nextRand() * 0.1);
    }

    // Integrate gyro → trace path (MantisX style: -gz → X, -gx → Y)
    _demoTraceXPos += (-_demoGyroZ) * _demoDt;
    _demoTraceYPos += (-_demoGyroX) * _demoDt;
    _demoLiveX = _demoAccelX * _demoSensitivity;
    _demoLiveY = _demoAccelY * _demoSensitivity;

    final ts = now.millisecondsSinceEpoch.toDouble();
    _demoTracePoints.add(_DemoTracePoint(_demoTraceXPos, _demoTraceYPos, ts));
    if (_demoTracePoints.length > _demoTraceMax) {
      _demoTracePoints.removeAt(0);
    }

    // Auto-generate shot every 4-8 seconds
    final timeSinceLastShot = now.difference(_demoLastShotTime ?? now).inMilliseconds;
    if (timeSinceLastShot > 4000 + (_nextRand() * 4000).round()) {
      _triggerDemoShot();
      _demoLastShotTime = now;
    }
    _gyroXData = [..._gyroXData, DataPoint(_demoTime, _demoGyroX)];
    _gyroYData = [..._gyroYData, DataPoint(_demoTime, _demoGyroY)];
    _gyroZData = [..._gyroZData, DataPoint(_demoTime, _demoGyroZ)];
    _accelXData = [..._accelXData, DataPoint(_demoTime, _demoAccelX)];
    _accelYData = [..._accelYData, DataPoint(_demoTime, _demoAccelY)];
    _accelZData = [..._accelZData, DataPoint(_demoTime, _demoAccelZ)];

    // Also write to session buffers so demo sessions can be replayed.
    // Session data is NOT cleared on demo stop — only display buffers are.
    _sessionGyroX ??= [];
    _sessionGyroY ??= [];
    _sessionGyroZ ??= [];
    _sessionAccelX ??= [];
    _sessionAccelY ??= [];
    _sessionAccelZ ??= [];
    _sessionGyroX!.add(DataPoint(_demoTime, _demoGyroX));
    _sessionGyroY!.add(DataPoint(_demoTime, _demoGyroY));
    _sessionGyroZ!.add(DataPoint(_demoTime, _demoGyroZ));
    _sessionAccelX!.add(DataPoint(_demoTime, _demoAccelX));
    _sessionAccelY!.add(DataPoint(_demoTime, _demoAccelY));
    _sessionAccelZ!.add(DataPoint(_demoTime, _demoAccelZ));

    // Trace data: integrated gyro (MantisX-style)
    _liveTraceX = _demoTraceXPos;
    _liveTraceY = _demoTraceYPos;
    _traceXData = _demoTracePoints.map((p) => p.x).toList();
    _traceYData = _demoTracePoints.map((p) => p.y).toList();

    if (_gyroXData.length > 200) {
      _gyroXData = _gyroXData.sublist(_gyroXData.length - 200);
      _gyroYData = _gyroYData.sublist(_gyroYData.length - 200);
      _gyroZData = _gyroZData.sublist(_gyroZData.length - 200);
      _accelXData = _accelXData.sublist(_accelXData.length - 200);
      _accelYData = _accelYData.sublist(_accelYData.length - 200);
      _accelZData = _accelZData.sublist(_accelZData.length - 200);
    }

    _uiUpdatesReceived++;
    notifyListeners();
  }

  void _triggerDemoShot() {
    _demoShotCount++;
    _demoShotPhase = 1; // Start recoil spike (next tick will be phase 2-9)

    // Generate random score 60-95
    final score = 60.0 + _nextRand() * 35.0;
    final hold = score * (0.8 + _nextRand() * 0.2);
    final press = score * (0.7 + _nextRand() * 0.3);
    final recoil = score * (0.6 + _nextRand() * 0.4);
    final elev = score * (0.7 + _nextRand() * 0.3);
    final wind = score * (0.7 + _nextRand() * 0.3);

    // Generate phase trace data
    final holdX = List.generate(10, (i) => (_nextRand() - 0.5) * 0.01);
    final holdY = List.generate(10, (i) => (_nextRand() - 0.5) * 0.01);
    final pressX = List.generate(10, (i) => (_nextRand() - 0.5) * 0.02);
    final pressY = List.generate(10, (i) => (_nextRand() - 0.5) * 0.02);
    final recoilX = List.generate(10, (i) => (_nextRand() - 0.5) * 0.03);
    final recoilY = List.generate(10, (i) => (_nextRand() - 0.5) * 0.03);

    final shot = ShotResult(
      timestamp: DateTime.now(),
      totalScore: score,
      holdScore: hold,
      pressScore: press,
      recoilScore: recoil,
      elevationScore: elev,
      windageScore: wind,
      travelDistance: (1 - score / 100) * 0.1,
      peakJerk: (1 - score / 100) * 5,
      firearmType: _settingsProvider?.firearmType ?? FirearmType.pistol,
      trainingMode: _settingsProvider?.trainingMode ?? TrainingMode.dryFire,
      holdX: holdX,
      holdY: holdY,
      pressX: pressX,
      pressY: pressY,
      recoilX: recoilX,
      recoilY: recoilY,
    );

    _sessionShots = [..._sessionShots, shot];
    _latestShot = shot;
    _totalDataPoints++;
    onShotDetected?.call();
  }

  double _nextRand() {
    // Simple pseudo-random using current time for demo
    return ((DateTime.now().microsecondsSinceEpoch % 1000) / 1000.0);
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}

class _DemoTracePoint {
  final double x;
  final double y;
  final double timestamp;
  _DemoTracePoint(this.x, this.y, this.timestamp);
}
