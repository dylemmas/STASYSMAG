// // File: services/sensor_data_stream.dart (VERSI FINAL DENGAN PERBAIKAN CRASH)
// import 'dart:async';
// import 'package:flutter/material.dart';

// class SensorStreamService {
//   static final SensorStreamService _instance = SensorStreamService._internal();
//   factory SensorStreamService() => _instance;
//   SensorStreamService._internal();

//   final _dataController = StreamController<SensorSample>.broadcast();
//   Stream<SensorSample> get dataStream => _dataController.stream;

//   final _calibrationController = StreamController<int>.broadcast();
//   Stream<int> get calibrationStream => _calibrationController.stream;

//   int _lastKnownBatteryLevel = 0;

//   bool _isCalibrating = false;
//   final List<List<double>> _calibrationSamples = [];
//   final int _samplesToCollect = 100;
//   List<double> _gyroBias = [0.0, 0.0, 0.0];
//   List<double> _accelBias = [0.0, 0.0, 0.0];
//   final Stopwatch _stopwatch = Stopwatch();

//   bool _isCalibrated = false;
//   bool get isCalibrated => _isCalibrated;

//   void startCalibration() {
//     if (_isCalibrating) return;
//     _isCalibrating = true;
//     _isCalibrated = false;
//     _calibrationSamples.clear();
//     _calibrationController.add(0);
//     debugPrint("Kalibrasi dimulai...");
//   }

//   void _finishCalibration() {
//     _isCalibrating = false;
//     if (_calibrationSamples.isEmpty) return;

//     _gyroBias = [0.0, 0.0, 0.0];
//     _accelBias = [0.0, 0.0, 0.0];

//     for (var sample in _calibrationSamples) {
//       _gyroBias[0] += sample[0]; _gyroBias[1] += sample[1]; _gyroBias[2] += sample[2];
//       _accelBias[0] += sample[3]; _accelBias[1] += sample[4]; _accelBias[2] += sample[5];
//     }

//     int count = _calibrationSamples.length;
//     _gyroBias = _gyroBias.map((b) => b / count).toList();
//     _accelBias = _accelBias.map((b) => b / count).toList();

//     _isCalibrated = true;
//     _calibrationController.add(_samplesToCollect);
//     debugPrint("Kalibrasi selesai. GyroBias: $_gyroBias");
//   }

//   // PERBAIKAN UTAMA: Menangani data sensor dengan lebih robust
//   void processESP32Data(String data) {
//     try {
//       if (!_stopwatch.isRunning) _stopwatch.start();

//       debugPrint("Menerima data mentah: $data");

//       final parts = data.trim().split(',');

//       // Validasi format data
//       if (parts.length != 6) {
//         debugPrint("Format data sensor salah. Diharapkan 6 nilai, diterima ${parts.length}.");
//         return;
//       }

//       // Parse data dengan error handling yang lebih baik
//       final List<double> values = [];
//       for (int i = 0; i < parts.length; i++) {
//         final parsed = double.tryParse(parts[i]);
//         if (parsed == null) {
//           debugPrint("Error parsing nilai ke-$i: '${parts[i]}' bukan angka valid");
//           return;
//         }
//         values.add(parsed);
//       }

//       // Urutan dari ESP32: ax,ay,az,gx,gy,gz
//       // Kita reorder ke: gx,gy,gz,ax,ay,az
//       final reading = [values[3], values[4], values[5], values[0], values[1], values[2]];

//       if (_isCalibrating) {
//         _calibrationSamples.add(reading);
//         _calibrationController.add(_calibrationSamples.length);
//         debugPrint("Mode Kalibrasi: Mengumpulkan sampel ke-${_calibrationSamples.length}");

//         if (_calibrationSamples.length >= _samplesToCollect) {
//           _finishCalibration();
//         }
//       } else {
//         debugPrint("Mode Normal: Mengirim data ke grafik...");

//         // PERBAIKAN: Cek apakah controller masih bisa digunakan
//         if (_dataController.isClosed) {
//           debugPrint("Warning: DataController sudah ditutup, tidak bisa mengirim data");
//           return;
//         }

//         final sensorSample = SensorSample(
//           timestamp: _stopwatch.elapsed.inMilliseconds / 1000.0,
//           gx: reading[0] - _gyroBias[0],
//           gy: reading[1] - _gyroBias[1],
//           gz: reading[2] - _gyroBias[2],
//           ax: reading[3] - _accelBias[0],
//           ay: reading[4] - _accelBias[1],
//           az: reading[5] - _accelBias[2],
//           batteryLevel: _lastKnownBatteryLevel,
//         );

//         // PERBAIKAN: Validasi data sebelum mengirim
//         if (sensorSample.timestamp.isFinite &&
//             sensorSample.gx.isFinite && sensorSample.gy.isFinite && sensorSample.gz.isFinite &&
//             sensorSample.ax.isFinite && sensorSample.ay.isFinite && sensorSample.az.isFinite) {

//           _dataController.add(sensorSample);
//           debugPrint("Data valid dikirim: timestamp=${sensorSample.timestamp}");
//         } else {
//           debugPrint("Data tidak valid (NaN atau infinite), diabaikan");
//         }
//       }
//     } catch (e, stackTrace) {
//       debugPrint("Error parsing data sensor di SensorStreamService: $e");
//       debugPrint("StackTrace: $stackTrace");
//       debugPrint("Data mentah yang menyebabkan error: '$data'");
//     }
//   }

//   // PERBAIKAN: Method untuk set battery level dari sumber lain
//   void updateBatteryLevel(int level) {
//     if (level >= 0 && level <= 100) {
//       _lastKnownBatteryLevel = level;
//       debugPrint("Battery level diupdate: $level%");
//     }
//   }

//   void dispose() {
//     debugPrint("SensorStreamService dispose() dipanggil");

//     if (!_dataController.isClosed) {
//       _dataController.close();
//     }

//     if (!_calibrationController.isClosed) {
//       _calibrationController.close();
//     }

//     _stopwatch.stop();
//   }
// }
