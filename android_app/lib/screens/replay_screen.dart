// ============================================
// File: screens/replay_screen.dart
// ============================================
// Offline replay screen: loads a SessionLog by id, runs it through
// ReplayEngine, and shows the reconstructed barrel trace + per-shot
// 3-phase breakdown.

import 'package:flutter/material.dart';
import '../providers/session_logger.dart';
import '../services/database_service.dart';
import '../services/trajectory/replay_engine.dart';
import '../services/trajectory/replay_models.dart';
import '../theme/app_theme.dart';
import '../widgets/analysis/trajectory_canvas.dart';
import '../widgets/analysis/trajectory_scrubber.dart';
import '../widgets/analysis/phase_summary_card.dart';
import '../widgets/analysis/factor_breakdown_card.dart';

class ReplayScreen extends StatefulWidget {
  final String sessionId;

  const ReplayScreen({super.key, required this.sessionId});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  late Future<_ReplayResult?> _future;
  ReplayShot? _selectedShot;
  int _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReplayResult?> _load() async {
    final session = await DatabaseService().getSession(widget.sessionId);
    if (session == null) return null;
    final trace = ReplayEngine().replay(session);
    if (trace.hasShots) {
      _selectedShot = trace.shots.first;
      _frameIndex = trace.shots.first.breakIndex.clamp(
        0,
        trace.frames.length - 1,
      );
    } else if (trace.frames.isNotEmpty) {
      _frameIndex = trace.frames.length - 1;
    }
    return _ReplayResult(session: session, trace: trace);
  }

