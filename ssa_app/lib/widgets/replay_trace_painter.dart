// ============================================
// File: widgets/replay_trace_painter.dart
// ============================================
// Reusable CustomPainter that renders a ReplayTrace as a 2D
// barrel-path plot with shot markers. Used by ReplayScreen.
//
// Pre-allocates all Paint objects as static finals so repaint
// cycles (e.g. selection changes) don't reallocate.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/trajectory/replay_models.dart';

class ReplayTracePainter extends CustomPainter {
  final ReplayTrace trace;
  final ReplayShot? selectedShot;
  final Color Function(double) getScoreColor;
  /// Target distance in metres for SCATT ring overlay. Default 10.0.
  final double targetDistanceM;
  /// Index of the frame to highlight (e.g. from the timeline scrubber).
  /// If null, no playhead is drawn. Default null.
  final int? frameIndex;

  ReplayTracePainter({
    required this.trace,
    required this.selectedShot,
    required this.getScoreColor,
    this.targetDistanceM = 10.0,
    this.frameIndex,
  });

  // Pre-allocated paints (singleton-style)
  static final Paint _gridPaint = Paint()
    ..color = const Color(0xFF6B7280)
    ..strokeWidth = 0.5;

  static final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;

  static final Paint _tracePaint = Paint()
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static final Paint _markerStrokePaint = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  static final Paint _markerFillPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static final Paint _hitMarkerPaint = Paint()
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  static final Paint _crosshairPaint = Paint()
    ..color = const Color(0xFF8BCEFF)
    ..strokeWidth = 0.8;

  static final Paint _centerFillPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (trace.frames.isEmpty) {
      _drawEmptyState(canvas, size);
      return;
    }

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Determine bounds from frames
    double maxDev = 0.005;
    for (final f in trace.frames) {
      if (f.barrelX.abs() > maxDev) maxDev = f.barrelX.abs();
      if (f.barrelY.abs() > maxDev) maxDev = f.barrelY.abs();
    }
    maxDev *= 1.3;
    if (maxDev < 0.001) maxDev = 0.01;

    final scaleX = size.width / 2 / maxDev;
    final scaleY = size.height / 2 / maxDev;

    _drawGrid(canvas, size, cx, cy);
    _drawRings(canvas, cx, cy, maxDev * scaleX, maxDev * scaleY);
    _drawTargetOverlay(canvas, size, cx, cy, scaleX, scaleY);

