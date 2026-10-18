import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/obd_provider.dart';
import '../../services/settings/app_preferences.dart';
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

class HeadunitBackgroundSheet extends StatefulWidget {
  const HeadunitBackgroundSheet({super.key});

  @override
  State<HeadunitBackgroundSheet> createState() => _HeadunitBackgroundSheetState();
}

class _HeadunitBackgroundSheetState extends State<HeadunitBackgroundSheet> {
  static const MethodChannel _storageChannel =
      MethodChannel('com.example.redrive/storage');

  bool _autoLaunch = true;
  String? _lastBootAction;
  String? _lastBootTimestamp;
  bool _isLoading = true;
  bool _isDumping = false;
  String? _lastDumpPath;
  String? _lastDumpSummary;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final autoLaunch = await AppPreferences.isAutoLaunchOnBootEnabled();
    final action = await AppPreferences.getLastBootAction();
    final timestamp = await AppPreferences.getLastBootTimestamp();

    if (mounted) {
      setState(() {
        _autoLaunch = autoLaunch;
        _lastBootAction = action;
        _lastBootTimestamp = timestamp;
        _isLoading = false;
      });
    }
  }

  Future<void> _exportHeadunitProfile() async {
    if (_isDumping) return;
    final mq = MediaQuery.of(context);
    final flutterMetrics = <String, dynamic>{
      'logicalWidthDp': mq.size.width,
      'logicalHeightDp': mq.size.height,
      'devicePixelRatio': mq.devicePixelRatio,
      'paddingTop': mq.padding.top,
      'paddingBottom': mq.padding.bottom,
      'paddingLeft': mq.padding.left,
      'paddingRight': mq.padding.right,
      'viewPaddingTop': mq.viewPadding.top,
      'viewPaddingBottom': mq.viewPadding.bottom,
      'systemGestureInsetsBottom': mq.systemGestureInsets.bottom,
    };

    setState(() => _isDumping = true);
    try {
      final res = await _storageChannel.invokeMapMethod<String, dynamic>(
        'dumpHeadunitProfile',
        <String, dynamic>{'flutterMetrics': flutterMetrics},
      );
      if (!mounted) return;
      final savedPath = res?['savedPath']?.toString() ?? '';
      final sdkInt = res?['sdkInt'];
      final release = res?['release'];
      final appsCount = res?['launchableAppsCount'];
      final vendorCount = res?['vendorPackagesCount'];
      final propsCount = res?['systemPropsCount'];

      setState(() {
        _lastDumpPath = savedPath;
        _lastDumpSummary =
            'Android $release (API $sdkInt) • $appsCount apps • $vendorCount vendor pkgs • $propsCount props';
      });

      if (mounted && savedPath.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Headunit dump saved:\n$savedPath'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Copy Path',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: savedPath));
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Headunit dump failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isDumping = false);
      }
    }
  }

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
                        'Ignition lifecycle • Topway TS18, FYT, Allwinner',
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
                // Auto-Launch Control Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.rocket_launch_rounded, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Auto-Launch App on Ignition',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!_isLoading)
                            Switch.adaptive(
                              value: _autoLaunch,
                              activeTrackColor: theme.colorScheme.primary,
                              onChanged: (val) async {
                                setState(() => _autoLaunch = val);
                                await AppPreferences.setAutoLaunchOnBootEnabled(val);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _autoLaunch
                            ? 'On ignition, ReDrive automatically brings its dashboard onto the screen and connects to your OBD-II adapter.'
                            : 'Silent mode active: On ignition, ReDrive wakes up and connects in the background without interrupting your launcher or radio. Toggle ON if you prefer the dashboard to appear on screen immediately.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _lastBootAction != null ? Icons.check_circle_rounded : Icons.pending_rounded,
                            size: 16,
                            color: _lastBootAction != null ? Colors.greenAccent : Colors.amberAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Last Ignition / Wake Event:',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _lastBootAction != null
                                      ? '$_lastBootAction\n($_lastBootTimestamp)'
                                      : 'No wake intent recorded yet (waiting for next vehicle ignition cycle)',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: _lastBootAction != null ? theme.colorScheme.onSurface : Colors.amberAccent,
                                    fontFamily: _lastBootAction != null ? 'monospace' : null,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

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
                const SizedBox(height: 14),

                // Headunit Discovery Dump Card (TS18 / Knockoff Launcher Extractor)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.cyanAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.developer_board_rounded, color: Colors.cyanAccent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Headunit Profile & TS18 Launcher Dump',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Exports a complete JSON snapshot (screen DPI/dimensions, real Android SDK & SoC, all getprop system properties, installed apps, internal com.ts.MainUI / MCU activities for Radio, BT, DSP/EQ, running services, and SWC input devices) to /storage/emulated/0/Download/ReDrive.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                          height: 1.35,
                        ),
                      ),
                      if (_lastDumpPath != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_lastDumpSummary != null)
                                Text(
                                  _lastDumpSummary!,
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                _lastDumpPath!,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.cyanAccent,
                            side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.5)),
                          ),
                          onPressed: _isDumping ? null : _exportHeadunitProfile,
                          icon: _isDumping
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download_rounded, size: 18),
                          label: Text(
                            _isDumping
                                ? 'Scanning Headunit Packages & Props...'
                                : 'Export Headunit Profile Dump',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Info card: Why no permissions dialog
                _buildCard(
                  theme: theme,
                  icon: Icons.info_outline_rounded,
                  iconColor: Colors.amberAccent,
                  title: 'Why standard Android permission popups fail',
                  body:
                      'Chinese Android headunit ROMs (Topway TS18, Allwinner, FYT) do not implement Google\'s standard "Special App Access" settings menus (ACTION_IGNORE_BATTERY_OPTIMIZATIONS or ACTION_MANAGE_OVERLAY_PERMISSION). Requesting them from apps produces no UI window.',
                ),
                const SizedBox(height: 12),

                // Info card 1: First-time launch requirement
                _buildCard(
                  theme: theme,
                  icon: Icons.notifications_active_rounded,
                  iconColor: Colors.amberAccent,
                  title: 'First-time Launch After APK Updates',
                  body:
                      'Android security places all newly installed or updated APKs in a "Stopped State". You must open ReDrive manually once after updating so Android registers the ignition broadcast receivers.',
                ),
                const SizedBox(height: 12),

                // Info card 2: Car Scanner paradigm
                _buildCard(
                  theme: theme,
                  icon: Icons.shield_rounded,
                  iconColor: Colors.greenAccent,
                  title: 'How ReDrive operates (Car Scanner paradigm)',
                  body:
                      'ReDrive runs an Android Foreground Service with an ongoing notification and PARTIAL_WAKE_LOCK. In Android\'s Low Memory Killer (LMK) architecture, foreground services have top priority and will never be killed to free RAM for navigation or music apps.',
                ),
                const SizedBox(height: 12),

                // Info card 3: Headunit ignition lifecycle
                _buildCard(
                  theme: theme,
                  icon: Icons.electric_car_rounded,
                  iconColor: Colors.cyanAccent,
                  title: 'Ignition & Sleep Lifecycle',
                  body:
                      '• Ignition ON (ACC_ON / Boot): ReDrive awakens automatically, launches onto the screen, and retries OBD connection up to 10 times.\n• Ignition OFF (ACC_OFF / Sleep): ReDrive cleanly flushes trip metrics to SQLite disk and closes the Bluetooth RFCOMM socket to ensure 0% battery drain while parked.',
                ),
                const SizedBox(height: 12),

                // Info card 4: Insecure Bluetooth RFCOMM
                _buildCard(
                  theme: theme,
                  icon: Icons.bluetooth_connected_rounded,
                  iconColor: Colors.purpleAccent,
                  title: 'Bluetooth Insecure RFCOMM Fallback',
                  body:
                      'Topway TS18 and Chinese headunits route Bluetooth via an external MCU chip that often freezes on standard Android secure PIN handshakes. ReDrive automatically falls back to an insecure RFCOMM socket, connecting immediately to your paired OBD-II adapter.',
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
