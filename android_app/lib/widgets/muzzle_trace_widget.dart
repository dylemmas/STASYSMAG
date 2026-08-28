// ============================================
// File: widgets/muzzle_trace_widget.dart
// MantisX-Style Real-time Muzzle Trace — Smooth 60fps
// ============================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_data_provider.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';

// Phase colors (MantisX style — STSYS palette)
const Color _holdColor = Color(0xFFFFB693);    // STSYS primary — orange
const Color _pressColor = Color(0xFF8BCEFF);   // STSYS secondary — blue
const Color _recoilColor = Color(0xFFFFB4AB);  // STSYS error — coral

// Scoring ring colors (MantisX zones)
const Color _eliteColor = Color(0xFFFFD700);
const Color _expertColor = Color(0xFF4CAF50);
const Color _advancedColor = Color(0xFF2196F3);
const Color _intermediateColor = Color(0xFFFF9800);
const Color _beginnerColor = Color(0xFFF44336);

class MuzzleTraceWidget extends StatefulWidget {
  final double zoom;
  final bool showGrid;

  const MuzzleTraceWidget({
    super.key,
    this.zoom = 0.05,
    this.showGrid = true,
  });

  @override
  State<MuzzleTraceWidget> createState() => _MuzzleTraceWidgetState();
}

