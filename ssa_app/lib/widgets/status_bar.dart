// ============================================
// File: widgets/status_bar.dart (FIXED OVERFLOW)
// ============================================
import 'package:flutter/material.dart';

class StatusBar extends StatelessWidget {
  final bool isConnected;
  final String deviceName;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const StatusBar({
    super.key,
    required this.isConnected,
    required this.deviceName,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Gunakan Expanded agar Row kiri mengambil sisa ruang yang ada
          // dan tidak memaksa melebar keluar layar
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.bluetooth,
                  color: isConnected ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                // Gunakan Flexible agar teks bisa memendek (ellipsis) jika kepanjangan
                Flexible(
                  child: Text(
                    isConnected ? 'Connected to $deviceName' : 'Disconnected',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis, // Tambahkan ... jika kepanjangan
                    maxLines: 1, // Batasi 1 baris
                  ),
                ),
              ],
            ),
          ),
          // Beri jarak sedikit antara teks dan tombol
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: isConnected ? onDisconnect : onConnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: isConnected ? Colors.red : Colors.green,
              // Perkecil padding tombol sedikit jika perlu
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(isConnected ? 'Disconnect' : 'Connect'),
          ),
        ],
      ),
    );
  }
}
