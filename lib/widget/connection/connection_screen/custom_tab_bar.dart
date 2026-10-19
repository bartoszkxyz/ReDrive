import 'package:flutter/material.dart';

enum ConnectionTab { obd, sync, wifi, troubleshoot }

class CustomTabBar extends StatelessWidget {
  final ConnectionTab selectedTab;
  final ValueChanged<ConnectionTab> onTabSelected;

  const CustomTabBar({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          _TabItem(
            key: const Key('tab_obd'),
            tab: ConnectionTab.obd,
            icon: Icons.directions_car_rounded,
            label: 'OBD (ELM327)',
            currentTab: selectedTab,
            onTap: onTabSelected,
          ),
          _TabItem(
            key: const Key('tab_sync'),
            tab: ConnectionTab.sync,
            icon: Icons.sync_rounded,
            label: 'Phone Sync',
            currentTab: selectedTab,
            onTap: onTabSelected,
          ),
          _TabItem(
            key: const Key('tab_wifi'),
            tab: ConnectionTab.wifi,
            icon: Icons.wifi_rounded,
            label: 'Wi-Fi / TCP',
            currentTab: selectedTab,
            onTap: onTabSelected,
          ),
          _TabItem(
            key: const Key('tab_troubleshoot'),
            tab: ConnectionTab.troubleshoot,
            icon: Icons.build_circle_rounded,
            label: 'Diagnostics',
            currentTab: selectedTab,
            onTap: onTabSelected,
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final ConnectionTab tab;
  final ConnectionTab currentTab;
  final IconData icon;
  final String label;
  final ValueChanged<ConnectionTab> onTap;

  const _TabItem({
    super.key,
    required this.tab,
    required this.currentTab,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = currentTab == tab;
    final contentColor = isActive
        ? colorScheme.onPrimary
        : colorScheme.onSurface.withValues(alpha: 0.6);

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(tab),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: contentColor, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: contentColor,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
