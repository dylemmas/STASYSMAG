import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sensor_data_provider.dart';
import '../../models/data_models.dart';
import '../../theme/app_theme.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Training Mode Section
              _SectionHeader('OPERATIONAL MODE'),
              const SizedBox(height: 12),
              _ModeGrid(settings: settings),

              const SizedBox(height: 24),

              // Spatial Orientation
              _SectionHeader('SPATIAL ORIENTATION'),
              const SizedBox(height: 12),
              _SpatialGrid(settings: settings),

              const SizedBox(height: 24),

              // Display Settings
              _SectionHeader('DISPLAY'),
              const SizedBox(height: 12),
              _GraphDurationSlider(settings: settings),

              const SizedBox(height: 24),

              // Scoring Info
              _SectionHeader('SCORING RANK'),
              const SizedBox(height: 12),
              _ScoringGuide(settings: settings),

              const SizedBox(height: 32),

              // Version footer
              Center(
                child: Text(
                  'STASYS v3.1.0 • STASYS App',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: StsysTheme.onSurfaceVariant,
      ),
    );
  }
}

class _ModeGrid extends StatelessWidget {
  final SettingsProvider settings;
  const _ModeGrid({required this.settings});

  @override
  Widget build(BuildContext context) {
    // Map firearm types to visual labels
    final modes = [
      ('DA', FirearmType.pistol, 'DRY AS'),
      ('AS', FirearmType.rifle, 'LIVE AS'),
      ('DFA', FirearmType.archery, 'DRY FIREARM'),
      ('FA', FirearmType.shotgun, 'LIVE FIREARM'),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.2,
      children: modes.map((m) {
        final isActive = settings.firearmType == m.$2;
        return GestureDetector(
          onTap: () => settings.updateFirearmType(m.$2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: isActive ? StsysTheme.tacticalGradient : null,
              color: isActive ? null : StsysTheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? null
                  : Border.all(
                      color: StsysTheme.outlineVariant.withValues(alpha: 0.15),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  m.$1,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: isActive
                        ? StsysTheme.onPrimary
                        : StsysTheme.onSurface,
                  ),
                ),
                Text(
                  m.$3,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    letterSpacing: 1,
                    color: isActive
                        ? StsysTheme.onPrimary.withValues(alpha: 0.7)
                        : StsysTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SpatialGrid extends StatelessWidget {
  final SettingsProvider settings;
  const _SpatialGrid({required this.settings});

  @override
  Widget build(BuildContext context) {
    final mountOptions = [
      (MountPosition.top, 'TOP'),
      (MountPosition.bottom, 'BOT'),
      (MountPosition.left, 'LEFT'),
      (MountPosition.right, 'RIGHT'),
    ];
    return Column(
      children: [
        Row(
          children: mountOptions.map((entry) {
            final pos = entry.$1;
            final label = entry.$2;
            final idx = mountOptions.indexOf(entry);
            final isActive = settings.mountPosition == pos;
            return Expanded(
              child: GestureDetector(
                onTap: () => settings.updateMountPosition(pos),
                child: Container(
                  margin: EdgeInsets.only(
                    right: idx < mountOptions.length - 1 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isActive
                        ? StsysTheme.primary.withValues(alpha: 0.15)
                        : StsysTheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive
                          ? StsysTheme.primary.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: isActive
                            ? StsysTheme.primary
                            : StsysTheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Direction
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: StsysTheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      'DIRECTION',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    const Spacer(),
                    _MiniToggle(
                      labels: const ['FW', 'BW'],
                      selectedIndex: settings.mountDirection == MountDirection.forward ? 0 : 1,
                      onChanged: (i) {
                        settings.updateMountDirection(
                          i == 0 ? MountDirection.forward : MountDirection.backward,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Calibration
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: StsysTheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CALIBRATION',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        context.read<SensorDataProvider>().resetAxis();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: StsysTheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: StsysTheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'RESET AXIS',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: StsysTheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniToggle extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final void Function(int) onChanged;
  const _MiniToggle({
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: labels.asMap().entries.map((e) {
        final idx = e.key;
        final label = e.value;
        final isActive = idx == selectedIndex;
        return GestureDetector(
          onTap: () => onChanged(idx),
          child: Container(
            margin: EdgeInsets.only(right: idx < labels.length - 1 ? 4 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? StsysTheme.secondary.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive
                    ? StsysTheme.secondary.withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isActive
                    ? StsysTheme.secondary
                    : StsysTheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _GraphDurationSlider extends StatelessWidget {
  final SettingsProvider settings;
  const _GraphDurationSlider({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TRACE WINDOW',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: StsysTheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: StsysTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${settings.maxSamples}s',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: StsysTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbColor: StsysTheme.primary,
              activeTrackColor: StsysTheme.primary,
              inactiveTrackColor: StsysTheme.surfaceContainerHighest,
              overlayColor: StsysTheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: settings.maxSamples.toDouble(),
              min: 2,
              max: 10,
              divisions: 8,
              onChanged: (v) => settings.updateMaxSamples(v.round()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '2s',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
              Text(
                '10s',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoringGuide extends StatelessWidget {
  final SettingsProvider settings;
  const _ScoringGuide({required this.settings});

  @override
  Widget build(BuildContext context) {
    final entries = [
      ('ELITE', 95.0, const Color(0xFFFFD700)),
      ('EXPERT', 85.0, const Color(0xFF4CAF50)),
      ('ADVANCED', 70.0, const Color(0xFF2196F3)),
      ('INTERMEDIATE', 50.0, const Color(0xFFFF9800)),
      ('BEGINNER', 0.0, const Color(0xFFF44336)),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StsysTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ...entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: e.$3,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        e.$1,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: StsysTheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '>${e.$2.toInt()}',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          Divider(color: StsysTheme.outlineVariant.withValues(alpha: 0.3), thickness: 1),
          const SizedBox(height: 8),
          Text(
            'Difficulty: ${settings.firearmType.displayName} • ${settings.trainingMode.displayName}',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              letterSpacing: 1,
              color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
