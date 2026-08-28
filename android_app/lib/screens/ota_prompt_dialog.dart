import 'package:flutter/material.dart';

class OtaPromptDialog extends StatelessWidget {
  final String currentVersion;
  final String newVersion;
  final VoidCallback onUpdate;

  const OtaPromptDialog({
    super.key,
    required this.currentVersion,
    required this.newVersion,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2A2A2A), width: 1),
      ),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B3D).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.system_update_alt,
              color: Color(0xFFFF6B3D),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Firmware Update',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version $newVersion tersedia untuk STASYS kamu.',
            style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Column(
              children: [
                _versionRow('Current', currentVersion, const Color(0xFFFFB693)),
                const Divider(color: Color(0xFF2A2A2A), height: 20),
                _versionRow('New', newVersion, const Color(0xFF00D4FF)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B3D).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFFF6B3D).withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6B3D), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Jangan putuskan koneksi Bluetooth saat update berlangsung.',
                    style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: onUpdate,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B3D),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Update Now'),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );
  }

  Widget _versionRow(String label, String version, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
        ),
        Row(
          children: [
            Text(
              'v',
              style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 13),
            ),
            Text(
              version,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
