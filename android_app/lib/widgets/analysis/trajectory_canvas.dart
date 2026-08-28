// ============================================
// File: widgets/analysis/trajectory_canvas.dart
// ============================================
// Wraps ReplayTracePainter with header + legend chrome.
// Tapping the canvas selects the nearest shot marker in screen space.

import 'package:flutter/material.dart';
import '../../providers/settings_provider.dart';
import '../../services/trajectory/replay_models.dart';
import '../../theme/app_theme.dart';
import '../replay_trace_painter.dart';
import 'package:provider/provider.dart';

class TrajectoryCanvas extends StatelessWidget {
  final ReplayTrace trace;
  final ReplayShot? selectedShot;
  final Color Function(double) getScoreColor;
  final ValueChanged<ReplayShot> onShotTapped;
  final int? frameIndex;

  const TrajectoryCanvas({
    super.key,
    required this.trace,
    required this.selectedShot,
    required this.getScoreColor,
    required this.onShotTapped,
    this.frameIndex,
  });

  @override
  Widget build(BuildContext context) {
    final targetDistanceM = context.watch<SettingsProvider>().targetDistanceM;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Text(
                  'BARREL TRACE',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: StsysTheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                _legendChip('PATH', const Color(0xFFFFB693)),
                const SizedBox(width: 6),
                _legendChip('HIT', const Color(0xFF4CAF50)),
                const SizedBox(width: 12),
                Text(
                  '${targetDistanceM.toStringAsFixed(0)}m',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: StsysTheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: StsysTheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: RepaintBoundary(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _handleTap(
                          details.localPosition,
                          constraints.biggest,
                        ),
                        child: CustomPaint(
                          painter: ReplayTracePainter(
                            trace: trace,
                            selectedShot: selectedShot,
                            getScoreColor: getScoreColor,
                            targetDistanceM: targetDistanceM,
                            frameIndex: frameIndex,
                          ),
                          size: Size.infinite,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(Offset local, Size size) {
    final shots = trace.frames
        .where((f) => f.shotMarker != null)
        .toList(growable: false);
    if (shots.isEmpty) return;

    // Reproduce the painter's screen-space mapping to find the nearest marker.
    double maxAbsX = 0.005, maxAbsY = 0.005;
    for (final f in trace.frames) {
      if (f.barrelX.abs() > maxAbsX) maxAbsX = f.barrelX.abs();
      if (f.barrelY.abs() > maxAbsY) maxAbsY = f.barrelY.abs();
    }
    maxAbsX *= 1.3;
    maxAbsY *= 1.3;
    if (maxAbsX < 0.001) maxAbsX = 0.01;
    if (maxAbsY < 0.001) maxAbsY = 0.01;

    final scaleX = (size.width / 2 - 8) / maxAbsX;
    final scaleY = (size.height / 2 - 8) / maxAbsY;
    final cx = size.width / 2;
    final cy = size.height / 2;

    ReplayShot? nearest;
    double bestDist = double.infinity;
    for (final f in shots) {
      final px = cx + f.barrelX * scaleX;
      final py = cy + f.barrelY * scaleY;
      final d = (local - Offset(px, py)).distance;
      if (d < bestDist) {
        bestDist = d;
        nearest = f.shotMarker;
      }
    }
    if (nearest != null && bestDist < 40) {
      onShotTapped(nearest);
    }
  }

  Widget _legendChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: StsysTheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
