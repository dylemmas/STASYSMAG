// ============================================
// File: widgets/gyro_realtime_chart.dart
// Custom painter — fading tail, no Syncfusion overhead
// ============================================
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_data_provider.dart';
import '../models/data_models.dart';

class GyroRealtimeChart extends StatefulWidget {
  const GyroRealtimeChart({super.key});

  @override
  State<GyroRealtimeChart> createState() => _GyroRealtimeChartState();
}

class _GyroRealtimeChartState extends State<GyroRealtimeChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Offset? _lastTap;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _controller.repeat(); // progress bar animation
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, provider, _) {
        final xData = provider.gyroXData;
        final yData = provider.gyroYData;
        final zData = provider.gyroZData;
        final score = provider.stabilityScore;

        return Card(
          color: const Color(0xFF1A1A2E),
          elevation: 0,
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Realtime Gyro',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Row(
                      children: [
                        _dot(Color(0xFF2196F3), 'X'),
                        const SizedBox(width: 8),
                        _dot(Color(0xFFE53935), 'Y'),
                        const SizedBox(width: 8),
                        _dot(Color(0xFF4CAF50), 'Z'),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: score > 80 ? const Color(0xFF4CAF50)
                                : score > 50 ? const Color(0xFFFF9800)
                                : const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${score.toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Chart
                Expanded(
                  child: xData.isEmpty
                      ? _placeholder()
                      : RepaintBoundary(
                          child: GestureDetector(
                            onPanDown: (d) => _lastTap = d.localPosition,
                            onPanEnd: (d) => _lastTap = null,
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _GyroChartPainter(
                                xData: xData,
                                yData: yData,
                                zData: zData,
                                lastTap: _lastTap,
                              ),
                            ),
                          ),
                        ),
                ),
                // Progress bar (5s window)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return SizedBox(
                        height: 2,
                        child: LinearProgressIndicator(
                          value: _controller.value,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF2196F3),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
          )),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      );

  Widget _placeholder() => Container(
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart, size: 40, color: Colors.grey[700]),
              const SizedBox(height: 8),
              Text('Waiting for data...', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
        ),
      );
}

class _GyroChartPainter extends CustomPainter {
  final List<DataPoint> xData;
  final List<DataPoint> yData;
  final List<DataPoint> zData;
  final Offset? lastTap;

  static const Color _colorX = Color(0xFF2196F3);
  static const Color _colorY = Color(0xFFE53935);
  static const Color _colorZ = Color(0xFF4CAF50);

  _GyroChartPainter({
    required this.xData,
    required this.yData,
    required this.zData,
    this.lastTap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (xData.isEmpty) return;

    final w = size.width;
    final h = size.height;
    if (w == 0 || h == 0) return;

    // Fixed scale — prevents coordinate jumps when data spikes
    const minVal = -5.0;
    const maxVal = 5.0;
    const fixedYRange = maxVal - minVal; // 10.0

    // Find time range
    double minTs = double.infinity;
    double maxTs = -double.infinity;

    for (final p in xData) {
      if (p.x < minTs) minTs = p.x;
      if (p.x > maxTs) maxTs = p.x;
    }
    for (final p in yData) {
      if (p.x < minTs) minTs = p.x;
      if (p.x > maxTs) maxTs = p.x;
    }
    for (final p in zData) {
      if (p.x < minTs) minTs = p.x;
      if (p.x > maxTs) maxTs = p.x;
    }

    final timeRange = (maxTs - minTs).clamp(0.01, double.infinity);

    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Horizontal grid (zero line + ±2.5)
    for (final val in [-2.5, 0.0, 2.5]) {
      final y = _mapY(val, minVal, maxVal, h);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Vertical grid (time markers)
    final numVGrid = 5;
    for (int i = 0; i <= numVGrid; i++) {
      final x = (i / numVGrid) * w;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }

    // Draw lines with fading tail
    void drawLine(List<DataPoint> points, Color color) {
      if (points.length < 2) return;

      final segCount = points.length - 1;

      for (int i = 0; i < segCount; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];

        final x0 = (p0.x - minTs) / timeRange * w;
        final x1 = (p1.x - minTs) / timeRange * w;
        final y0 = _mapY(p0.y, minVal, maxVal, h);
        final y1 = _mapY(p1.y, minVal, maxVal, h);

        // Fade: old points transparent, new points opaque
        final progress = i / segCount; // 0 = oldest, 1 = newest
        final alpha = (progress * progress).clamp(0.0, 1.0); // ease-in curve

        final paint = Paint()
          ..color = color.withValues(alpha: alpha * 0.9)
          ..strokeWidth = 1.5 + progress * 1.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(Offset(x0, y0), Offset(x1, y1), paint);
      }
    }

    drawLine(zData, _colorZ);
    drawLine(yData, _colorY);
    drawLine(xData, _colorX);

    // Draw current value dots
    void drawDot(List<DataPoint> points, Color color) {
      if (points.isEmpty) return;
      final last = points.last;
      final x = w; // right edge
      final y = _mapY(last.y, minVal, maxVal, h);

      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);

      // Glow
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(x, y), 6, glowPaint);
    }

    drawDot(xData, _colorX);
    drawDot(yData, _colorY);
    drawDot(zData, _colorZ);

    // Y-axis labels
    final labelStyle = const TextStyle(color: Colors.white54, fontSize: 9);
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final val in [-2.5, 0.0, 2.5]) {
      textPainter.text = TextSpan(text: val.toStringAsFixed(1), style: labelStyle);
      textPainter.layout();
      textPainter.paint(canvas, const Offset(2, 0));
    }
  }

  double _mapY(double value, double min, double max, double height) {
    return height - ((value - min) / (max - min)) * height;
  }

  @override
  bool shouldRepaint(covariant _GyroChartPainter old) {
    return old.xData != xData || old.yData != yData || old.zData != zData || old.lastTap != lastTap;
  }
}
