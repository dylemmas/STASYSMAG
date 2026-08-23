import 'package:flutter/material.dart';
import '../models/data_models.dart';

// Phase colors (MantisX style)
const Color holdColor = Color(0xFFFF4444);
const Color pressColor = Color(0xFFFFFF44);
const Color recoilColor = Color(0xFF44FFFF);

// ============================================
// SHOT ANALYSIS PANEL
// ============================================
class ShotAnalysisPanel extends StatelessWidget {
  final ShotResult? shot;
  final int? shotIndex;
  final Color Function(double) getScoreColor;

  const ShotAnalysisPanel({
    super.key,
    required this.shot,
    required this.shotIndex,
    required this.getScoreColor,
  });

  @override
  Widget build(BuildContext context) {
    if (shot == null) {
      return Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'Select a shot below',
            style: TextStyle(color: Colors.grey[400], fontSize: 16),
          ),
        ),
      );
    }

    final scoreColor = getScoreColor(shot!.totalScore);

    return Container(
      margin: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Big score + header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Big score
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scoreColor, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      shot!.totalScore.toInt().toString(),
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Shot info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SHOT #${(shotIndex ?? 0) + 1}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        _formatDateTime(shot!.timestamp),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Phase scores row
                      Row(
                        children: [
                          _phaseBadge('H', shot!.holdScore.toInt(), holdColor),
                          const SizedBox(width: 8),
                          _phaseBadge('P', shot!.pressScore.toInt(), pressColor),
                          const SizedBox(width: 8),
                          _phaseBadge('R', shot!.recoilScore.toInt(), recoilColor),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 3-Phase chart
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: ThreePhaseChartPainter(shot: shot!),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Phase score chips
          Row(
            children: [
              _scoreChip('HOLD', shot!.holdScore, holdColor),
              const SizedBox(width: 6),
              _scoreChip('PRESS', shot!.pressScore, pressColor),
              const SizedBox(width: 6),
              _scoreChip('RECOIL', shot!.recoilScore, recoilColor),
              const SizedBox(width: 6),
              _scoreChip('ELEV', shot!.elevationScore, Colors.purple),
              const SizedBox(width: 6),
              _scoreChip('WIND', shot!.windageScore, Colors.teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _phaseBadge(String label, int score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Text(
            '$score',
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _scoreChip(String label, double score, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
            ),
            Text(
              score.toInt().toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

// ============================================
// 3-PHASE CHART PAINTER
// ============================================
class ThreePhaseChartPainter extends CustomPainter {
  final ShotResult shot;

  ThreePhaseChartPainter({required this.shot});

  // --- PRE-ALLOCATED STATIC PAINT/TextPainter ---
  static final Paint _gridPaint = Paint()
    ..color = Colors.grey[800]!
    ..strokeWidth = 0.5;

  static final Paint _hitFill = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static final Paint _hitStroke = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  static final Paint _ringPaint = Paint()
    ..color = Colors.grey[700]!.withValues(alpha: 0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;

  static final Paint _curvePaint = Paint()
    ..strokeWidth = 2.5
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static final TextPainter _hLabel = TextPainter(
    text: TextSpan(
      text: 'H',
      style: TextStyle(
        color: holdColor,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  static final TextPainter _pLabel = TextPainter(
    text: TextSpan(
      text: 'P',
      style: TextStyle(
        color: pressColor,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  static final TextPainter _rLabel = TextPainter(
    text: TextSpan(
      text: 'R',
      style: TextStyle(
        color: recoilColor,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Calculate max deviation
    double maxDev = 0.005;
    if (shot.holdX != null) { for (final v in shot.holdX!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    if (shot.holdY != null) { for (final v in shot.holdY!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    if (shot.pressX != null) { for (final v in shot.pressX!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    if (shot.pressY != null) { for (final v in shot.pressY!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    if (shot.recoilX != null) { for (final v in shot.recoilX!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    if (shot.recoilY != null) { for (final v in shot.recoilY!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    maxDev *= 1.3;

    final scaleX = size.width / 2 / maxDev;
    final scaleY = size.height / 2 / maxDev;

    // Grid
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), _gridPaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), _gridPaint);

    // Concentric circles
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

    // Curves
    _drawCurve(canvas, shot.holdX, shot.holdY, cx, cy, scaleX, scaleY, holdColor);
    _drawCurve(canvas, shot.pressX, shot.pressY, cx, cy, scaleX, scaleY, pressColor);
    _drawCurve(canvas, shot.recoilX, shot.recoilY, cx, cy, scaleX, scaleY, recoilColor);

    // Hit marker
    canvas.drawCircle(Offset(cx, cy), 4, _hitFill);
    canvas.drawCircle(Offset(cx, cy), 4, _hitStroke);

    // Labels
    _hLabel.paint(canvas, Offset(cx + size.width * 0.42, cy + 12));
    _pLabel.paint(canvas, Offset(cx + size.width * 0.42, cy + 28));
    _rLabel.paint(canvas, Offset(cx + size.width * 0.42, cy + 44));
  }

  void _drawCurve(Canvas canvas, List<double>? xList, List<double>? yList,
      double cx, double cy, double sx, double sy, Color color) {
    if (xList == null || yList == null || xList.length < 2) return;

    final path = Path()..moveTo(cx + xList[0] * sx, cy + yList[0] * sy);
    for (int i = 1; i < xList.length; i++) {
      path.lineTo(cx + xList[i] * sx, cy + yList[i] * sy);
    }

    _curvePaint.color = color.withValues(alpha: 0.8);
    canvas.drawPath(path, _curvePaint);
  }

  @override
  bool shouldRepaint(covariant ThreePhaseChartPainter oldDelegate) {
    return oldDelegate.shot != shot;
  }
}
