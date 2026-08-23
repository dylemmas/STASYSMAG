// ============================================
// File: widgets/analysis_tab.dart
// ============================================
// Composite post-shot analysis view: barrel-trace canvas, optional
// timeline scrubber, per-shot 3-phase summary card, factor breakdown,
// and the replayed-shot chip selector at the bottom.
//
// Used by SessionDetailScreen when the ANALYSIS toggle is active.

import 'package:flutter/material.dart';
import '../services/trajectory/replay_models.dart';
import '../theme/app_theme.dart';
import 'analysis/factor_breakdown_card.dart';
import 'analysis/phase_summary_card.dart';
import 'analysis/trajectory_canvas.dart';
import 'analysis/trajectory_scrubber.dart';

class AnalysisTab extends StatefulWidget {
  final ReplayTrace trace;

  const AnalysisTab({super.key, required this.trace});

  @override
  State<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<AnalysisTab> {
  ReplayShot? _selectedShot;
  int _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.trace.hasShots) {
      _selectedShot = widget.trace.shots.first;
    }
    if (widget.trace.frames.isNotEmpty) {
      _frameIndex = widget.trace.frames.length - 1;
    }
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
      _frameIndex = shot.breakIndex.clamp(0, widget.trace.frames.length - 1);
    });
  }

  void _onFrameChanged(int idx) {
    setState(() => _frameIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    final trace = widget.trace;

    if (trace.isEmpty) {
      return Center(
        child: Text(
          'NO TRACE DATA',
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

    if (!trace.hasShots) {
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

    final selectedShot =
        _selectedShot ?? trace.shots.first;
    final shotIndex = trace.shots.indexOf(selectedShot);

    return Column(
      children: [
        // Barrel trace (flex 2 of remaining)
        Expanded(
          flex: 2,
          child: TrajectoryCanvas(
            trace: trace,
            selectedShot: _selectedShot,
            getScoreColor: _scoreColor,
            onShotTapped: _selectShot,
          ),
        ),
        // Scrubber
        TrajectoryScrubber(
          trace: trace,
          frameIndex: _frameIndex,
          onFrameChanged: _onFrameChanged,
        ),
        // Per-shot summary + breakdown (flex 3)
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(
                child: PhaseSummaryCard(
                  shot: selectedShot,
                  shotIndex: shotIndex < 0 ? 0 : shotIndex,
                  getScoreColor: _scoreColor,
                ),
              ),
              FactorBreakdownCard(shot: selectedShot),
            ],
          ),
        ),
        // Shot chip selector (flex 1)
        Expanded(
          flex: 1,
          child: _ShotChipStrip(
            trace: trace,
            selectedShot: _selectedShot,
            getScoreColor: _scoreColor,
            onSelect: _selectShot,
          ),
        ),
      ],
    );
  }
}

class _ShotChipStrip extends StatelessWidget {
  final ReplayTrace trace;
  final ReplayShot? selectedShot;
  final Color Function(double) getScoreColor;
  final ValueChanged<ReplayShot> onSelect;

  const _ShotChipStrip({
    required this.trace,
    required this.selectedShot,
    required this.getScoreColor,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
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
                final isSelected = shot == selectedShot;
                final color = getScoreColor(shot.totalScore);

                return GestureDetector(
                  onTap: () => onSelect(shot),
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
