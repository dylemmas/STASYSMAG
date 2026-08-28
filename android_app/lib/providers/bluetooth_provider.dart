import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import './sensor_data_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:async';

// ================= CONNECTION PHASE =================
// Upstream firmware uses text-based auth, then binary float packets.
enum _ConnectionPhase {
  waitingForReady,  // Waiting for "READY\n" from ESP32
  waitingForHash,   // Sent challenge, waiting for SHA256 hex response
  streaming,        // Auth succeeded, receiving 0xAA 0xBB binary packets
  otaMode,          // Dedicated OTA mode — pure text parser, no binary
}

// Separate text buffer for OTA mode — unlimited, no trim, no collision
String _otaTextBuffer = '';

const String _secretKey = "12ebaf10h12fa9123z21sti";

class BluetoothProvider extends ChangeNotifier {

  SensorDataProvider _sensorDataProvider;
  StreamSubscription<Uint8List>? _dataSubscription;

  BluetoothProvider({required SensorDataProvider sensorDataProvider})
      : _sensorDataProvider = sensorDataProvider;

  set sensorDataProvider(SensorDataProvider provider) {
    _sensorDataProvider = provider;
  }

  BluetoothDevice? _selectedDevice;
  BluetoothConnection? _connection;
  List<BluetoothDevice> _devicesList = [];
  bool _isConnected = false;
  bool _isScanning = false;
  bool _isAuthenticated = false;
  String _deviceName = '';
  _ConnectionPhase _connectionPhase = _ConnectionPhase.waitingForReady;

  // Binary parser state
  static const int _SYNC0 = 0xAA;
  static const int _SYNC1 = 0xBB;
  // STASYS_FW packet structure (31 bytes):
  // [0-1] sync (0xAA, 0xBB)
  // [2-5] ax, [6-9] ay, [10-13] az (float, m/s²)
  // [14-17] gx, [18-21] gy, [22-25] gz (float, rad/s)
  // [26-27] piezo (uint16 ADC peak)
  // [28] battery (uint8 %)
  // [29-30] crc16 (CRC-16 CCITT over bytes 2-28)
  static const int _PACKET_SIZE = 31;
  final List<int> _binaryBuffer = [];

  // Statistics
  int _totalPacketsReceived = 0;
  int _checksumErrorsCount = 0;

  // Getters
  BluetoothDevice? get selectedDevice => _selectedDevice;
  BluetoothConnection? get connection => _connection;
  List<BluetoothDevice> get devicesList => List.unmodifiable(_devicesList);
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  bool get isAuthenticated => _isAuthenticated;
  String get connectedDeviceName => _deviceName.isNotEmpty ? _deviceName : (_selectedDevice?.name ?? 'STASYS');
  int get totalPacketsReceived => _totalPacketsReceived;
  int get invalidPacketsCount => 0;  // Not tracked in upstream protocol
  int get checksumErrorsCount => _checksumErrorsCount;
  bool get sessionActive => false;  // Upstream firmware has no session concept
  int get sessionId => 0;
  int get shotCount => 0;

  double get packetLossPercentage {
    if (_totalPacketsReceived == 0) return 0.0;
    return (_checksumErrorsCount / _totalPacketsReceived) * 100;
  }

  // ================= DEBUG =================
  static int _debugRxPrinted = 0;
  static int _debugBinaryPrinted = 0;

