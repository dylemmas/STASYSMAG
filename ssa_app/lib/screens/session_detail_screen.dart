import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/session_logger.dart';
import '../models/data_models.dart';
import '../services/trajectory/replay_engine.dart';
import '../services/trajectory/replay_models.dart';
import '../theme/app_theme.dart';
import '../widgets/analysis_tab.dart';

enum _DetailTab { postShot, analysis }

class SessionDetailScreen extends StatefulWidget {
  final SessionLog session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  ShotResult? _selectedShot;
  int? _selectedShotIndex;
  _DetailTab _tab = _DetailTab.postShot;

  // Built lazily on first switch to ANALYSIS so the post-shot view
  // (the default tab) stays snappy.
  ReplayTrace? _analysisTrace;

  @override
  void initState() {
    super.initState();
    if (widget.session.shots.isNotEmpty) {
      _selectedShot = widget.session.shots.last;
      _selectedShotIndex = widget.session.shots.length - 1;
    }
  }

  void _selectShot(ShotResult shot) {
    final idx = widget.session.shots.indexOf(shot);
    setState(() {
      _selectedShot = shot;
      _selectedShotIndex = idx;
    });
  }

  void _setTab(_DetailTab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      if (tab == _DetailTab.analysis && _analysisTrace == null) {
        _analysisTrace = ReplayEngine().replay(widget.session);
      }
    });
  }

  Widget _buildAnalysisBody() {
    final session = widget.session;
    if (!session.hasRawData) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_flat, size: 48, color: StsysTheme.onSurface.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              'NO IMU DATA AVAILABLE',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: StsysTheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'This session was recorded without raw gyro/accel time-series data. Replay requires raw sensor data captured during the session.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  color: StsysTheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_analysisTrace == null || _analysisTrace!.isEmpty) {
      return Center(
        child: Text(
          'NO SHOTS DETECTED IN IMU DATA',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: StsysTheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      );
    }
    return AnalysisTab(trace: _analysisTrace!);
  }

  Color _getScoreColor(double score) {
    if (score >= 95) return const Color(0xFFFFD700);
    if (score >= 85) return const Color(0xFF4CAF50);
    if (score >= 70) return const Color(0xFF2196F3);
    if (score >= 50) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final avgScore = session.averageScore;

    return Scaffold(
      backgroundColor: StsysTheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: StsysTheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(
                    color: StsysTheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: StsysTheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: StsysTheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEEE, dd MMMM').format(session.date).toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: StsysTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${session.shots.length} shots — ${avgScore.toStringAsFixed(1)} avg',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _getScoreColor(avgScore),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showDeleteDialog(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: StsysTheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: StsysTheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tab toggle: POST SHOT | ANALYSIS
            _buildTabToggle(),

            // ANALYSIS tab: barrel trace + scrubber + per-shot panel.
            if (_tab == _DetailTab.analysis)
              Expanded(child: _buildAnalysisBody())
            else ...[
              // Selected shot 3-phase chart
              if (_selectedShot != null && _selectedShotIndex != null)
              Expanded(
                flex: 3,
                child: _ShotDetailPanel(
                  shot: _selectedShot!,
                  shotIndex: _selectedShotIndex!,
                  getScoreColor: _getScoreColor,
                ),
              )
            else
              Expanded(
                flex: 3,
                child: Center(
                  child: Text(
                    'NO SHOTS IN SESSION',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: StsysTheme.onSurface.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),

            // Shot list
            if (session.shots.isNotEmpty)
              Expanded(
                flex: 2,
                child: Container(
                  color: StsysTheme.surfaceContainerLow,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'SHOTS IN SESSION',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: StsysTheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: StsysTheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${session.shots.length}',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: StsysTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: session.shots.length,
                          itemBuilder: (context, index) {
                            final shot = session.shots[index];
                            final isSelected = shot == _selectedShot;
                            final scoreColor = _getScoreColor(shot.totalScore);

                            return GestureDetector(
                              onTap: () => _selectShot(shot),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 70,
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? scoreColor.withValues(alpha: 0.15)
                                      : StsysTheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? scoreColor
                                        : StsysTheme.outlineVariant.withValues(alpha: 0.2),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '#${index + 1}',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1,
                                        color: StsysTheme.onSurface.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      shot.totalScore.toInt().toString(),
                                      style: TextStyle(
                                        fontFamily: 'Manrope',
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: scoreColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat('HH:mm').format(shot.timestamp),
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 8,
                                        color: StsysTheme.onSurface.withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: StsysTheme.surfaceContainerLow,
      child: Container(
        decoration: BoxDecoration(
          color: StsysTheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            _tabPill(_DetailTab.postShot, 'POST SHOT'),
            _tabPill(_DetailTab.analysis, 'ANALYSIS'),
          ],
        ),
      ),
    );
  }

  Widget _tabPill(_DetailTab tab, String label) {
    final selected = _tab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setTab(tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? StsysTheme.secondary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? StsysTheme.secondary
                  : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: selected
                  ? StsysTheme.secondary
                  : StsysTheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        backgroundColor: StsysTheme.surfaceContainerHigh,
        title: Text(
          'DELETE SESSION?',
          style: StsysText.labelBold.copyWith(color: StsysTheme.error),
        ),
        content: Text(
          'This action cannot be undone.',
          style: StsysText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'BATAL',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                color: StsysTheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(
              'HAPUS',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
                color: StsysTheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Shot Detail Panel (3-Phase Chart)
// ============================================
class _ShotDetailPanel extends StatelessWidget {
  final ShotResult shot;
  final int shotIndex;
  final Color Function(double) getScoreColor;

  const _ShotDetailPanel({
    required this.shot,
    required this.shotIndex,
    required this.getScoreColor,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = getScoreColor(shot.totalScore);

    return Container(
      margin: const EdgeInsets.all(16),
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
                        _formatTime(shot.timestamp),
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
                          _phaseBadge('H', shot.holdScore.toInt(), const Color(0xFFFF4444)),
                          const SizedBox(width: 6),
                          _phaseBadge('P', shot.pressScore.toInt(), const Color(0xFFFFFF44)),
                          const SizedBox(width: 6),
                          _phaseBadge('R', shot.recoilScore.toInt(), const Color(0xFF44FFFF)),
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
                    painter: _ThreePhasePainter(shot: shot),
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

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

// ============================================
// 3-Phase Chart Painter
// ============================================
class _ThreePhasePainter extends CustomPainter {
  final ShotResult shot;

  _ThreePhasePainter({required this.shot});

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

  static final Paint _curvePaint = Paint()
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    double maxDev = 0.005;
    if (shot.holdX != null) { for (final v in shot.holdX!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    if (shot.holdY != null) { for (final v in shot.holdY!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    if (shot.pressX != null) { for (final v in shot.pressX!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    if (shot.pressY != null) { for (final v in shot.pressY!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    if (shot.recoilX != null) { for (final v in shot.recoilX!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    if (shot.recoilY != null) { for (final v in shot.recoilY!) { if (v.abs() > maxDev) maxDev = v.abs(); } }
    maxDev *= 1.3;

    if (maxDev < 0.001) maxDev = 0.01;

    final scaleX = size.width / 2 / maxDev;
    final scaleY = size.height / 2 / maxDev;

    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), _gridPaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), _gridPaint);

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

    _drawCurve(canvas, shot.holdX, shot.holdY, cx, cy, scaleX, scaleY, _holdColor);
    _drawCurve(canvas, shot.pressX, shot.pressY, cx, cy, scaleX, scaleY, _pressColor);
    _drawCurve(canvas, shot.recoilX, shot.recoilY, cx, cy, scaleX, scaleY, _recoilColor);

    canvas.drawCircle(Offset(cx, cy), 3, _hitFill);
    canvas.drawCircle(Offset(cx, cy), 3, _hitStroke);
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
  bool shouldRepaint(covariant _ThreePhasePainter oldDelegate) {
    return oldDelegate.shot != shot;
  }
}