class _MuzzleTraceWidgetState extends State<MuzzleTraceWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // --- 60fps lerp: dot animates toward target ---
  double _dotX = 0.0, _dotY = 0.0;    // current rendered position
  double _targetX = 0.0, _targetY = 0.0; // EMA-smoothed target

  // --- Camera-follow: center lerps toward dot with 500ms delay ---
  double _cameraX = 0.0, _cameraY = 0.0; // current camera center (world offset)
  static const double _cameraLerp = 0.03;  // ~500ms delay (lower=slower=more delay)

  // --- Speed tracking for dot sizing ---
  double _liveSpeed = 0.0;
  double _prevAccelX = 0.0, _prevAccelY = 0.0;
  double _prevTraceX = 0.0, _prevTraceY = 0.0;

  // --- Trace path ---
  final List<_TracePoint> _recentTrace = [];
  static const int _maxTracePoints = 400;
  static const int _traceWindowMs = 2000;

  // --- MantisX-style: dot uses direct accel ---
  static const double _liveDotSensitivity = 0.08;

  // --- Phase coloring ---
  bool _isHold = true;
  bool _isPress = false;
  bool _isRecoil = false;

  // --- Shot display ---
  ShotResult? _lastShot;
  int _shotCount = 0;

  // --- Timer-based phase transitions ---
  Timer? _phaseResetTimer;

  // --- 60fps ticker for smooth animation ---
  late Ticker _ticker;
  double _lastTickTime = 0;

  // --- Auto-zoom: keep movement visible on canvas ---
  static const double _minZoom = 0.015;  // max zoom-in (tight)
  static const double _maxZoom = 0.12;  // max zoom-out (wide view)
  double _currentZoom = 0.05;
  double _autoZoomLerp = 0.02;

  Color get _currentPhaseColor {
    if (_isRecoil) return _recoilColor;
    if (_isPress) return _pressColor;
    return _holdColor;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    _ticker.start();
    _lastTickTime = DateTime.now().millisecondsSinceEpoch.toDouble();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (_ticker.isActive) {
          _ticker.stop();
        }
        break;
      case AppLifecycleState.resumed:
        if (!_ticker.isActive) {
          _lastTickTime = DateTime.now().millisecondsSinceEpoch.toDouble();
          _ticker.start();
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _phaseResetTimer?.cancel();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final deltaMs = (now - _lastTickTime.toInt()).toDouble();
    _lastTickTime = now.toDouble();

    // Lerp dot position toward target
    if (deltaMs > 0) {
      final t = (deltaMs / 16.0).clamp(0.0, 1.0);
      _dotX = _dotX + (_targetX - _dotX) * t;
      _dotY = _dotY + (_targetY - _dotY) * t;

      // Camera-follow: center lerps toward dot position
      _cameraX = _cameraX + (_dotX - _cameraX) * _cameraLerp;
      _cameraY = _cameraY + (_dotY - _cameraY) * _cameraLerp;
    }

    // Auto-zoom: adjust zoom so dot stays visible (~80% of canvas)
    if (_recentTrace.isNotEmpty) {
      double maxExtent = 0.0;
      for (final pt in _recentTrace) {
        final ex = (pt.x - _cameraX).abs();
        final ey = (pt.y - _cameraY).abs();
        if (ex > maxExtent) maxExtent = ex;
        if (ey > maxExtent) maxExtent = ey;
      }
      // Target: dot at edge of canvas at 80% fill
      final targetZoom = (maxExtent > 0.01) ? (maxExtent * 1.25) : _currentZoom;
      _currentZoom = _currentZoom + (targetZoom.clamp(_minZoom, _maxZoom) - _currentZoom) * _autoZoomLerp;
    }

    if (mounted) setState(() {});
  }

  void _processLatestData(SensorDataProvider provider) {
    // Use quaternion-projected trace data from isolate (same as Python stasysz.py)
    // Live dot position from isolate's atan2 projection of barrel vector
    // Trace path from isolate's accumulated trace history
    if (provider.traceXData.isEmpty && provider.accelXData.isEmpty) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // --- LIVE DOT: Quaternion projection from isolate (same as Python) ---
    if (provider.traceXData.isNotEmpty) {
      // Isolate provides live trace position from quaternion projection
      _targetX = provider.liveTraceX;
      _targetY = provider.liveTraceY;

      // Speed from dot position delta
      final ddx = provider.liveTraceX - _prevTraceX;
      final ddy = provider.liveTraceY - _prevTraceY;
      _liveSpeed = _sqrt(ddx * ddx + ddy * ddy);
      _prevTraceX = provider.liveTraceX;
      _prevTraceY = provider.liveTraceY;
    } else {
      // Fallback: demo mode uses direct accelerometer
      final ax = provider.accelXData.last.value;
      final ay = provider.accelYData.last.value;
      _targetX = ax * _liveDotSensitivity;
      _targetY = ay * _liveDotSensitivity;

      final dax = ax - _prevAccelX;
      final day = ay - _prevAccelY;
      _liveSpeed = _sqrt(dax * dax + day * day);
      _prevAccelX = ax;
      _prevAccelY = ay;
    }

    // --- TRACE PATH: Rebuild from isolate's trace history (same as Python) ---
    _recentTrace.clear();
    final traceXs = provider.traceXData;
    final traceYs = provider.traceYData;
    final traceLen = traceXs.length < traceYs.length ? traceXs.length : traceYs.length;

    for (int i = 0; i < traceLen; i++) {
      final phase = _isRecoil
          ? TracePhase.recoil
          : (_isPress ? TracePhase.press : TracePhase.hold);
      // Use relative position from start of window (center = 0)
      final relX = traceXs[i];
      final relY = traceYs[i];
      _recentTrace.add(_TracePoint(relX, relY, nowMs.toDouble(), phase));
    }

    if (_recentTrace.length > _maxTracePoints) {
      _recentTrace.removeRange(0, _recentTrace.length - _maxTracePoints);
    }

    // Phase detection from shot state
    if (_lastShot != null) {
      _isHold = false;
      _isPress = false;
      _isRecoil = true;
      _phaseResetTimer?.cancel();
      _phaseResetTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _isRecoil = false;
            _isHold = true;
          });
        }
      });
    }

    // New shot detected
    if (provider.latestShot != null && provider.latestShot != _lastShot) {
      _lastShot = provider.latestShot;
      _shotCount++;
      _isHold = false;
      _isPress = false;
      _isRecoil = true;
      _phaseResetTimer?.cancel();
      _phaseResetTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isRecoil = false;
            _isHold = true;
            _recentTrace.clear();
            _dotX = 0.0;
            _dotY = 0.0;
            _targetX = 0.0;
            _targetY = 0.0;
          });
        }
      });
    }
  }

  double _sqrt(double v) => v <= 0 ? 0 : _invSqrt(v) * v;

  double _invSqrt(double v) {
    double x = v;
    double y = 1.5 + v * 0.5;
    y = y * (1.5 - x * y * y);
    y = y * (1.5 - x * y * y);
    y = y * (1.5 - x * y * y);
    return y;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, provider, child) {
        _processLatestData(provider);

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  _PhaseDot('H', _holdColor, _isHold),
                  _PhaseDot('P', _pressColor, _isPress),
                  _PhaseDot('R', _recoilColor, _isRecoil),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: StsysTheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_shotCount shots',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: StsysTheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: StsysTheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: StsysTheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _MuzzleTracePainter(
                          trace: _recentTrace,
                          dotX: _dotX,
                          dotY: _dotY,
                          cameraX: _cameraX,
                          cameraY: _cameraY,
                          zoom: _currentZoom,
                          showGrid: widget.showGrid,
                          phaseColor: _currentPhaseColor,
                          liveSpeed: _liveSpeed,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_lastShot != null) _buildScoreRow(_lastShot!),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScoreRow(ShotResult shot) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: StsysTheme.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _scoreChip('HOLD', shot.holdScore, _holdColor),
          Container(width: 1, height: 28, color: StsysTheme.outlineVariant.withValues(alpha: 0.2)),
          _scoreChip('PRESS', shot.pressScore, _pressColor),
          Container(width: 1, height: 28, color: StsysTheme.outlineVariant.withValues(alpha: 0.2)),
          _scoreChip('RECOIL', shot.recoilScore, _recoilColor),
        ],
      ),
    );
  }

  Widget _scoreChip(String label, double score, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 8,
            letterSpacing: 1,
            color: color.withValues(alpha: 0.7),
          ),
        ),
        Text(
          score.toInt().toString(),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ============================================
// PHASE DOT INDICATOR
// ============================================
class _PhaseDot extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;

  const _PhaseDot(this.label, this.color, this.active);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color : color.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 9,
              fontWeight: active ? FontWeight.w800 : FontWeight.w400,
              color: active ? color : StsysTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// TRACE DATA CLASSES
// ============================================
enum TracePhase { hold, press, recoil }

class _TracePoint {
  final double x;
  final double y;
  final double timestamp;
  final TracePhase phase;

  _TracePoint(this.x, this.y, this.timestamp, this.phase);
}

// ============================================
// CUSTOM PAINTER — Pre-allocated Paint/Color/TextPainter
// ============================================
class _MuzzleTracePainter extends CustomPainter {
  final List<_TracePoint> trace;
  final double dotX;
  final double dotY;
  final double cameraX; // camera center offset (world space)
  final double cameraY;
  final double zoom;
  final bool showGrid;
  final Color phaseColor;
  final double liveSpeed;

  _MuzzleTracePainter({
    required this.trace,
    required this.dotX,
    required this.dotY,
    required this.cameraX,
    required this.cameraY,
    required this.zoom,
    required this.showGrid,
    required this.phaseColor,
    required this.liveSpeed,
  });

  // --- PRE-ALLOCATED STATIC PAINT OBJECTS ---
  static final Paint _tracePaint = Paint()
    ..strokeWidth = 2.5
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final Paint _trailDotPaint = Paint()..style = PaintingStyle.fill;

  // Pre-allocated mutable paints
  final Paint _glowPaint1 = Paint()..style = PaintingStyle.fill;
  final Paint _glowPaint2 = Paint()..style = PaintingStyle.fill;
  final Paint _currentDotPaint = Paint()..style = PaintingStyle.fill;

  static final List<(double, Color, Color)> _ringRenders = [
    (0.2, _beginnerColor.withValues(alpha: 0.04), _beginnerColor.withValues(alpha: 0.2)),
    (0.4, _intermediateColor.withValues(alpha: 0.04), _intermediateColor.withValues(alpha: 0.2)),
    (0.6, _advancedColor.withValues(alpha: 0.04), _advancedColor.withValues(alpha: 0.2)),
    (0.8, _expertColor.withValues(alpha: 0.04), _expertColor.withValues(alpha: 0.2)),
    (1.0, _eliteColor.withValues(alpha: 0.04), _eliteColor.withValues(alpha: 0.2)),
  ];

  static final Paint _ringFillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _ringStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;

  static final TextPainter _eliteLabel = TextPainter(
    text: TextSpan(
      text: 'ELITE',
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 7,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: _eliteColor.withValues(alpha: 0.25),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  static final TextPainter _expertLabel = TextPainter(
    text: TextSpan(
      text: 'EXPERT',
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 7,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: _expertColor.withValues(alpha: 0.25),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = size.width / 2 / zoom;

    // Camera offset: camera position in world space
    // Visual center = cx - cameraX * scale, cy - cameraY * scale
    // This makes the dot stay centered as it moves
    final offsetX = cx - cameraX * scale;
    final offsetY = cy - cameraY * scale;

    if (showGrid) {
      _drawScoringRings(canvas, cx, cy, scale, size);
    }

    // --- TRACE PATH (relative to camera) ---
    if (trace.length >= 2) {
      const fadeMin = 0.3;
      final traceLen = trace.length;
      for (int i = 1; i < traceLen; i++) {
        final prev = trace[i - 1];
        final curr = trace[i];
        // Skip invalid points (NaN/Infinity from corrupted sensor data)
        if (prev.x.isNaN || prev.x.isInfinite || curr.x.isNaN || curr.x.isInfinite ||
            prev.y.isNaN || prev.y.isInfinite || curr.y.isNaN || curr.y.isInfinite) {
          continue;
        }
        // Skip extreme jumps that indicate data corruption or tare artifacts
        final dx = (curr.x - prev.x).abs();
        final dy = (curr.y - prev.y).abs();
        if (dx > zoom * 2.0 || dy > zoom * 2.0) {
          continue;
        }
        final ageFraction = i / traceLen;
        final opacity = fadeMin + (1.0 - fadeMin) * ageFraction;
        _tracePaint.color = _getPhaseColor(curr.phase).withValues(alpha: opacity);
        canvas.drawLine(
          Offset(offsetX + prev.x * scale, offsetY + prev.y * scale),
          Offset(offsetX + curr.x * scale, offsetY + curr.y * scale),
          _tracePaint,
        );
      }
    }

    // --- DOT POSITION (follows trace line) ---
    final dotPx = offsetX + dotX * scale;
    final dotPy = offsetY + dotY * scale;

    // --- TRAIL DOTS (motion blur — minimal visual) ---
    for (int t = 3; t >= 1; t--) {
      final trailAlpha = (0.3 - t * 0.08);
      final trailRadius = 4.0 * (1.0 - t * 0.2);
      _trailDotPaint.color = Colors.white.withValues(alpha: trailAlpha.clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(dotPx - t * 2.0, dotPy),
        trailRadius,
        _trailDotPaint,
      );
    }

    // --- WHITE CROSSHAIR at screen center (reference marker) ---
    final crosshairPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 20, cy), Offset(cx + 20, cy), crosshairPaint);
    canvas.drawLine(Offset(cx, cy - 20), Offset(cx, cy + 20), crosshairPaint);
  }

  void _drawScoringRings(Canvas canvas, double cx, double cy, double scale, Size size) {
    for (final ring in _ringRenders) {
      final radius = ring.$1 * scale;
      if (radius > 0 && radius < size.width / 2) {
        _ringFillPaint.color = ring.$2;
        _ringStrokePaint.color = ring.$3;
        canvas.drawCircle(Offset(cx, cy), radius, _ringFillPaint);
        canvas.drawCircle(Offset(cx, cy), radius, _ringStrokePaint);
      }
    }
    _eliteLabel.paint(canvas, Offset(cx + scale * 0.7 * 0.7, cy - scale * 0.7 * 0.7));
    _expertLabel.paint(canvas, Offset(cx + scale * 0.9 * 0.7 * 0.7, cy - scale * 0.9 * 0.7 * 0.7));
  }

  Color _getPhaseColor(TracePhase phase) {
    switch (phase) {
      case TracePhase.hold: return _holdColor;
      case TracePhase.press: return _pressColor;
      case TracePhase.recoil: return _recoilColor;
    }
  }

  double _clamp(double v, double lo, double hi) => v < lo ? lo : v > hi ? hi : v;

  @override
  bool shouldRepaint(covariant _MuzzleTracePainter oldDelegate) {
    if (oldDelegate.dotX != dotX) return true;
    if (oldDelegate.dotY != dotY) return true;
    if (oldDelegate.cameraX != cameraX) return true;
    if (oldDelegate.cameraY != cameraY) return true;
    if (oldDelegate.trace.length != trace.length) return true;
    if (trace.isNotEmpty && oldDelegate.trace.isNotEmpty) {
      final oldLast = oldDelegate.trace.last;
      final newLast = trace.last;
      if (oldLast.x != newLast.x || oldLast.y != newLast.y ||
          oldLast.phase != newLast.phase) return true;
    }
    if (oldDelegate.phaseColor != phaseColor) return true;
    if (oldDelegate.liveSpeed != liveSpeed) return true;
    return false;
  }
}