    // Draw trace polyline with recency-based opacity
    final frames = trace.frames;
    final n = frames.length;
    _tracePaint.shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        const Color(0xFFFFB693).withValues(alpha: 0.15),
        const Color(0xFFFFB693).withValues(alpha: 0.95),
      ],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final tracePath = Path();
    tracePath.moveTo(
      cx + frames.first.barrelX * scaleX,
      cy + frames.first.barrelY * scaleY,
    );
    for (int i = 1; i < n; i++) {
      tracePath.lineTo(
        cx + frames[i].barrelX * scaleX,
        cy + frames[i].barrelY * scaleY,
      );
    }
    canvas.drawPath(tracePath, _tracePaint);

    // Draw shot markers
    for (final frame in frames) {
      final marker = frame.shotMarker;
      if (marker == null) continue;

      final x = cx + frame.barrelX * scaleX;
      final y = cy + frame.barrelY * scaleY;
      final isSelected = marker == selectedShot;
      final color = getScoreColor(marker.totalScore);

      // Vertical line through hit point
      _hitMarkerPaint.color = color.withValues(alpha: isSelected ? 0.9 : 0.45);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _hitMarkerPaint);

      // Marker dot
      final dotR = isSelected ? 6.0 : 4.0;
      _markerFillPaint.color = color;
      canvas.drawCircle(Offset(x, y), dotR, _markerFillPaint);
      canvas.drawCircle(Offset(x, y), dotR, _markerStrokePaint);

      // Score number above the marker
      _drawScoreLabel(canvas, x, y - 12, marker.totalScore.toInt(), color);
    }

    // Crosshair
    canvas.drawLine(Offset(cx - 16, cy), Offset(cx + 16, cy), _crosshairPaint);
    canvas.drawLine(Offset(cx, cy - 16), Offset(cx, cy + 16), _crosshairPaint);

    // Center hit dot
    canvas.drawCircle(Offset(cx, cy), 3, _centerFillPaint);
    canvas.drawCircle(Offset(cx, cy), 3, _markerStrokePaint);

    // Playhead cursor from timeline scrubber
    if (frameIndex != null && frameIndex! >= 0 && frameIndex! < n) {
      final cursor = frames[frameIndex!];
      final px = cx + cursor.barrelX * scaleX;
      final py = cy + cursor.barrelY * scaleY;

      final cursorPaint = Paint()
        ..color = const Color(0xFF8BCEFF)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), cursorPaint);

      final dotPaint = Paint()
        ..color = const Color(0xFF8BCEFF)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 4, dotPaint);
      canvas.drawCircle(
        Offset(px, py),
        4,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      _drawScoreLabel(
        canvas,
        px,
        py - 12,
        (cursor.tSeconds * 1000).round(),
        const Color(0xFF8BCEFF),
      );
    }
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'NO TRACE DATA',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          color: Color(0xFF6B7280),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  void _drawGrid(Canvas canvas, Size size, double cx, double cy) {
    _gridPaint.color = const Color(0xFF6B7280).withValues(alpha: 0.3);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), _gridPaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), _gridPaint);
  }

  void _drawRings(Canvas canvas, double cx, double cy,
      double maxRadiusX, double maxRadiusY) {
    _ringPaint.color = const Color(0xFF6B7280).withValues(alpha: 0.15);
    for (final r in [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: r * maxRadiusX * 2,
          height: r * maxRadiusY * 2,
        ),
        _ringPaint,
      );
    }
  }

  void _drawTargetOverlay(Canvas canvas, Size size, double cx, double cy,
      double scaleX, double scaleY) {
    // SCATT target rings: 5° circle at targetDistanceM.
    // Radius on target plane: r = distance * tan(5°)
    const targetAngleDeg = 5.0;
    final rad = targetAngleDeg * math.pi / 180.0;
    final targetRadiusM = targetDistanceM * math.tan(rad);
    final targetRadiusPx = targetRadiusM * scaleX;

    // Draw 5 target rings (0.2, 0.4, 0.6, 0.8, 1.0 of full radius)
    final ringPaint = Paint()
      ..color = const Color(0xFF6B7280).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (final r in [0.2, 0.4, 0.6, 0.8, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: r * targetRadiusPx * 2,
          height: r * targetRadiusPx * 2,
        ),
        ringPaint,
      );
    }

    // Draw shot hit markers on target plane (mm offset).
    final shotMarkers = trace.frames
        .where((f) => f.shotMarker != null)
        .toList(growable: false);
    if (shotMarkers.isEmpty) return;

    for (final frame in shotMarkers) {
      final marker = frame.shotMarker!;
      final px = cx + frame.targetXmm / (targetRadiusM * 1000) * targetRadiusPx;
      final py = cy - frame.targetYmm / (targetRadiusM * 1000) * targetRadiusPx;
      final color = getScoreColor(marker.totalScore);

      // Hit dot
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(Offset(px, py), 4, dotPaint);
      canvas.drawCircle(Offset(px, py), 4, strokePaint);

      // Score label above hit
      _drawScoreLabel(canvas, px, py - 10, marker.totalScore.toInt(), color);
    }
  }

  void _drawScoreLabel(Canvas canvas, double x, double y, int score, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: score.toString(),
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height));
  }

  @override
  bool shouldRepaint(covariant ReplayTracePainter oldDelegate) {
    return oldDelegate.trace != trace ||
        oldDelegate.selectedShot != selectedShot ||
        oldDelegate.frameIndex != frameIndex;
  }
}
