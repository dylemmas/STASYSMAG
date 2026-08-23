import 'package:flutter/material.dart';
import '../models/data_models.dart';

// ============================================
// SHOT HISTORY LIST
// ============================================
class ShotHistoryList extends StatefulWidget {
  final List<ShotResult> shots;
  final ShotResult? selectedShot;
  final void Function(ShotResult) onShotSelected;
  final Color Function(double) getScoreColor;
  final String Function(DateTime) formatTime;
  final String Function(double) formatScore;

  const ShotHistoryList({
    super.key,
    required this.shots,
    required this.selectedShot,
    required this.onShotSelected,
    required this.getScoreColor,
    required this.formatTime,
    required this.formatScore,
  });

  @override
  State<ShotHistoryList> createState() => _ShotHistoryListState();
}

class _ShotHistoryListState extends State<ShotHistoryList> {
  double _cachedAvg = 0;
  int _cachedCount = 0;

  @override
  void initState() {
    super.initState();
    _computeStats();
  }

  @override
  void didUpdateWidget(ShotHistoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recompute only when shots reference changes
    if (!identical(oldWidget.shots, widget.shots)) {
      _computeStats();
    }
  }

  void _computeStats() {
    if (widget.shots.isEmpty) {
      _cachedAvg = 0;
      _cachedCount = 0;
      return;
    }
    double sum = 0;
    for (final s in widget.shots) { sum += s.totalScore; }
    _cachedCount = widget.shots.length;
    _cachedAvg = sum / _cachedCount;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Text(
                  'SESSION HISTORY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                _buildStats(),
              ],
            ),
          ),
          // Shot cards
          Expanded(
            child: ListView.builder(
              itemCount: widget.shots.length,
              itemBuilder: (context, index) {
                final i = widget.shots.length - 1 - index; // Most recent first
                final shot = widget.shots[i];
                final isSelected = shot == widget.selectedShot;
                return ShotCard(
                  shot: shot,
                  shotNumber: i + 1,
                  isSelected: isSelected,
                  onTap: () => widget.onShotSelected(shot),
                  getScoreColor: widget.getScoreColor,
                  formatTime: widget.formatTime,
                  prevShot: i > 0 ? widget.shots[i - 1] : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    if (_cachedCount == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$_cachedCount shots | Avg: ${_cachedAvg.toStringAsFixed(1)}',
        style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ============================================
// SHOT CARD
// ============================================
class ShotCard extends StatelessWidget {
  final ShotResult shot;
  final int shotNumber;
  final bool isSelected;
  final VoidCallback onTap;
  final Color Function(double) getScoreColor;
  final String Function(DateTime) formatTime;
  final ShotResult? prevShot;

  const ShotCard({
    super.key,
    required this.shot,
    required this.shotNumber,
    required this.isSelected,
    required this.onTap,
    required this.getScoreColor,
    required this.formatTime,
    this.prevShot,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = getScoreColor(shot.totalScore);
    final split = prevShot != null
        ? shot.timestamp.difference(prevShot!.timestamp).inMilliseconds
        : 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[200]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Shot number
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$shotNumber',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Time
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatTime(shot.timestamp),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'H:${shot.holdScore.toInt()} P:${shot.pressScore.toInt()} R:${shot.recoilScore.toInt()}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            // Split
            if (split > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: split < 1500
                      ? Colors.green.withValues(alpha: 0.1)
                      : split > 3000
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(split / 1000).toStringAsFixed(2)}s',
                  style: TextStyle(
                    fontSize: 11,
                    color: split < 1500
                        ? Colors.green
                        : split > 3000
                            ? Colors.red
                            : Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            // Score
            Container(
              width: 48,
              height: 32,
              decoration: BoxDecoration(
                color: scoreColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  shot.totalScore.toInt().toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
