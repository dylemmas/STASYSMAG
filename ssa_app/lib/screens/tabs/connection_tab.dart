import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../../providers/bluetooth_provider.dart';
import '../../theme/app_theme.dart';

class ConnectionTab extends StatelessWidget {
  const ConnectionTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothProvider>(
      builder: (context, btProvider, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection Status Card
              _ConnectionStatusCard(
                isConnected: btProvider.isConnected,
                deviceName: btProvider.selectedDevice?.name,
                address: btProvider.selectedDevice?.address,
                onDisconnect: btProvider.disconnect,
              ),

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: _ActionBtn(
                      icon: Icons.search,
                      label: 'SCAN',
                      color: StsysTheme.primary,
                      isLoading: btProvider.isScanning,
                      onTap: btProvider.isScanning
                          ? null
                          : btProvider.startScan,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionBtn(
                      icon: Icons.bluetooth_searching,
                      label: 'PAIRED',
                      color: StsysTheme.secondary,
                      onTap: btProvider.getBondedDevices,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Device List
              const Text(
                'AVAILABLE DEVICES',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: StsysTheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 12),

              if (btProvider.devicesList.isEmpty)
                _EmptyDevicesState()
              else
                ...btProvider.devicesList.map(
                  (device) => _DeviceCard(
                    device: device,
                    isConnected: btProvider.isConnected &&
                        btProvider.selectedDevice == device,
                    onTap: () async {
                      bool ok = await btProvider.connectToDevice(device);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to connect',
                              style: StsysText.body.copyWith(color: StsysTheme.onSurface),
                            ),
                            backgroundColor: StsysTheme.surfaceContainerHigh,
                          ),
                        );
                      }
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  final bool isConnected;
  final String? deviceName;
  final String? address;
  final VoidCallback onDisconnect;

  const _ConnectionStatusCard({
    required this.isConnected,
    this.deviceName,
    this.address,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected
            ? StsysTheme.primary.withValues(alpha: 0.1)
            : StsysTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? StsysTheme.primary.withValues(alpha: 0.3)
              : StsysTheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isConnected
                  ? StsysTheme.primary.withValues(alpha: 0.2)
                  : StsysTheme.error.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: isConnected ? StsysTheme.primary : StsysTheme.error,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? deviceName ?? 'CONNECTED' : 'NOT CONNECTED',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color:
                        isConnected ? StsysTheme.primary : StsysTheme.error,
                    letterSpacing: 0.5,
                  ),
                ),
                if (isConnected && address != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    address!,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.6),
                      letterSpacing: 1,
                    ),
                  ),
                ],
                if (!isConnected) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Tap SCAN to discover devices',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isConnected)
            GestureDetector(
              onTap: onDisconnect,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: StsysTheme.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.bluetooth_disabled,
                  color: StsysTheme.error,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback? onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: enabled
              ? LinearGradient(
                  colors: [color.withValues(alpha: 0.8), color],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : null,
          color: enabled ? null : StsysTheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: StsysTheme.onSurface.withValues(alpha: 0.4),
                ),
              )
            else
              Icon(
                icon,
                size: 18,
                color: enabled
                    ? StsysTheme.onPrimary
                    : StsysTheme.onSurface.withValues(alpha: 0.3),
              ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1.5,
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

class _DeviceCard extends StatelessWidget {
  final BluetoothDevice device;
  final bool isConnected;
  final VoidCallback onTap;

  const _DeviceCard({
    required this.device,
    required this.isConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isConnected ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isConnected
              ? StsysTheme.primary.withValues(alpha: 0.08)
              : StsysTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isConnected
                ? StsysTheme.primary.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isConnected
                    ? StsysTheme.primary.withValues(alpha: 0.2)
                    : StsysTheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.bluetooth,
                color: isConnected
                    ? StsysTheme.primary
                    : StsysTheme.secondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name ?? 'Unknown Device',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 15,
                      fontWeight:
                          isConnected ? FontWeight.w800 : FontWeight.w600,
                      color: StsysTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.address,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      letterSpacing: 1,
                      color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (isConnected)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: StsysTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 14,
                      color: StsysTheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'CONNECTED',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: StsysTheme.primary,
                      ),
                    ),
                  ],
                ),
              )
            else
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDevicesState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.bluetooth_searching,
            size: 48,
            color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'SCANNING FOR DEVICES...',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Make sure your STASYS device is powered on',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: StsysTheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
