import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/obd_provider.dart';
import 'obd_adapter_test_sheet.dart';

void showHeadunitBackgroundSheet(BuildContext context) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) => const HeadunitBackgroundSheet(),
  );
}

class HeadunitBackgroundSheet extends StatelessWidget {
  const HeadunitBackgroundSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF16181C) : Colors.white;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.car_repair_rounded, color: theme.colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Headunit Background Architecture',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Optimized for Chinese Topway / TS18 Headunits',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 24),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                // Quick Status Badges
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildStatusChip(theme, Icons.check_circle_rounded, 'Foreground Service', Colors.greenAccent),
                    _buildStatusChip(theme, Icons.bolt_rounded, 'Partial WakeLock', Colors.cyanAccent),
                    _buildStatusChip(theme, Icons.power_settings_new_rounded, 'ACC Ignition Hooks', Colors.amberAccent),
                    _buildStatusChip(theme, Icons.bluetooth_audio_rounded, 'Insecure RFCOMM', Colors.blueAccent),
                  ],
                ),
                const SizedBox(height: 16),

                // Info card 1: Why no permissions dialog
                _buildCard(
                  theme: theme,
                  icon: Icons.info_outline_rounded,
                  iconColor: Colors.amberAccent,
                  title: 'Why standard Android permission popups fail',
                  body:
                      'Chinese Android headunit ROMs (Topway TS18, Allwinner, FYT) do not implement Google\'s standard "Special App Access" settings menus (ACTION_IGNORE_BATTERY_OPTIMIZATIONS or ACTION_MANAGE_OVERLAY_PERMISSION). Requesting them from apps produces no UI window.',
                ),
                const SizedBox(height: 12),

                // Info card 2: Car Scanner paradigm
                _buildCard(
                  theme: theme,
                  icon: Icons.shield_rounded,
                  iconColor: Colors.greenAccent,
                  title: 'How ReDrive operates (Car Scanner paradigm)',
                  body:
                      'Like Car Scanner, ReDrive runs an Android Foreground Service with an active notification and a PARTIAL_WAKE_LOCK. In Android\'s Low Memory Killer (LMK) architecture, foreground services have top priority and will never be killed to free RAM for navigation or music apps, requiring no battery optimization whitelisting.',
                ),
                const SizedBox(height: 12),

                // Info card 3: Headunit ignition lifecycle
                _buildCard(
                  theme: theme,
                  icon: Icons.electric_car_rounded,
                  iconColor: Colors.cyanAccent,
                  title: 'Ignition & Sleep Lifecycle',
                  body:
                      '• Ignition ON (ACC_ON / Boot): ReDrive awakens silently in the background, waits 2.5 seconds for headunit Bluetooth settling, and retries connection up to 10 times without popping over your launcher or maps.\n• Ignition OFF (ACC_OFF / Sleep): ReDrive cleanly flushes trip metrics to SQLite disk and closes the Bluetooth RFCOMM socket to ensure 0% battery drain while parked.',
                ),
                const SizedBox(height: 12),

                // Info card 4: Insecure Bluetooth RFCOMM
                _buildCard(
                  theme: theme,
                  icon: Icons.bluetooth_connected_rounded,
                  iconColor: Colors.purpleAccent,
                  title: 'Bluetooth Insecure RFCOMM Fallback',
                  body:
                      'Topway TS18 headunits route Bluetooth via an external MCU chip that often freezes on standard Android secure PIN handshakes. ReDrive automatically falls back to an insecure RFCOMM socket, connecting immediately to your paired OBD-II adapter.',
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2024) : Colors.grey.shade100,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final obdProvider = context.read<ObdProvider>();
                      showObdAdapterTestSheet(context, obdProvider);
                    },
                    icon: const Icon(Icons.speed_rounded, size: 18),
                    label: const Text('Test OBD Adapter'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got It'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required ThemeData theme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.4,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
