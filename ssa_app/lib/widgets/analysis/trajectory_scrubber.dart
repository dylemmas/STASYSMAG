// ============================================
// File: widgets/analysis/trajectory_scrubber.dart
// ============================================
// Slider scrubber over a ReplayTrace's frame timeline.
// Emits (frameIndex) so callers can highlight frames on the canvas.

import 'package:flutter/material.dart';
import '../../services/trajectory/replay_models.dart';
import '../../theme/app_theme.dart';

class TrajectoryScrubber extends StatelessWidget {
  final ReplayTrace trace;
  final int frameIndex;
  final ValueChanged<int> onFrameChanged;

  const TrajectoryScrubber({
    super.key,
    required this.trace,
    required this.frameIndex,
    required this.onFrameChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (trace.isEmpty) return const SizedBox.shrink();

    final maxFrame = trace.frames.length - 1;
    final clampedIndex = frameIndex.clamp(0, maxFrame);
    final currentFrame = trace.frames[clampedIndex];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: StsysTheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TIMELINE',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: StsysTheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                't=${currentFrame.tSeconds.toStringAsFixed(2)}s',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: StsysTheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: StsysTheme.secondary,
              inactiveTrackColor:
                  StsysTheme.surfaceContainerHighest,
              thumbColor: StsysTheme.secondary,
              overlayColor:
                  StsysTheme.secondary.withValues(alpha: 0.2),
              trackHeight: 2,
            ),
            child: Slider(
              min: 0,
              max: maxFrame.toDouble(),
              value: clampedIndex.toDouble(),
              onChanged: (v) => onFrameChanged(v.round()),
            ),
          ),
          // Shot markers along the timeline
          SizedBox(
            height: 10,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final shots = trace.frames
                    .where((f) => f.shotMarker != null)
                    .toList(growable: false);
                return Stack(
                  children: [
                    for (final frame in shots)
                      _buildShotTick(
                        frame.tIndex,
                        frame.shotMarker!.totalScore,
                        maxFrame,
                        constraints.maxWidth,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShotTick(int tIndex, double score, int maxFrame, double width) {
    final pct = maxFrame == 0 ? 0.0 : tIndex / maxFrame;
    final dx = pct * width;
    return Positioned(
      left: dx - 3,
      top: 0,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: getScoreColor(score),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black,
            width: 0.5,
          ),
        ),
      ),
    );
  }

  Color getScoreColor(double score) {
    if (score >= 95) return const Color(0xFFFFD700);
    if (score >= 85) return const Color(0xFF4CAF50);
    if (score >= 70) return const Color(0xFF2196F3);
    if (score >= 50) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }
}
