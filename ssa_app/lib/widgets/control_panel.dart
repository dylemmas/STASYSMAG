import 'package:flutter/material.dart';

class ControlPanel extends StatelessWidget {
  final bool isRecording;
  final bool isCalibrating;
  final VoidCallback onRecord;
  final VoidCallback onCalibrate;
  final VoidCallback onSave;

  const ControlPanel({
    super.key,
    required this.isRecording,
    required this.isCalibrating,
    required this.onRecord,
    required this.onCalibrate,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Tombol Record
          ElevatedButton.icon(
            onPressed: onRecord,
            icon: Icon(isRecording ? Icons.stop : Icons.fiber_manual_record),
            label: Text(isRecording ? 'Stop' : 'Record'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecording ? Colors.red : Colors.grey[300],
              foregroundColor: isRecording ? Colors.white : Colors.black,
            ),
          ),

          // Tombol Kalibrasi
          ElevatedButton.icon(
            onPressed: isCalibrating ? null : onCalibrate,
            icon: isCalibrating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.settings),
            label: Text(isCalibrating ? 'Calibrating...' : 'Calibrate'),
          ),

          // Tombol Simpan
          ElevatedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