  Color _scoreColor(double score) {
    if (score >= 95) return const Color(0xFFFFD700);
    if (score >= 85) return const Color(0xFF4CAF50);
    if (score >= 70) return const Color(0xFF2196F3);
    if (score >= 50) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  void _selectShot(ReplayShot shot) {
    setState(() {
      _selectedShot = shot;
      _frameIndex = shot.breakIndex.clamp(0, _frameIndex);
    });
  }

  void _onFrameChanged(int idx) {
    setState(() => _frameIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StsysTheme.surfaceContainerLowest,
      body: SafeArea(
        child: FutureBuilder<_ReplayResult?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final result = snapshot.data;
            if (result == null) {
              return _ErrorView(onBack: () => Navigator.pop(context));
            }
            return _buildBody(result);
          },
        ),
      ),
    );
  }

  Widget _buildBody(_ReplayResult result) {
    final session = result.session;
    final trace = result.trace;
    final avgScore = trace.shots.isEmpty
        ? 0.0
        : trace.shots.map((s) => s.totalScore).reduce((a, b) => a + b) /
            trace.shots.length;

    // If no raw IMU data was ever recorded, show a clear message.
    if (!session.hasRawData) {
      return _buildNoRawDataView();
    }

    return Column(
      children: [
        _buildHeader(session, trace, avgScore),
        if (trace.hasShots)
          Expanded(
            flex: 2,
            child: _buildTraceView(trace),
          )
        else
          Expanded(
            flex: 2,
            child: _buildEmptyTrace(),
          ),
        if (trace.hasShots && !trace.isEmpty)
          TrajectoryScrubber(
            trace: trace,
            frameIndex: _frameIndex,
            onFrameChanged: _onFrameChanged,
          ),
        if (_selectedShot != null)
          Expanded(
            flex: 3,
            child: _ReplayShotPanel(
              shot: _selectedShot!,
              shotIndex: trace.shots.indexOf(_selectedShot!),
              getScoreColor: _scoreColor,
            ),
          )
        else
          Expanded(
            flex: 3,
            child: _buildEmptyPanel(),
          ),
        if (trace.hasShots)
          Expanded(
            flex: 1,
            child: _buildShotChips(trace),
          ),
      ],
    );
  }

  Widget _buildNoRawDataView() {
    return Column(
      children: [
        // header bar stays
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: StsysTheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: StsysTheme.outlineVariant.withValues(alpha: 0.2))),
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
                  child: Icon(Icons.arrow_back, size: 20, color: StsysTheme.onSurface.withValues(alpha: 0.7)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'OFFLINE REPLAY',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: StsysTheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        // empty message
        Expanded(
          child: Center(
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
                    'This session was recorded without raw gyro/accel time-series data.',
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
          ),
        ),
      ],
    );
  }

  // ============================================
  // Header
  // ============================================
  Widget _buildHeader(SessionLog session, ReplayTrace trace, double avgScore) {
    final duration = Duration(milliseconds: (trace.totalDurationSeconds * 1000).round());
    final durStr = '${duration.inMinutes.toString().padLeft(2, '0')}:'
        '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Container(
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
                  'OFFLINE REPLAY',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: StsysTheme.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${trace.shots.length} shots · $durStr · ${trace.sampleRateHz.toInt()} Hz',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: trace.hasShots
                        ? _scoreColor(avgScore)
                        : StsysTheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showInfoDialog(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: StsysTheme.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.info_outline,
                size: 20,
                color: StsysTheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        backgroundColor: StsysTheme.surfaceContainerHigh,
        title: Text(
          'ABOUT REPLAY',
          style: StsysText.labelBold.copyWith(color: StsysTheme.secondary),
        ),
        content: Text(
          'The barrel trace and shot breakdown are reconstructed from '
          'the original raw sensor data using the offline replay engine. '
          'Results should match what was scored live.',
          style: StsysText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
                color: StsysTheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // Trace view
  // ============================================
  Widget _buildTraceView(ReplayTrace trace) {
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
                child: TrajectoryCanvas(
                  trace: trace,
                  selectedShot: _selectedShot,
                  getScoreColor: _scoreColor,
                  onShotTapped: _selectShot,
                  frameIndex: _frameIndex,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

  Widget _buildEmptyTrace() {
    return Center(
      child: Text(
        'NO SHOTS RECORDED',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          color: StsysTheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  Widget _buildEmptyPanel() {
    return Center(
      child: Text(
        'SELECT A SHOT TO INSPECT',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          color: StsysTheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  // ============================================
  // Shot chips
  // ============================================
  Widget _buildShotChips(ReplayTrace trace) {
    return Container(
      color: StsysTheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'REPLAYED SHOTS',
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
                  color: StsysTheme.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${trace.shots.length}',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: StsysTheme.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: trace.shots.length,
              itemBuilder: (context, index) {
                final shot = trace.shots[index];
                final isSelected = shot == _selectedShot;
                final color = _scoreColor(shot.totalScore);

                return GestureDetector(
                  onTap: () => _selectShot(shot),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 70,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.15)
                          : StsysTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? color
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
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          't=${shot.breakTSeconds.toStringAsFixed(2)}s',
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
    );
  }
}

// ============================================
// Per-shot 3-phase panel
// ============================================
class _ReplayShotPanel extends StatelessWidget {
  final ReplayShot shot;
  final int shotIndex;
  final Color Function(double) getScoreColor;

  const _ReplayShotPanel({
    required this.shot,
    required this.shotIndex,
    required this.getScoreColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PhaseSummaryCard(
            shot: shot,
            shotIndex: shotIndex,
            getScoreColor: getScoreColor,
          ),
        ),
        FactorBreakdownCard(shot: shot),
      ],
    );
  }
}

// ============================================
// Error / not-found view
// ============================================
class _ErrorView extends StatelessWidget {
  final VoidCallback onBack;

  const _ErrorView({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: StsysTheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.arrow_back,
                      size: 20,
                      color: StsysTheme.onSurface.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: StsysTheme.error.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(
                  'SESSION NOT FOUND',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: StsysTheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================
// Internal result wrapper
// ============================================
class _ReplayResult {
  final SessionLog session;
  final ReplayTrace trace;

  const _ReplayResult({required this.session, required this.trace});
}
