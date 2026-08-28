import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/sensor_data_provider.dart';
import '../../providers/session_logger.dart';
import '../../theme/app_theme.dart';
import '../session_detail_screen.dart';
import 'package:intl/intl.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, sessionProvider, child) {
        final sessions = sessionProvider.sessions;

        return CustomScrollView(
          slivers: [
            // Stats Header
            SliverToBoxAdapter(
              child: Consumer<SensorDataProvider>(
                builder: (context, sensor, _) {
                  return _buildStatsHeader(sessions, sensor.batteryLevel);
                },
              ),
            ),

            // Session List
            if (sessions.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // sessions is already sorted newest-first in SessionProvider.loadSessions()
                      final session = sessions[index];
                      return _SessionCard(
                        session: session,
                        sessionNumber: sessions.length - index,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                SessionDetailScreen(session: session),
                          ),
                        ),
                        onDelete: () => _showDeleteDialog(
                            context, sessionProvider, session),
                      );
                    },
                    childCount: sessions.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatsHeader(List<SessionLog> sessions, int batteryLevel) {
    if (sessions.isEmpty) return const SizedBox.shrink();

    final totalSessions = sessions.length;
    final totalDuration = sessions.fold<double>(
        0.0, (sum, s) => sum + s.duration);
    final avgScore = sessions.isEmpty
        ? 0.0
        : sessions.map((s) => s.averageScore).reduce((a, b) => a + b) /
            sessions.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _StatBox(
            label: 'SESSIONS',
            value: '$totalSessions',
            color: StsysTheme.primary,
          ),
          Container(
            width: 1,
            height: 40,
            color: StsysTheme.outlineVariant.withValues(alpha: 0.3),
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          _StatBox(
            label: 'AVG SCORE',
            value: avgScore.toStringAsFixed(1),
            color: StsysTheme.secondary,
          ),
          Container(
            width: 1,
            height: 40,
            color: StsysTheme.outlineVariant.withValues(alpha: 0.3),
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          _StatBox(
            label: 'TOTAL MIN',
            value: '${(totalDuration / 60).toStringAsFixed(0)}',
            color: StsysTheme.tertiary,
          ),
          const Spacer(),
          // Battery indicator
          _BatteryIndicator(level: batteryLevel),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.ads_click_outlined,
            size: 64,
            color: StsysTheme.onSurface.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),
          Text(
            'NO SESSIONS YET',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 2,
              color: StsysTheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your device and start training',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
      BuildContext ctx, SessionProvider provider, SessionLog session) {
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
              'CANCEL',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                color: StsysTheme.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              provider.deleteSession(session);
              Navigator.pop(ctx);
            },
            child: Text(
              'DELETE',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
                color: StsysTheme.error,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Stat Box
// ============================================
class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: StsysTheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Session Card
// ============================================
class _SessionCard extends StatefulWidget {
  final SessionLog session;
  final int sessionNumber;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.sessionNumber,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  double _hoverProgress = 0;

  @override
  Widget build(BuildContext context) {
    final date = widget.session.date;
    final avgScore = widget.session.averageScore;
    final scoreColor = StsysTheme.getScoreColor(avgScore);

    final dateStr = DateFormat('EEEE, dd MMMM yyyy').format(date).toUpperCase();
    final timeStr = DateFormat('HH:mm').format(date);
    final firearmType = widget.session.firearmType.displayName;

    return GestureDetector(
      onTapDown: (_) => setState(() => _hoverProgress = 1),
      onTapUp: (_) {
        setState(() => _hoverProgress = 0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _hoverProgress = 0),
      onLongPress: widget.onDelete,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: StsysTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // Date + time
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: StsysTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$timeStr',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: StsysTheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: StsysTheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: StsysTheme.outlineVariant.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            firearmType.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              color: StsysTheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Shots badge
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: StsysTheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.ads_click,
                                size: 14,
                                color: StsysTheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.session.shots.length}',
                                style: TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: StsysTheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Avg Score
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          avgScore.toStringAsFixed(2),
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: scoreColor,
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          'AVG',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.5,
                            color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Hover gradient line
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: 2,
              decoration: BoxDecoration(
                gradient: StsysTheme.tacticalGradient,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              width: _hoverProgress > 0 ? double.infinity : 0,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Battery Indicator
// ============================================
class _BatteryIndicator extends StatelessWidget {
  final int level;

  const _BatteryIndicator({required this.level});

  IconData get _icon {
    if (level >= 80) return Icons.battery_full;
    if (level >= 60) return Icons.battery_5_bar;
    if (level >= 40) return Icons.battery_4_bar;
    if (level >= 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color get _color {
    if (level >= 60) return const Color(0xFF4CAF50);
    if (level >= 20) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon, color: _color, size: 20),
        const SizedBox(width: 4),
        Text(
          '$level%',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _color,
          ),
        ),
      ],
    );
  }
}
