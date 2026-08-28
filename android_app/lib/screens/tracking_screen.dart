import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/sensor_data_provider.dart';
import '../models/data_models.dart';
import '../theme/app_theme.dart';
import 'tracking_mode_view.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  bool _showModeView = false;

  void resetToModeView() {
    setState(() => _showModeView = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showModeView) {
      return TrackingModeView(
        onModeSelected: (mode) {
          setState(() => _showModeView = false);
        },
        onBackToModeView: () {
          resetToModeView();
        },
      );
    }

    return _buildModeSelectionView();
  }

  Widget _buildModeSelectionView() {
    return Scaffold(
      backgroundColor: StsysTheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),

            // Demo mode banner
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
                if (!settings.isDemoMode) return const SizedBox.shrink();
                return Container(
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
                );
              },
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SELECT MODE',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: StsysTheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose your training mode',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: StsysTheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 2x2 Mode Grid
                    Expanded(
                      child: Consumer<SettingsProvider>(
                        builder: (context, settings, _) {
                          return GridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.1,
                            children: FirearmType.values.map((mode) {
                              return _ModeCard(
                                mode: mode,
                                isSelected: settings.firearmType == mode,
                                onTap: () {
                                  settings.updateFirearmType(mode);
                                  setState(() => _showModeView = true);
                                },
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
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
          Consumer<BluetoothProvider>(
            builder: (context, bt, _) {
              return StatusBadge(
                isConnected: bt.isConnected,
                deviceName: bt.isConnected ? bt.connectedDeviceName : null,
              );
            },
          ),
          const SizedBox(width: 8),
          Consumer<SensorDataProvider>(
            builder: (context, sensor, _) {
              return _BatteryIndicator(level: sensor.batteryLevel);
            },
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final FirearmType mode;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  IconData get _icon {
    switch (mode) {
      case FirearmType.pistol:
        return Icons.flash_on;
      case FirearmType.rifle:
        return Icons.sports_martial_arts;
      case FirearmType.archery:
        return Icons.gps_fixed;
      case FirearmType.shotgun:
        return Icons.local_fire_department;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? StsysTheme.primary.withValues(alpha: 0.1)
              : StsysTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? StsysTheme.primary
                : StsysTheme.outlineVariant.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: isSelected ? StsysTheme.tacticalGradient : null,
                color: isSelected
                    ? null
                    : StsysTheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _icon,
                color: isSelected
                    ? StsysTheme.onPrimary
                    : StsysTheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              mode.displayName.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: isSelected
                    ? StsysTheme.primary
                    : StsysTheme.onSurface,
              ),
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
        Icon(_icon, color: _color, size: 18),
        const SizedBox(width: 2),
        Text(
          '$level%',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _color,
          ),
        ),
      ],
    );
  }
}
