import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/settings_provider.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';
import 'tabs/graph_tab.dart';

class TrackingModeView extends StatelessWidget {
  final void Function(FirearmType) onModeSelected;
  final VoidCallback onBackToModeView;

  const TrackingModeView({
    super.key,
    required this.onModeSelected,
    required this.onBackToModeView,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        final mode = settings.firearmType;

        return Scaffold(
          backgroundColor: StsysTheme.surfaceContainerLowest,
          body: SafeArea(
            child: Column(
              children: [
                // Header with back to mode selection
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                        onTap: () => context.go('/tracking'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: StsysTheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_back,
                                size: 16,
                                color: StsysTheme.onSurface.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'MODE',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: StsysTheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: StsysTheme.tacticalGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          mode.displayName.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: StsysTheme.onPrimary,
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: StsysTheme.surfaceContainerHigh,
                              title: Text(
                                'GANTI MODE?',
                                style: StsysText.labelBold.copyWith(
                                  color: StsysTheme.primary,
                                ),
                              ),
                              content: Text(
                                'Ingin kembali ke pemilihan mode?',
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
                                    onBackToModeView();
                                  },
                                  child: Text(
                                    'YA',
                                    style: TextStyle(
                                      fontFamily: 'Manrope',
                                      fontWeight: FontWeight.w800,
                                      color: StsysTheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: StsysTheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.swap_horiz,
                                size: 16,
                                color: StsysTheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'GANTI',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: StsysTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Demo mode banner
                if (settings.isDemoMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.science_outlined,
                          size: 14,
                          color: Color(0xFFFF9800),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'DEMO MODE — Connect device to use real data',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: const Color(0xFFFF9800),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Live Graph
                const Expanded(
                  child: GraphTab(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
