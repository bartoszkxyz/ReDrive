import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:redrive/services/settings/app_preferences.dart';
import 'package:redrive/services/logging/log_service.dart';
import 'package:redrive/widget/settings/log_viewer_sheet.dart';

class _DismissibleCupertinoSheetRoute<T> extends CupertinoSheetRoute<T> {
  _DismissibleCupertinoSheetRoute({
    // ignore: deprecated_member_use
    required super.builder,
    super.enableDrag,
    Color barrierColor = const Color(0x73000000), // ~45% black
  }) : _barrierColor = barrierColor;

  final Color _barrierColor;

  @override
  Color? get barrierColor => _barrierColor;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss';
}

void showSettingsSheet(BuildContext context) {
  HapticFeedback.mediumImpact();

  final size = MediaQuery.of(context).size;
  final bool isCompactHeight = size.height <= 750 || size.width > size.height;

  Navigator.of(context, rootNavigator: true).push(
    _DismissibleCupertinoSheetRoute(
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetContext) {
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            if (notification.extent <= notification.minExtent + 0.01) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.canPop(sheetContext)) {
                  Navigator.pop(sheetContext);
                }
              });
            }
            return false;
          },
          child: DraggableScrollableSheet(
            initialChildSize: isCompactHeight ? 0.85 : 0.55,
            minChildSize: isCompactHeight ? 0.45 : 0.40,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return SettingsSheet(scrollController: scrollController);
            },
          ),
        );
      },
    ),
  );
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  bool _autoConnect = true;
  bool _autoTrip = true;
  bool _debugLogging = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final autoConnect = await AppPreferences.isAutoConnectEnabled();
    final autoTrip = await AppPreferences.isAutoTripEnabled();
    final debugLogging = await AppPreferences.isDebugLoggingEnabled();
    if (mounted) {
      setState(() {
        _autoConnect = autoConnect;
        _autoTrip = autoTrip;
        _debugLogging = debugLogging;
      });
    }
  }

  void _showMinDistanceDialog(BuildContext context, TripProvider tripProvider) {
    double tempValue = tripProvider.minTripDistanceKm;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final colorScheme = Theme.of(context).colorScheme;
            return Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  Text(
                    'Minimum Trip Distance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Trips shorter than this threshold will not be saved to history.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    tempValue == 0
                        ? 'Save all trips (0 km)'
                        : '${tempValue < 1 ? tempValue.toStringAsFixed(1) : tempValue.toStringAsFixed(0)} km',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: tempValue,
                    min: 0,
                    max: 50,
                    divisions: 50,
                    activeColor: colorScheme.primary,
                    onChanged: (val) {
                      setModalState(() => tempValue = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [0.0, 0.1, 1.0, 5.0, 10.0, 20.0].map((preset) {
                      final isSelected = tempValue == preset;
                      return ActionChip(
                        label: Text(
                          preset == 0.1
                              ? '0.1 km (Default)'
                              : preset == 0.0
                                  ? '0 km (Off)'
                                  : '${preset < 1 ? preset.toStringAsFixed(1) : preset.toInt()} km',
                        ),
                        backgroundColor: isSelected
                            ? colorScheme.primary.withValues(alpha: 0.2)
                            : colorScheme.onSurface.withValues(alpha: 0.05),
                        labelStyle: TextStyle(
                          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onPressed: () {
                          setModalState(() => tempValue = preset);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(modalContext),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            tripProvider.setMinTripDistanceKm(tempValue);
                            Navigator.pop(modalContext);
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final tripProvider = context.watch<TripProvider>();
    final obdProvider = context.watch<ObdProvider>();
    final isDemo = obdProvider.mode == ObdMode.demo;
    final isReal = obdProvider.mode == ObdMode.real;

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              controller: widget.scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l.settings,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.1,
                              ),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Setting Tiles ─────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, bottomPadding + 40),
                    child: Column(
                      children: [
                        // Min Trip Distance
                        _SettingsTile(
                          icon: Icons.route_rounded,
                          label: 'Min Trip Distance',
                          subtitle: 'Save trips longer than this threshold',
                          trailingText: tripProvider.minTripDistanceKm == 0
                              ? '0 km (All)'
                              : '${tripProvider.minTripDistanceKm < 1 ? tripProvider.minTripDistanceKm.toStringAsFixed(1) : tripProvider.minTripDistanceKm.toStringAsFixed(0)} km',
                          colorScheme: colorScheme,
                          onTap: () => _showMinDistanceDialog(context, tripProvider),
                        ),
                        const SizedBox(height: 10),

                        // Auto-Connect OBD
                        _SettingsTile(
                          icon: Icons.bluetooth_connected_rounded,
                          label: 'Auto-Connect OBD',
                          subtitle: 'Connect to last device on startup',
                          colorScheme: colorScheme,
                          trailing: Switch.adaptive(
                            value: _autoConnect,
                            activeTrackColor: colorScheme.primary,
                            onChanged: (val) {
                              setState(() => _autoConnect = val);
                              AppPreferences.setAutoConnectEnabled(val);
                            },
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Auto-Start Trip
                        _SettingsTile(
                          icon: Icons.speed_rounded,
                          label: 'Auto-Start Trips',
                          subtitle: 'Detect engine running (>400 RPM)',
                          colorScheme: colorScheme,
                          trailing: Switch.adaptive(
                            value: _autoTrip,
                            activeTrackColor: colorScheme.primary,
                            onChanged: (val) {
                              setState(() => _autoTrip = val);
                              AppPreferences.setAutoTripEnabled(val);
                            },
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Demo Mode Simulation
                        _SettingsTile(
                          icon: Icons.play_circle_outline_rounded,
                          label: 'Demo Mode',
                          subtitle: isDemo
                              ? 'Simulating ECU telemetry'
                              : 'Simulate sensor data for testing',
                          colorScheme: colorScheme,
                          trailing: Switch.adaptive(
                            value: isDemo,
                            activeTrackColor: colorScheme.primary,
                            onChanged: (val) async {
                              if (val) {
                                if (isReal) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(l.disconnectEcuFirst)),
                                  );
                                  return;
                                }
                                await obdProvider.startDemoMode();
                              } else {
                                await obdProvider.stopDemoMode();
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Engine Displacement (Suzuki Swift M15A)
                        _SettingsTile(
                          icon: Icons.local_gas_station_rounded,
                          label: 'Engine Profile',
                          subtitle: 'Suzuki Swift M15A (1.5L VVT)',
                          trailingText: '1.5 L',
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(height: 10),

                        // Headunit Autostart & Background Permissions
                        _SettingsTile(
                          icon: Icons.power_settings_new_rounded,
                          label: 'Headunit Autostart',
                          subtitle: 'Configure overlay & background permissions',
                          colorScheme: colorScheme,
                          onTap: () async {
                            await [
                              Permission.systemAlertWindow,
                              Permission.ignoreBatteryOptimizations,
                            ].request();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Autostart and battery optimization permissions requested'),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 10),

                        // Debug / Log Collection
                        _SettingsTile(
                          icon: Icons.bug_report_rounded,
                          label: 'Debug Logging',
                          subtitle: _debugLogging
                              ? 'Collecting diagnostic logs (tap to view)'
                              : 'Collect logs for troubleshooting',
                          colorScheme: colorScheme,
                          trailing: Switch.adaptive(
                            value: _debugLogging,
                            activeTrackColor: colorScheme.primary,
                            onChanged: (val) async {
                              setState(() => _debugLogging = val);
                              await LogService.setEnabled(val);
                            },
                          ),
                          onTap: () {
                            showLogViewerSheet(context);
                          },
                        ),

                        if (_debugLogging) ...[
                          const SizedBox(height: 10),
                          _SettingsTile(
                            icon: Icons.terminal_rounded,
                            label: 'View Diagnostic Logs',
                            subtitle: 'Inspect live logs, search, copy or clear',
                            trailingText: 'Open',
                            colorScheme: colorScheme,
                            onTap: () {
                              showLogViewerSheet(context);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final ColorScheme colorScheme;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: colorScheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailingText != null) ...[
                  Text(
                    trailingText!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (trailing != null)
                  trailing!
                else if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
