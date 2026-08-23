import 'dart:isolate';
import '../models/data_models.dart';

/// Kelas untuk menampung data yang sudah diproses oleh isolate.
class ProcessedData {
  final DataPoint accelX, accelY, accelZ;
  final DataPoint gyroX, gyroY, gyroZ;

  ProcessedData({
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
  });
}

/// Pesan untuk mengirim data mentah ke isolate.
class IsolateData {
  final String data;
  final double time;

  IsolateData(this.data, this.time);
}

/// Konfigurasi awal untuk isolate, termasuk bias kalibrasi.
class IsolateConfig {
  final SendPort sendPort;
  final List<double> accelBias;
  final List<double> gyroBias;

  IsolateConfig({
    required this.sendPort,
    required this.accelBias,
    required this.gyroBias,
  });
}

/// Fungsi utama yang akan dijalankan di isolate.
///
/// Fungsi ini mendengarkan data mentah, memprosesnya, dan mengirim
/// kembali data yang sudah matang ke thread utama.
void dataProcessingIsolate(IsolateConfig config) {
  final receivePort = ReceivePort();
  config.sendPort.send(receivePort.sendPort);

  receivePort.listen((dynamic message) {
    if (message is IsolateData) {
      try {
        final values = message.data.split(',').map((e) => double.tryParse(e) ?? 0.0).toList();
        if (values.length == 6) {
          final correctedAx = values[0] - config.accelBias[0];
          final correctedAy = values[1] - config.accelBias[1];
          final correctedAz = values[2] - config.accelBias[2];
          final correctedGx = values[3] - config.gyroBias[0];
          final correctedGy = values[4] - config.gyroBias[1];
          final correctedGz = values[5] - config.gyroBias[2];

          final processedData = ProcessedData(
            accelX: DataPoint(message.time, correctedAx),
            accelY: DataPoint(message.time, correctedAy),
            accelZ: DataPoint(message.time, correctedAz),
            gyroX: DataPoint(message.time, correctedGx),
            gyroY: DataPoint(message.time, correctedGy),
            gyroZ: DataPoint(message.time, correctedGz),
          );
          config.sendPort.send(processedData);
        }
      } catch (e) {
        // Kirim error jika ada, untuk debugging
        config.sendPort.send('Error parsing data: ${e.toString()}');
      }
    }
  });
}
