import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssa_app/providers/bluetooth_provider.dart';
import 'package:ssa_app/providers/sensor_data_provider.dart';
import 'package:ssa_app/widgets/muzzle_trace_widget.dart';
import 'package:ssa_app/widgets/shot_history_list.dart';
import '../../models/data_models.dart';
import '../../theme/app_theme.dart';

class GraphTab extends StatefulWidget {
  const GraphTab({super.key});

  @override
  State<GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends State<GraphTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _lastShotCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getScoreColor(double score) {
    if (score >= 95) return const Color(0xFFFFD700);
    if (score >= 85) return const Color(0xFF4CAF50);
    if (score >= 70) return const Color(0xFF2196F3);
    if (score >= 50) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Control Bar
        _buildControlBar(),

        // Tab Bar
        Container(
          color: StsysTheme.surfaceContainerLow,
          child: TabBar(
            controller: _tabController,
            indicatorColor: StsysTheme.primary,
            indicatorWeight: 3,
            labelColor: StsysTheme.primary,
            unselectedLabelColor: StsysTheme.onSurface.withValues(alpha: 0.5),
            dividerColor: StsysTheme.outlineVariant.withValues(alpha: 0.3),
            labelStyle: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            tabs: const [
              Tab(text: 'TRACE'),
              Tab(text: 'POST SHOT'),
            ],
          ),
        ),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // TRACE TAB
              Container(
                color: StsysTheme.surfaceContainerLowest,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Live badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: StsysTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: StsysTheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: StsysTheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'LIVE STREAM',
                                style: TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: StsysTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Consumer<SensorDataProvider>(
                          builder: (context, sensor, child) {
                            return Text(
                              'FOV: ${sensor.gyroXData.length} samples',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                color: StsysTheme.onSurface.withValues(alpha: 0.3),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Muzzle trace widget
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: StsysTheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: StsysTheme.outlineVariant.withValues(alpha: 0.15),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: MuzzleTraceWidget(zoom: 0.05, showGrid: false),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // POST SHOT TAB
              _PostShotTab(
                getScoreColor: _getScoreColor,
                formatTime: _formatTime,
                onShotCountChanged: (count) => _lastShotCount = count,
                lastShotCount: _lastShotCount,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlBar() {
    return Consumer<SensorDataProvider>(
      builder: (context, sensorData, child) {
        return Consumer<BluetoothProvider>(
          builder: (context, btProvider, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: StsysTheme.surfaceContainerLowest,
              child: Row(
                children: [
                  Expanded(
                    child: _ControlButton(
                      icon: sensorData.isRecording
                          ? Icons.stop
                          : Icons.fiber_manual_record,
                      label: sensorData.isRecording ? 'STOP' : 'RECORD',
                      color: sensorData.isRecording
                          ? StsysTheme.error
                          : StsysTheme.primary,
                      enabled: btProvider.isConnected &&
                          btProvider.isAuthenticated,
                      onTap: () => sensorData.toggleRecording(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ControlButton(
                      icon: Icons.tune,
                      label: 'CALIBRATE',
                      color: StsysTheme.secondary,
                      enabled: btProvider.isConnected &&
                          btProvider.isAuthenticated &&
                          !sensorData.isCalibrating,
                      isLoading: sensorData.isCalibrating,
                      onTap: () {
                        if (!btProvider.isAuthenticated) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Connect and authenticate first'),
                            ),
                          );
                          return;
                        }
                        sensorData.startCalibration();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ControlButton(
                      icon: Icons.save_outlined,
                      label: 'SAVE',
                      color: const Color(0xFF4CAF50),
                      enabled: sensorData.canSaveSession &&
                          (!btProvider.isConnected || btProvider.isAuthenticated || sensorData.isDemoMode),
                      onTap: () async {
                        final scaffold = ScaffoldMessenger.of(context);
                        try {
                          await sensorData.saveCurrentSession();
                          if (context.mounted) {
                            scaffold.showSnackBar(
                              const SnackBar(
                                content: Text('Session saved'),
                              ),
                            );
                          }
                        } catch (e, stack) {
                          debugPrint('[SAVE] Error type: ${e.runtimeType}');
                          debugPrint('[SAVE] Error: $e');
                          debugPrint('[SAVE] Stack: $stack');
                          if (context.mounted) {
                            scaffold.showSnackBar(
                              SnackBar(
                                content: Text('Failed: ${e.runtimeType}: $e'),
                                duration: const Duration(seconds: 8),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================
// POST SHOT TAB
// ============================================
class _PostShotTab extends StatefulWidget {
  final Color Function(double) getScoreColor;
  final String Function(DateTime) formatTime;
  final void Function(int) onShotCountChanged;
  final int lastShotCount;

  const _PostShotTab({
    required this.getScoreColor,
    required this.formatTime,
    required this.onShotCountChanged,
    required this.lastShotCount,
  });

  @override
  State<_PostShotTab> createState() => _PostShotTabState();
}

class _PostShotTabState extends State<_PostShotTab> {
  ShotResult? _selectedShot;
  int? _selectedShotIndex;
  bool _needsShotUpdate = false;
  bool _hasUserSelected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleShotUpdate();
  }

  void _scheduleShotUpdate() {
    if (_needsShotUpdate || !mounted) return;
    _needsShotUpdate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _needsShotUpdate = false;
      _doShotUpdate();
    });
  }

  void _doShotUpdate() {
    if (!mounted) return;
    final sensor = context.read<SensorDataProvider>();
    final shots = sensor.sessionShots;

    widget.onShotCountChanged(shots.length);

    // Only auto-select latest if user hasn't manually selected a shot
    if (_hasUserSelected) return;

    if (shots.isNotEmpty && shots.length > widget.lastShotCount) {
      _updateSelection(shots.last);
    } else if (shots.isNotEmpty &&
        (_selectedShot == null || !shots.contains(_selectedShot))) {
      _updateSelection(shots.last);
    } else if (shots.isEmpty && _selectedShot != null) {
      setState(() {
        _selectedShot = null;
        _selectedShotIndex = null;
      });
    }
  }

  void _updateSelection(ShotResult? shot) {
    final sensor = context.read<SensorDataProvider>();
    final shots = sensor.sessionShots;

    if (shot != null && shots.contains(shot)) {
      setState(() {
        _selectedShot = shot;
        _selectedShotIndex = shots.indexOf(shot);
      });
    } else if (shots.isNotEmpty) {
      setState(() {
        _selectedShot = shots.last;
        _selectedShotIndex = shots.length - 1;
      });
    } else {
      setState(() {
        _selectedShot = null;
        _selectedShotIndex = null;
      });
    }
  }

  void _onUserTapShot(ShotResult shot) {
    setState(() {
      _hasUserSelected = true;
    });
    _updateSelection(shot);
  }

  void _resetToLive() {
    final sensor = context.read<SensorDataProvider>();
    final shots = sensor.sessionShots;
    setState(() {
      _hasUserSelected = false;
      _selectedShot = shots.isNotEmpty ? shots.last : null;
      _selectedShotIndex = shots.isNotEmpty ? shots.length - 1 : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorDataProvider>(
      builder: (context, sensor, child) {
        final shots = sensor.sessionShots;
        if (shots.isEmpty) {
          return Container(
            color: StsysTheme.surfaceContainerLowest,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.ads_click_outlined,
                    size: 48,
                    color: StsysTheme.onSurface.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'NO SHOTS RECORDED',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: StsysTheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            // 3-phase chart (latest shot)
            Expanded(
              flex: 3,
              child: _selectedShot == null
                  ? const SizedBox.shrink()
                  : _LatestShotPanel(
                      shot: _selectedShot!,
                      shotIndex: _selectedShotIndex ?? 0,
                      getScoreColor: widget.getScoreColor,
                    ),
            ),
            const SizedBox(height: 8),
            // Shot history list
            Expanded(
              flex: 2,
              child: Container(
                color: StsysTheme.surfaceContainerLowest,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Back to Live button
                    if (_hasUserSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: _resetToLive,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: StsysTheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: StsysTheme.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.live_tv,
                                  size: 12,
                                  color: StsysTheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'BACK TO LIVE',
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                    color: StsysTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ShotHistoryList(
                        shots: shots,
                        selectedShot: _selectedShot,
                        onShotSelected: _onUserTapShot,
                        getScoreColor: widget.getScoreColor,
                        formatTime: widget.formatTime,
                        formatScore: (s) => s.toInt().toString(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================
// LATEST SHOT PANEL
// ============================================
class _LatestShotPanel extends StatelessWidget {
  final ShotResult shot;
  final int shotIndex;
  final Color Function(double) getScoreColor;

  const _LatestShotPanel({
    required this.shot,
    required this.shotIndex,
    required this.getScoreColor,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = getScoreColor(shot.totalScore);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Score + header
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Big score
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scoreColor, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      shot.totalScore.toInt().toString(),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: scoreColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info
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
                          color: StsysTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDateTime(shot.timestamp),
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
                          _phaseBadge(
                            'H',
                            shot.holdScore.toInt(),
                            const Color(0xFFFF4444),
                          ),
                          const SizedBox(width: 6),
                          _phaseBadge(
                            'P',
                            shot.pressScore.toInt(),
                            const Color(0xFFFFFF44),
                          ),
                          const SizedBox(width: 6),
                          _phaseBadge(
                            'R',
                            shot.recoilScore.toInt(),
                            const Color(0xFF44FFFF),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3-Phase chart
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
                    painter: _ThreePhaseChartPainter(shot: shot),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),

          // Phase chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                _scoreChip('HOLD', shot.holdScore, const Color(0xFFFF4444)),
                const SizedBox(width: 4),
                _scoreChip('PRESS', shot.pressScore, const Color(0xFFFFFF44)),
                const SizedBox(width: 4),
                _scoreChip('RECOIL', shot.recoilScore, const Color(0xFF44FFFF)),
                const SizedBox(width: 4),
                _scoreChip('ELEV', shot.elevationScore, Colors.purple),
                const SizedBox(width: 4),
                _scoreChip('WIND', shot.windageScore, Colors.teal),
              ],
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
                fontWeight: FontWeight.w900,
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
class _ThreePhaseChartPainter extends CustomPainter {
  final ShotResult shot;

  _ThreePhaseChartPainter({required this.shot});

  // --- PRE-ALLOCATED STATIC PAINT/TextPainter ---
  static const Color _holdColor = Color(0xFFFF4444);
  static const Color _pressColor = Color(0xFFFFFF44);
  static const Color _recoilColor = Color(0xFF44FFFF);

  static final Paint _gridPaint = Paint()
    ..color = StsysTheme.outlineVariant.withValues(alpha: 0.3)
    ..strokeWidth = 0.5;

  static final Paint _hitFill = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static final Paint _hitStroke = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  // Pre-allocated curve Paint (mutate color each draw)
  static final Paint _curvePaint = Paint()
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  // Pre-allocated ring Paint (mutate color each draw)
  static final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;

  // Pre-built label TextPainters
  static final TextPainter _hLabel = TextPainter(
    text: const TextSpan(
      text: 'H',
      style: TextStyle(
        fontFamily: 'Manrope',
        color: _holdColor,
        fontSize: 9,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  static final TextPainter _pLabel = TextPainter(
    text: const TextSpan(
      text: 'P',
      style: TextStyle(
        fontFamily: 'Manrope',
        color: _pressColor,
        fontSize: 9,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  static final TextPainter _rLabel = TextPainter(
    text: const TextSpan(
      text: 'R',
      style: TextStyle(
        fontFamily: 'Manrope',
        color: _recoilColor,
        fontSize: 9,
        fontWeight: FontWeight.w800,
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

    // Rings
    _ringPaint.color = StsysTheme.outlineVariant.withValues(alpha: 0.15);
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
    _drawCurve(canvas, shot.holdX, shot.holdY, cx, cy, scaleX, scaleY, _holdColor);
    _drawCurve(canvas, shot.pressX, shot.pressY, cx, cy, scaleX, scaleY, _pressColor);
    _drawCurve(canvas, shot.recoilX, shot.recoilY, cx, cy, scaleX, scaleY, _recoilColor);

    // Hit marker
    canvas.drawCircle(Offset(cx, cy), 3, _hitFill);
    canvas.drawCircle(Offset(cx, cy), 3, _hitStroke);

    // Labels — reuse static TextPainters
    _hLabel.paint(canvas, Offset(cx + size.width * 0.42, cy + 8));
    _pLabel.paint(canvas, Offset(cx + size.width * 0.42, cy + 22));
    _rLabel.paint(canvas, Offset(cx + size.width * 0.42, cy + 36));
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
  bool shouldRepaint(covariant _ThreePhaseChartPainter oldDelegate) {
    return oldDelegate.shot != shot;
  }
}

// ============================================
// CONTROL BUTTON
// ============================================
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final bool isLoading;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    this.enabled = true,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: enabled
              ? LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.8),
                    color,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : null,
          color: enabled ? null : StsysTheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: StsysTheme.onPrimary,
                ),
              )
            else
              Icon(
                icon,
                size: 16,
                color: enabled
                    ? StsysTheme.onPrimary
                    : StsysTheme.onSurface.withValues(alpha: 0.3),
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: enabled
                    ? StsysTheme.onPrimary
                    : StsysTheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
