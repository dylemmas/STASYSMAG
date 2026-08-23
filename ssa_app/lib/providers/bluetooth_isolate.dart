import 'dart:isolate';
import 'dart:typed_data';
//import 'dart:convert';
import 'package:crypto/crypto.dart';

class BluetoothIsolateConfig {
  final SendPort mainSendPort;

  BluetoothIsolateConfig(this.mainSendPort);
}

class BluetoothIsolate {
  // ignore: constant_identifier_names
  static const int PACKET_SIZE = 28;
  // ignore: constant_identifier_names
  static const int HEADER_1 = 0xAA;
  // ignore: constant_identifier_names
  static const int HEADER_2 = 0x55;

  static void entryPoint(BluetoothIsolateConfig config) {
    final isolateReceivePort = ReceivePort();
    config.mainSendPort.send(isolateReceivePort.sendPort);

    final List<int> binaryBuffer = [];
    bool handshakeDone = false;

    isolateReceivePort.listen((message) {
      // =============================
      // DATA BINER DARI BLUETOOTH
      // =============================
      if (message is Uint8List) {
        binaryBuffer.addAll(message);

        while (binaryBuffer.length >= PACKET_SIZE) {
          // Cari header
          if (binaryBuffer[0] != HEADER_1 ||
              binaryBuffer[1] != HEADER_2) {
            binaryBuffer.removeAt(0);
            continue;
          }

          final packet = binaryBuffer.sublist(0, PACKET_SIZE);
          binaryBuffer.removeRange(0, PACKET_SIZE);

          // =============================
          // VERIFIKASI CHECKSUM
          // =============================
          final payload = packet.sublist(2, PACKET_SIZE - 4);
          final checksumRecv =
              ByteData.sublistView(Uint8List.fromList(packet),
                      PACKET_SIZE - 4, PACKET_SIZE)
                  .getUint32(0, Endian.little);

          final checksumCalc = _crc32(payload);

          if (checksumRecv != checksumCalc) {
            config.mainSendPort.send({
              'type': 'checksum_error',
            });
            continue;
          }

          // =============================
          // HANDSHAKE
          // =============================
          if (!handshakeDone) {
            handshakeDone = true;
            config.mainSendPort.send({
              'type': 'handshake_ok',
            });
          }

          // =============================
          // KIRIM DATA VALID KE MAIN
          // =============================
          config.mainSendPort.send({
            'type': 'data',
            'payload': payload,
          });
        }

        // proteksi memory
        if (binaryBuffer.length > 4000) {
          binaryBuffer.clear();
        }
      }

      // =============================
      // COMMAND DARI MAIN THREAD
      // =============================
      else if (message is String) {
        if (message == 'RESET_HANDSHAKE') {
          handshakeDone = false;
        } else if (message == 'STOP') {
          isolateReceivePort.close();
        }
      }
    });
  }

  static int _crc32(List<int> data) {
    final hash = md5.convert(data);
    return ByteData.sublistView(Uint8List.fromList(hash.bytes))
        .getUint32(0, Endian.little);
  }
}
