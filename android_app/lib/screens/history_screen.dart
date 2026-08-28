import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';
import 'session_detail_screen.dart';
import 'replay_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh session list on app resume
      context.read<SessionProvider>().loadSessions();
    }
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StsysTheme.surfaceContainerHigh,
        title: Text(
          'HAPUS SEMUA SESSION?',
          style: StsysText.labelBold.copyWith(color: StsysTheme.error),
        ),
        content: Text(
          'Semua data akan hilang dan tidak bisa dikembalikan.',
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
              _clearAllSessions();
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

  void _clearAllSessions() async {
    final provider = context.read<SessionProvider>();
    final sessions = List.from(provider.sessions);
    for (final session in sessions) {
      await provider.deleteSession(session);
    }
  }

  void _exportSessions(BuildContext ctx) async {
    final provider = ctx.read<SessionProvider>();
    final sessions = provider.sessions;

    if (sessions.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: const Text('No sessions to export'),
          backgroundColor: StsysTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final exportService = ExportService();
      await exportService.shareSessionsCSV(sessions);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: StsysTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StsysTheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),

            // Session List
            Expanded(
              child: Consumer<SessionProvider>(
                builder: (context, sessionProvider, _) {
                  final sessions = sessionProvider.sessions;

                  if (sessions.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final avgScore = session.averageScore;
                      final scoreColor = StsysTheme.getScoreColor(avgScore);
                      final dateStr = DateFormat('EEEE, dd MMMM yyyy')
                          .format(session.date)
                          .toUpperCase();
                      final timeStr = DateFormat('HH:mm').format(session.date);

                      return Dismissible(
                        key: Key(session.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: StsysTheme.error.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.delete, color: StsysTheme.error),
                        ),
                        confirmDismiss: (_) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: StsysTheme.surfaceContainerHigh,
                              title: Text(
                                'HAPUS SESSION?',
                                style: StsysText.labelBold.copyWith(
                                  color: StsysTheme.error,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text('BATAL',
                                      style: TextStyle(
                                          color: StsysTheme.onSurfaceVariant)),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text('HAPUS',
                                      style: TextStyle(color: StsysTheme.error)),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (_) {
                          sessionProvider.deleteSession(session);
                        },
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    SessionDetailScreen(session: session),
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: StsysTheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
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
                                        timeStr,
                                        style: const TextStyle(
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
                                        ),
                                        child: Text(
                                          session.firearmType.displayName.toUpperCase(),
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 1,
                                            color: StsysTheme.onSurface
                                                .withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                                            Icon(Icons.ads_click, size: 14, color: StsysTheme.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${session.shots.length}',
                                              style: const TextStyle(
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
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'AVG',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 9,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: 1.5,
                                              color: StsysTheme.onSurfaceVariant
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => ReplayScreen(
                                                    sessionId: session.id,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: StsysTheme.secondary
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Icon(
                                                Icons.timeline,
                                                size: 14,
                                                color: StsysTheme.secondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
          // Refresh button
          Consumer<SessionProvider>(
            builder: (context, sessionProvider, _) {
              return GestureDetector(
                onTap: () => sessionProvider.loadSessions(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: StsysTheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.refresh,
                    size: 20,
                    color: StsysTheme.primary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          ShaderMask(
            shaderCallback: (bounds) {
              return StsysTheme.tacticalGradient.createShader(bounds);
            },
            child: const Text(
              'STASYS',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              if (!settings.isDemoMode) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.science_outlined, size: 12, color: Color(0xFFFF9800)),
                    const SizedBox(width: 4),
                    Text(
                      'DEMO',
                      style: TextStyle(
                        fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w700,
                        letterSpacing: 1, color: const Color(0xFFFF9800),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const Spacer(),
          Consumer<SessionProvider>(
            builder: (context, sessionProvider, _) {
              if (sessionProvider.sessions.isEmpty) {
                return const SizedBox.shrink();
              }
              return GestureDetector(
                onTap: () => _exportSessions(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: StsysTheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.share,
                    size: 20,
                    color: StsysTheme.primary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Consumer<SessionProvider>(
            builder: (context, sessionProvider, _) {
              if (sessionProvider.sessions.isEmpty) {
                return const SizedBox.shrink();
              }
              return GestureDetector(
                onTap: _showClearAllDialog,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: StsysTheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.delete_sweep,
                    size: 20,
                    color: StsysTheme.error.withValues(alpha: 0.7),
                  ),
                ),
              );
            },
          ),
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
            color: StsysTheme.onSurface.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'NO SESSIONS YET',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 2,
              color: StsysTheme.onSurface.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your device and start training',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
