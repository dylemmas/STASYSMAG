// ============================================
// File: screens/main_screen.dart
// STASYS Dark Theme with Bottom Nav Bar
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/bluetooth_provider.dart';
import 'tabs/home_tab.dart';
import 'tabs/graph_tab.dart';
import 'tabs/connection_tab.dart';
import 'tabs/settings_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeTab(),
    GraphTab(),
    ConnectionTab(),
    SettingsTab(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(Icons.grid_view_outlined, Icons.grid_view, 'HOME'),
    _NavItem(Icons.ads_click_outlined, Icons.ads_click, 'LIVE'),
    _NavItem(Icons.history_outlined, Icons.history, 'HISTORY'),
    _NavItem(Icons.settings_outlined, Icons.settings, 'SETTINGS'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StsysTheme.background,
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: StsysTheme.background,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: StsysTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Image(
              image: AssetImage('assets/icon/app_icon.png'),
              width: 28,
              height: 28,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'STASYS',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w900,
              fontSize: 22,
              color: StsysTheme.primary,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      actions: [
        Consumer<BluetoothProvider>(
          builder: (context, bt, child) {
            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: StatusBadge(
                isConnected: bt.isConnected,
                deviceName: bt.selectedDevice?.name,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: StsysTheme.background,
        border: Border(
          top: BorderSide(
            color: StsysTheme.onSurface.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_navItems.length, (index) {
              final item = _navItems[index];
              final isActive = _currentIndex == index;
              return _NavButton(
                item: item,
                isActive: isActive,
                onTap: () => setState(() => _currentIndex = index),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem(this.icon, this.activeIcon, this.label);
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isActive ? 20 : 16,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? StsysTheme.primaryContainer.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? item.activeIcon : item.icon,
              color: isActive
                  ? StsysTheme.primary
                  : StsysTheme.onSurface.withValues(alpha: 0.4),
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: isActive
                    ? StsysTheme.primary
                    : StsysTheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
