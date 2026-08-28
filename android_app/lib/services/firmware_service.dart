import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

class FirmwareInfo {
  final String version;
  final int sizeBytes;
  final Uint8List bytes;
  final String sha256;

  FirmwareInfo({
    required this.version,
    required this.sizeBytes,
    required this.bytes,
    required this.sha256,
  });
}

class FirmwareService {
  static const String _assetPath = 'assets/firmware/stasys_fw.bin';
  static const String expectedVersion = '1.4.0'; // Update on each release
  // 128 bytes raw → ~172 bytes base64 → ~200 bytes BT transfer. Fits in 200-byte buffer.
  static const int chunkSize = 128;

  Uint8List? _cachedFirmware;
  String? _cachedSha256;

  Future<FirmwareInfo> loadFirmware() async {
    if (_cachedFirmware != null) {
      return FirmwareInfo(
        version: expectedVersion,
        sizeBytes: _cachedFirmware!.length,
        bytes: _cachedFirmware!,
        sha256: _cachedSha256!,
      );
    }

    final ByteData data = await rootBundle.load(_assetPath);
    final Uint8List bytes = data.buffer.asUint8List();
    final String sha256Hash = sha256.convert(bytes).toString();

    _cachedFirmware = bytes;
    _cachedSha256 = sha256Hash;

    return FirmwareInfo(
      version: expectedVersion,
      sizeBytes: bytes.length,
      bytes: bytes,
      sha256: sha256Hash,
    );
  }

  List<OtaChunk> chunkFirmware(Uint8List bytes) {
    final List<OtaChunk> chunks = [];
    int offset = 0;
    int seq = 0;
    while (offset < bytes.length) {
      final int end = (offset + chunkSize > bytes.length)
          ? bytes.length
          : offset + chunkSize;
      final Uint8List chunkData = bytes.sublist(offset, end);
      chunks.add(OtaChunk(seq: seq, data: chunkData));
      offset = end;
      seq++;
    }
    return chunks;
  }
}

class OtaChunk {
  final int seq;
  final Uint8List data;
  OtaChunk({required this.seq, required this.data});
}