  // ================= DUAL-MODE DATA RECEPTION =================
  void _onDataReceived(Uint8List data) {
    if (_debugRxPrinted < 3) {
      debugPrint('[RX] raw len=${data.length}: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      _debugRxPrinted++;
    }

    switch (_connectionPhase) {
      case _ConnectionPhase.waitingForReady:
      case _ConnectionPhase.waitingForHash:
        _handleTextData(data);
        break;
      case _ConnectionPhase.streaming:
        _handleBinaryData(data);
        break;
      case _ConnectionPhase.otaMode:
        _handleOtaData(data);
        break;
    }
  }

  // ================= TEXT-BASED AUTH (upstream firmware) =================
  String _textBuffer = '';

  void _handleTextData(Uint8List data) {
    _textBuffer += String.fromCharCodes(data);

    while (_textBuffer.contains('\n')) {
      int nlIndex = _textBuffer.indexOf('\n');
      String line = _textBuffer.substring(0, nlIndex).trim();
      _textBuffer = _textBuffer.substring(nlIndex + 1);

      if (line.isEmpty) continue;

      if (_connectionPhase == _ConnectionPhase.waitingForReady) {
        if (line == 'READY') {
          debugPrint('[BT] Received READY, sending auth challenge...');
          _sendText('AUTH_CHALLENGE');
          _connectionPhase = _ConnectionPhase.waitingForHash;
        }
      } else if (_connectionPhase == _ConnectionPhase.waitingForHash) {
        if (line.length == 64) {
          debugPrint('[BT] Received hash response (${line.length} chars)');
          String toHash = 'AUTH_CHALLENGE' + _secretKey;
          String computedHash = sha256.convert(utf8.encode(toHash)).toString();
          if (line.toLowerCase() == computedHash.toLowerCase()) {
            debugPrint('[BT] Auth verified, switching to streaming mode');
            _isAuthenticated = true;
            _connectionPhase = _ConnectionPhase.streaming;
            _textBuffer = '';
            notifyListeners();
            _sensorDataProvider.requestFullSync();
          } else {
            debugPrint('[BT] Auth FAILED: expected=$computedHash, got=$line');
          }
        }
      }
    }
  }

  void _sendText(String text) {
    if (_connection == null || !_isConnected) return;
    try {
      _connection!.output.add(Uint8List.fromList('$text\n'.codeUnits));
      _connection!.output.allSent;
    } catch (e) {
      debugPrint('Error sending text: $e');
    }
  }

  // ================= OTA MODE: PURE TEXT PARSER =================
  // No binary parsing, no buffer trim, no collision with streaming mode.
  void _handleOtaData(Uint8List data) {
    // Accumulate raw bytes into dedicated OTA buffer (unbounded)
    for (int b in data) {
      _otaTextBuffer += String.fromCharCode(b);
    }
  }

  void resetFromOtaMode() {
    _connectionPhase = _ConnectionPhase.streaming;
    _otaTextBuffer = '';
  }

  void exitOtaMode() {
    _connectionPhase = _ConnectionPhase.streaming;
    _otaTextBuffer = '';
  }

  // ================= BINARY PACKET PARSER (31-byte float packets) =================
  void _handleBinaryData(Uint8List data) {
    // Also accumulate printable ASCII for OTA text responses during streaming
    for (int b in data) {
      if (b >= 32 && b <= 126 || b == 10 || b == 13) {
        _textBuffer += String.fromCharCode(b);
      }
    }
    // Trim text buffer to last 2048 chars to prevent unbounded growth
    if (_textBuffer.length > 2048) {
      _textBuffer = _textBuffer.substring(_textBuffer.length - 2048);
    }

    for (int b in data) {
      _binaryBuffer.add(b);

      if (_binaryBuffer.length == 1) {
        if (b != _SYNC0) {
          _binaryBuffer.clear();
          _binaryBuffer.add(b);
        }
      } else if (_binaryBuffer.length == 2) {
        if (b != _SYNC1) {
          _binaryBuffer.clear();
          if (b == _SYNC0) {
            _binaryBuffer.add(b);
          }
        }
      }
      if (_binaryBuffer.length == _PACKET_SIZE) {
        if (_binaryBuffer[0] == _SYNC0 && _binaryBuffer[1] == _SYNC1) {
          if (_verifyCrc16(_binaryBuffer)) {
            _parseBinaryPacket(_binaryBuffer);
            _totalPacketsReceived++;
          } else {
            _checksumErrorsCount++;
            if (_debugBinaryPrinted < 3) {
              // Compute CRC-16 for debugging
              int crc = 0xFFFF;
              for (int i = 2; i < 29; i++) {
                crc ^= _binaryBuffer[i] << 8;
                for (int j = 0; j < 8; j++) {
                  if ((crc & 0x8000) != 0) {
                    crc = (crc << 1) ^ 0x1021;
                  } else {
                    crc <<= 1;
                  }
                }
              }
              crc &= 0xFFFF;
              int receivedCrc = (_binaryBuffer[30] << 8) | _binaryBuffer[29];
              debugPrint('[BT] CRC16 fail: got=$receivedCrc.toRadixString(16), expected=$crc.toRadixString(16), bytes=${_binaryBuffer.sublist(2, 29).map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
              _debugBinaryPrinted++;
            }
          }
        }
        _binaryBuffer.clear();
      }
    }
  }

  bool _verifyCrc16(List<int> buf) {
    // CRC-16 CCITT over bytes 2-28 (27 bytes: floats + piezo + battery)
    // Initial: 0xFFFF, Polynomial: 0x1021
    int crc = 0xFFFF;
    for (int i = 2; i < 29; i++) {
      crc ^= buf[i] << 8;
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x8000) != 0) {
          crc = (crc << 1) ^ 0x1021;
        } else {
          crc <<= 1;
        }
      }
    }
    crc &= 0xFFFF;

