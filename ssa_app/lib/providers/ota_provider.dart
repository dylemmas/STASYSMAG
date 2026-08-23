// ============================================
// File: providers/ota_provider.dart
// ============================================
import 'package:flutter/material.dart';
import '../services/firmware_service.dart';
import 'bluetooth_provider.dart';

enum OtaState {
  idle,
  loading,
  sending,
  verifying,
  rebooting,
  completed,
  failed,
}

class OtaProvider extends ChangeNotifier {
  final FirmwareService _firmwareService;
  final BluetoothProvider _btProvider;

  OtaProvider({
    required FirmwareService firmwareService,
    required BluetoothProvider btProvider,
  })  : _firmwareService = firmwareService,
        _btProvider = btProvider;

  OtaState _state = OtaState.idle;
  double _progress = 0.0;
  String _statusMessage = '';
  String _errorMessage = '';
  int _totalChunks = 0;
  int _sentChunks = 0;

  // Getters
  OtaState get state => _state;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  String get errorMessage => _errorMessage;
  int get totalChunks => _totalChunks;
  int get sentChunks => _sentChunks;

  Future<void> startOta() async {
    _state = OtaState.loading;
    _progress = 0.0;
    _sentChunks = 0;
    _statusMessage = 'Loading firmware...';
    notifyListeners();

    try {
      final firmware = await _firmwareService.loadFirmware();
      print('[OTA] Firmware loaded: ${firmware.sizeBytes} bytes, SHA256: ${firmware.sha256}');
      _statusMessage = 'Starting OTA transfer...';
      notifyListeners();

      // Step 1: Send OTA_START
      print('[OTA] Sending OTA_START with size=${firmware.sizeBytes}');
      final response = await _btProvider.sendOtaStart(firmware.sizeBytes);
      print('[OTA] OTA_START response: $response');
      if (!response.contains('OTA_READY')) {
        throw Exception('OTA_START failed: $response');
      }

      // Step 2: Send chunks in burst mode (no delay between chunks)
      // ESP32 burst mode: sends batched ACKs, drain loop handles overflow via taskYIELD()
      final chunks = _firmwareService.chunkFirmware(firmware.bytes);
      _totalChunks = chunks.length;
      _state = OtaState.sending;

      for (final chunk in chunks) {
        print('[OTA] Sending chunk seq=${chunk.seq}, size=${chunk.data.length}');
        _statusMessage = 'Sending chunk ${chunk.seq + 1}/$_totalChunks...';
        notifyListeners();

        final ack = await _btProvider.sendOtaChunk(chunk.seq, chunk.data);
        print('[OTA] Chunk ${chunk.seq} ACK: $ack');
        if (!ack.contains('OTA_ACK')) {
          // Retry up to 3 times
          bool success = false;
          for (int retry = 0; retry < 3; retry++) {
            await Future.delayed(const Duration(milliseconds: 500));
            final retryAck = await _btProvider.sendOtaChunk(chunk.seq, chunk.data);
            if (retryAck.contains('OTA_ACK')) {
              success = true;
              break;
            }
          }
          if (!success) {
            throw Exception('Chunk ${chunk.seq} failed after 3 retries');
          }
        }

        _sentChunks++;
        _progress = _sentChunks / _totalChunks;
        notifyListeners();

        // 200ms delay between chunks to prevent BT buffer overflow
        await Future.delayed(const Duration(milliseconds: 200));
        // ESP32 drain loop with taskYIELD() prevents BT buffer overflow.
        // Burst ACKs arrive in batches (e.g., 8 chunks → 8 ACKs at once).
      }

      // Step 3: Send OTA_FINISH
      _state = OtaState.verifying;
      _statusMessage = 'Verifying firmware...';
      notifyListeners();

      final finishResponse = await _btProvider.sendOtaFinish(firmware.sha256);
      if (!finishResponse.contains('OTA_COMPLETE')) {
        throw Exception('OTA_FINISH failed: $finishResponse');
      }

      // Step 4: Reboot
      _state = OtaState.rebooting;
      _statusMessage = 'Rebooting device...';
      notifyListeners();

      await _btProvider.sendRebootCommand();
      _state = OtaState.completed;
      _progress = 1.0;
      _statusMessage = 'Update complete!';
      notifyListeners();
    } catch (e) {
      _state = OtaState.failed;
      _errorMessage = e.toString();
      _statusMessage = 'Update failed';
      // Reset BT provider from OTA mode on failure
      _btProvider.resetFromOtaMode();
      notifyListeners();
    }
  }

  void reset() {
    _state = OtaState.idle;
    _progress = 0.0;
    _statusMessage = '';
    _errorMessage = '';
    _sentChunks = 0;
    _totalChunks = 0;
    notifyListeners();
  }
}
