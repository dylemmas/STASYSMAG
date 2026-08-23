// ============================================
// File: widgets/analysis/phase_summary_card.dart
// ============================================
// 3-phase score summary card (HOLD / PRESS / RECOIL) with score badge,
// phase badges, and a tiny inline 3-phase painter. Mirrors the
// per-shot breakdown used in ReplayScreen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/trajectory/replay_models.dart';
import '../../theme/app_theme.dart';

class PhaseSummaryCard extends StatelessWidget {
  final ReplayShot shot;
  final int shotIndex;
  final Color Function(double) getScoreColor;

  const PhaseSummaryCard({
    super.key,
    required this.shot,
    required this.shotIndex,
    required this.getScoreColor,
  });

  static const Color _holdColor = Color(0xFFFF4444);
  static const Color _pressColor = Color(0xFFFFFF44);
  static const Color _recoilColor = Color(0xFF44FFFF);

  @override
  Widget build(BuildContext context) {
    final color = getScoreColor(shot.totalScore);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      shot.totalScore.toInt().toString(),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SHOT #${shotIndex + 1}'.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: StsysTheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('HH:mm:ss').format(shot.timestamp),
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: StsysTheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _phaseBadge('H', shot.holdScore.toInt(), _holdColor),
                          const SizedBox(width: 6),
                          _phaseBadge('P', shot.pressScore.toInt(), _pressColor),
                          const SizedBox(width: 6),
                          _phaseBadge('R', shot.recoilScore.toInt(), _recoilColor),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: StsysTheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: ThreePhasePainter(shot: shot),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseBadge(String label, int score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label:$score',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

/// Tiny inline painter: draws HOLD/PRESS/RECOIL barrel curves on a
/// single canvas, sharing the same scale. Exported so it can be reused
/// outside the card (e.g. tests, future debug overlays).
class ThreePhasePainter extends CustomPainter {
  final ReplayShot shot;

  ThreePhasePainter({required this.shot});

  static const Color _holdColor = Color(0xFFFF4444);
  static const Color _pressColor = Color(0xFFFFFF44);
  static const Color _recoilColor = Color(0xFF44FFFF);

  static final Paint _gridPaint = Paint()
    ..color = const Color(0xFF6B7280).withValues(alpha: 0.3)
    ..strokeWidth = 0.5;

  static final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;

  static final Paint _hitFill = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static final Paint _hitStroke = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  static final Paint _curvePaint = Paint()
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    double maxDev = 0.005;
    for (final v in shot.holdX) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    for (final v in shot.holdY) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    for (final v in shot.pressX) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    for (final v in shot.pressY) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    for (final v in shot.recoilX) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    for (final v in shot.recoilY) {
      if (v.abs() > maxDev) maxDev = v.abs();
    }
    maxDev *= 1.3;
    if (maxDev < 0.001) maxDev = 0.01;

    final scaleX = size.width / 2 / maxDev;
    final scaleY = size.height / 2 / maxDev;

    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), _gridPaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), _gridPaint);

    _ringPaint.color = const Color(0xFF6B7280).withValues(alpha: 0.15);
    for (final r in [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: r * maxDev * scaleX * 2,
          height: r * maxDev * scaleY * 2,
        ),
        _ringPaint,
      );
    }

    _drawCurve(canvas, shot.holdX, shot.holdY, cx, cy, scaleX, scaleY, _holdColor);
    _drawCurve(canvas, shot.pressX, shot.pressY, cx, cy, scaleX, scaleY, _pressColor);
    _drawCurve(canvas, shot.recoilX, shot.recoilY, cx, cy, scaleX, scaleY, _recoilColor);

    canvas.drawCircle(Offset(cx, cy), 3, _hitFill);
    canvas.drawCircle(Offset(cx, cy), 3, _hitStroke);
  }

  void _drawCurve(Canvas canvas, List<double> xList, List<double> yList,
      double cx, double cy, double sx, double sy, Color color) {
    if (xList.length < 2) return;

    final path = Path()..moveTo(cx + xList[0] * sx, cy + yList[0] * sy);
    for (int i = 1; i < xList.length; i++) {
      path.lineTo(cx + xList[i] * sx, cy + yList[i] * sy);
    }
    _curvePaint.color = color;
    canvas.drawPath(path, _curvePaint);
  }

  @override
  bool shouldRepaint(covariant ThreePhasePainter oldDelegate) {
    return oldDelegate.shot != shot;
  }
}