    int receivedCrc = (buf[30] << 8) | buf[29];
    return crc == receivedCrc;
  }

  void _parseBinaryPacket(List<int> buf) {
    ByteData bd = ByteData.sublistView(Uint8List.fromList(buf));

    // [0-1] sync, [2-5] ax, [6-9] ay, [10-13] az, [14-17] gx, [18-21] gy, [22-25] gz, [26-27] piezo, [28] battery, [29-30] crc16
    double ax = bd.getFloat32(2, Endian.little);
    double ay = bd.getFloat32(6, Endian.little);
    double az = bd.getFloat32(10, Endian.little);
    double gx = bd.getFloat32(14, Endian.little);
    double gy = bd.getFloat32(18, Endian.little);
    double gz = bd.getFloat32(22, Endian.little);
    int piezo = bd.getUint16(26, Endian.little);
    int battery = buf[28];

    if (_isValidSensorData(ax, ay, az, gx, gy, gz)) {
      _sensorDataProvider.updateAllData(
        ax: ax, ay: ay, az: az,
        gx: gx, gy: gy, gz: gz,
        battery: battery,
        piezo: piezo,
      );
    }
  }

  bool _isValidSensorData(double ax, double ay, double az, double gx, double gy, double gz) {
    const double maxAccel = 100.0; // 10g — real recoil can hit 30-50 m/s²
    if (ax.abs() > maxAccel || ay.abs() > maxAccel || az.abs() > maxAccel) return false;
    const double maxGyro = 50.0; // 50 rad/s — real shots can exceed 10 rad/s
    if (gx.abs() > maxGyro || gy.abs() > maxGyro || gz.abs() > maxGyro) return false;
    if (ax.isNaN || ay.isNaN || az.isNaN || gx.isNaN || gy.isNaN || gz.isNaN) return false;
    if (ax.isInfinite || ay.isInfinite || az.isInfinite || gx.isInfinite || gy.isInfinite || gz.isInfinite) return false;
    return true;
  }

  // ================= BLUETOOTH LIFECYCLE =================
  Future<void> initializeBluetooth() async {
    bool permissionGranted = await _requestBluetoothPermissions();
    if (permissionGranted) {
      await getBondedDevices();
    }
  }

  Future<bool> _requestBluetoothPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  Future<void> getBondedDevices() async {
    try {
      List<BluetoothDevice> bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      _devicesList = bonded.where((d) => (d.name ?? '').toLowerCase().contains('stasys')).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error getting bonded devices: $e');
    }
  }

  Future<void> startScan() async {
    bool permissionGranted = await _requestBluetoothPermissions();
    if (!permissionGranted) return;

    _isScanning = true;
    _devicesList.clear();
    notifyListeners();

    try {
      FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
        if (!(r.device.name ?? '').toLowerCase().contains('stasys')) return;
        final existingIndex = _devicesList.indexWhere((d) => d.address == r.device.address);
        if (existingIndex >= 0) {
          _devicesList[existingIndex] = r.device;
        } else {
          _devicesList.add(r.device);
        }
        notifyListeners();
      }).onDone(() {
        _isScanning = false;
        notifyListeners();
      });
    } catch (e) {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    // Force disconnect any existing connection first
    await _forceDisconnect();

    _selectedDevice = device;
    _connectionPhase = _ConnectionPhase.waitingForReady;
    _binaryBuffer.clear();
    _textBuffer = '';
    _isAuthenticated = false;
    _totalPacketsReceived = 0;
    _checksumErrorsCount = 0;
    _deviceName = device.name ?? 'STASYS';
    notifyListeners();

    const maxRetries = 3;
    const delayBetweenRetries = Duration(seconds: 2);

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        debugPrint('[BT] Retry $attempt/${maxRetries} for ${device.address}');
        // Force disconnect before retry
        await _forceDisconnect();
        await Future.delayed(delayBetweenRetries);
      }

      try {
        debugPrint('[BT] Connecting to ${device.address} (attempt ${attempt + 1})');
        BluetoothConnection conn = await BluetoothConnection.toAddress(device.address);
        _connection = conn;
        _isConnected = true;
        notifyListeners();

        _dataSubscription = _connection!.input!.listen(
          _onDataReceived,
          onError: (error) {
            debugPrint('Stream error: $error');
            disconnect();
          },
          onDone: () {
            debugPrint('Connection closed by remote device');
            _handleDisconnection();
          },
          cancelOnError: false,
        );

        // Wait up to 15s for auth to complete
        int waited = 0;
        while (!_isAuthenticated && waited < 15000) {
          await Future.delayed(const Duration(milliseconds: 300));
          waited += 300;
        }

        if (_isAuthenticated) {
          debugPrint('[BT] Connection and auth successful');
          return true;
        } else {
          debugPrint('[BT] Auth timeout after ${waited}ms');
          await disconnect();
          if (attempt < maxRetries) continue;
          return false;
        }
      } catch (e) {
        debugPrint('[BT] Connection attempt ${attempt + 1} failed: $e');
        _isConnected = false;
        if (attempt < maxRetries) {
          continue;
        }

        _isAuthenticated = false;
        notifyListeners();
        return false;
      }
    }

    return false;
  }

  /// Forcefully close any existing connection and clear state
  Future<void> _forceDisconnect() async {
    try {
      if (_dataSubscription != null) {
        await _dataSubscription!.cancel();
        _dataSubscription = null;
      }
      if (_connection != null) {
        await _connection!.close();
        _connection = null;
      }
      _isConnected = false;
      _isAuthenticated = false;
      _connectionPhase = _ConnectionPhase.waitingForReady;
      _textBuffer = '';
      _binaryBuffer.clear();
      debugPrint('[BT] Force disconnect completed');
    } catch (e) {
      debugPrint('[BT] Force disconnect error: $e');
    }
  }

  void _handleDisconnection() {
    _isConnected = false;
    _isAuthenticated = false;
    _connectionPhase = _ConnectionPhase.waitingForReady;
    _connection = null;
    _selectedDevice = null;
    _binaryBuffer.clear();
    _textBuffer = '';
    _sensorDataProvider.resetTimeReference();
    notifyListeners();
  }

  Future<void> sendDataToESP32(String data) async {
    if (_connection != null && _isConnected) {
      try {
        _connection!.output.add(Uint8List.fromList(data.codeUnits));
        await _connection!.output.allSent;
      } catch (e) {
        debugPrint('Error sending data: $e');
      }
    }
  }

  Future<void> disconnect() async {
    if (_dataSubscription != null) {
      await _dataSubscription!.cancel();
      _dataSubscription = null;
    }

    if (_connection != null) {
      await _connection!.close();
      _isConnected = false;
      _isAuthenticated = false;
      _connectionPhase = _ConnectionPhase.waitingForReady;
      _connection = null;
      _selectedDevice = null;

      debugPrint('=== CONNECTION STATISTICS ===');
      debugPrint('Total packets: $_totalPacketsReceived');
      debugPrint('Checksum errors: $_checksumErrorsCount');
      debugPrint('Packet loss: ${packetLossPercentage.toStringAsFixed(2)}%');

      _sensorDataProvider.resetTimeReference();
      notifyListeners();
    }
  }

  // ================= OTA (Over-The-Air Firmware Update) =================

  /// Sends OTA_START:size=N and waits for OTA_READY response.
  Future<String> sendOtaStart(int totalSize) async {
    if (_connection == null || !_isConnected) return 'ERROR:not_connected';
    // CRITICAL: Clear buffer BEFORE switching phase to prevent RangeError
    _otaTextBuffer = '';
    _connectionPhase = _ConnectionPhase.otaMode;
    try {
      _connection!.output.add(Uint8List.fromList('OTA_START:size=$totalSize\n'.codeUnits));
      await _connection!.output.allSent;
      return await _waitForOtaResponse(timeoutMs: 5000);
    } catch (e) {
      resetFromOtaMode();
      return 'ERROR:$e';
    }
  }

  void _exitOtaMode() {
    _connectionPhase = _ConnectionPhase.streaming;
    _otaTextBuffer = '';
  }

    /// Sends one OTA chunk as base64-encoded data. Returns 'OTA_ACK:seq=N' on success.
  Future<String> sendOtaChunk(int seq, Uint8List chunkData) async {
    if (_connection == null || !_isConnected) return 'OTA_NAK:seq=$seq:err';
    try {
      // Send the chunk immediately (no flow control wait)
      final base64Data = base64.encode(chunkData);
      final cmd = 'OTA_DATA:seq=$seq:base64=$base64Data\n';
      _connection!.output.add(Uint8List.fromList(cmd.codeUnits));
      await _connection!.output.allSent;

      // Wait for ACK
      return await _waitForOtaResponse(timeoutMs: 5000);
    } catch (e) {
      print('[OTA] sendOtaChunk($seq) exception: $e');
      return 'OTA_NAK:seq=$seq:err';
    }
  }

  /// Sends OTA_FINISH with SHA256 hash and waits for OTA_COMPLETE.
  Future<String> sendOtaFinish(String sha256) async {
    if (_connection == null || !_isConnected) return 'ERROR:not_connected';
    try {
      _connection!.output.add(Uint8List.fromList('OTA_FINISH:sha256=$sha256\n'.codeUnits));
      await _connection!.output.allSent;
      final response = await _waitForOtaResponse(timeoutMs: 10000);
      // Exit OTA mode after finish (success or fail)
      _exitOtaMode();
      return response;
    } catch (e) {
      _exitOtaMode();
      return 'ERROR:$e';
    }
  }

  /// Sends REBOOT command.
  Future<void> sendRebootCommand() async {
    if (_connection == null || !_isConnected) return;
    try {
      _connection!.output.add(Uint8List.fromList('REBOOT\n'.codeUnits));
      await _connection!.output.allSent;
    } catch (_) {}
  }

  /// Queries firmware version from ESP32.
  Future<String?> getFirmwareVersion() async {
    if (_connection == null || !_isConnected) return null;
    try {
      _connection!.output.add(Uint8List.fromList('GET_VERSION\n'.codeUnits));
      await _connection!.output.allSent;
      final response = await _waitForOtaResponse(timeoutMs: 3000);
      if (response.startsWith('VERSION=')) {
        return response.substring(8).trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Internal: waits for an OTA text response from the accumulated _otaTextBuffer (in OTA mode) or _textBuffer (in streaming mode).
  /// Polls buffer for OTA response patterns.
  Future<String> _waitForOtaResponse({required int timeoutMs}) async {
    int waited = 0;
    while (waited < timeoutMs) {
      await Future.delayed(const Duration(milliseconds: 50));
      waited += 50;

      // Use dedicated OTA buffer if in OTA mode, otherwise use shared _textBuffer
      String buffer = _connectionPhase == _ConnectionPhase.otaMode ? _otaTextBuffer : _textBuffer;

      // Check buffer for OTA response patterns
      if (buffer.contains('VERSION=') ||
          buffer.contains('OTA_READY') ||
          buffer.contains('OTA_ACK:') ||
          buffer.contains('OTA_NAK:') ||
          buffer.contains('OTA_COMPLETE') ||
          buffer.contains('OTA_ERR:') ||
          buffer.contains('OTA_ABORTED') ||
          buffer.contains('OTA_TIMEOUT')) {
        // Find the last newline-delimited line that matches OTA patterns
        String searchFor = '';
        if (buffer.contains('VERSION=')) {
          searchFor = 'VERSION=';
        } else if (buffer.contains('OTA_COMPLETE')) {
          searchFor = 'OTA_COMPLETE';
        } else if (buffer.contains('OTA_READY')) {
          searchFor = 'OTA_READY';
        } else if (buffer.contains('OTA_ERR:')) {
          searchFor = 'OTA_ERR:';
        } else if (buffer.contains('OTA_ACK:')) {
          searchFor = 'OTA_ACK:';
        } else if (buffer.contains('OTA_NAK:')) {
          searchFor = 'OTA_NAK:';
        } else if (buffer.contains('OTA_ABORTED')) {
          searchFor = 'OTA_ABORTED';
        } else if (buffer.contains('OTA_TIMEOUT')) {
          searchFor = 'OTA_TIMEOUT';
        }

        int idx = buffer.lastIndexOf(searchFor);
        if (idx >= 0) {
          int endIdx = buffer.indexOf('\n', idx);
          if (endIdx < 0) {
            endIdx = buffer.length;
          }
          String line = buffer.substring(idx, endIdx).trim();
          // Clear up to this point to prevent accumulation
          if (_connectionPhase == _ConnectionPhase.otaMode) {
            _otaTextBuffer = buffer.substring(endIdx + 1);
          } else {
            _textBuffer = buffer.substring(endIdx + 1);
          }
          return line;
        }
      }
    }
    throw Exception('BT response timeout');
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _dataSubscription = null;
    _connection?.dispose();
    _connection = null;
    super.dispose();
  }
}
