// ============================================
// File: widgets/analysis/factor_breakdown_card.dart
// ============================================
// Compact factor-breakdown grid for a single shot: 5 score chips
// (HOLD/PRESS/RECOIL/ELEV/WIND) + 4 meta chips (travel/jerk/firearm/mode).

import 'package:flutter/material.dart';
import '../../services/trajectory/replay_models.dart';
import '../../theme/app_theme.dart';

class FactorBreakdownCard extends StatelessWidget {
  final ReplayShot shot;

  const FactorBreakdownCard({super.key, required this.shot});

  static const Color _holdColor = Color(0xFFFF4444);
  static const Color _pressColor = Color(0xFFFFFF44);
  static const Color _recoilColor = Color(0xFF44FFFF);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              _scoreChip('HOLD', shot.holdScore, _holdColor),
              const SizedBox(width: 4),
              _scoreChip('PRESS', shot.pressScore, _pressColor),
              const SizedBox(width: 4),
              _scoreChip('RECOIL', shot.recoilScore, _recoilColor),
              const SizedBox(width: 4),
              _scoreChip('ELEV', shot.elevationScore, Colors.purple),
              const SizedBox(width: 4),
              _scoreChip('WIND', shot.windageScore, Colors.teal),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _metaChip(Icons.straighten,
                  '${shot.travelDistance.toStringAsFixed(1)}°'),
              const SizedBox(width: 6),
              _metaChip(Icons.bolt,
                  'jerk ${shot.peakJerk.toStringAsFixed(1)}'),
              const SizedBox(width: 6),
              _metaChip(Icons.gps_fixed, shot.firearmType),
              const SizedBox(width: 6),
              _metaChip(Icons.center_focus_strong, shot.trainingMode),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scoreChip(String label, double score, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 7,
                letterSpacing: 1,
                color: color.withValues(alpha: 0.7),
              ),
            ),
            Text(
              score.toInt().toString(),
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: StsysTheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: StsysTheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
