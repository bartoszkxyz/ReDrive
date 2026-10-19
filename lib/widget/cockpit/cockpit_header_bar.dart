import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/custom_dashboard_theme.dart';
import '../../core/theme/theme_engine.dart';
import '../../providers/bluetooth_provider.dart';
import '../../providers/obd_provider.dart';
import '../../screens/settings_screen.dart';
import '../../services/headunit/native_app_launcher_service.dart';

/// Top minimal automotive status bar for the TS18 1280x720 cockpit launcher.
/// Displays live time, DVR recording badge, Bluetooth status, and settings launcher.
class CockpitHeaderBar extends StatefulWidget {
  final NativeAppLauncherService? launcherService;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenConnections;
  final VoidCallback? onOpenDashboard;
  final VoidCallback? onOpenTrips;
  final bool? isBtConnected;
  final bool? isDvrRecording;
  final DateTime Function()? nowProvider;
  final bool enableBlinkAnimation;
  final bool enablePeriodicTimers;

  const CockpitHeaderBar({
    super.key,
    this.launcherService,
    this.onOpenSettings,
    this.onOpenConnections,
    this.onOpenDashboard,
    this.onOpenTrips,
    this.isBtConnected,
    this.isDvrRecording,
    this.nowProvider,
    this.enableBlinkAnimation = false,
    this.enablePeriodicTimers = true,
  });

  @override
  State<CockpitHeaderBar> createState() => _CockpitHeaderBarState();
}

class _CockpitHeaderBarState extends State<CockpitHeaderBar>
    with SingleTickerProviderStateMixin {
  late final NativeAppLauncherService _launcher;
  Timer? _clockTimer;
  Timer? _dvrCheckTimer;
  bool _dvrRecording = false;
  AnimationController? _blinkController;
  Animation<double>? _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _launcher = widget.launcherService ?? NativeAppLauncherService();

    if (widget.isDvrRecording != null) {
      _dvrRecording = widget.isDvrRecording!;
    } else {
      _checkDvrStatus();
      if (widget.enablePeriodicTimers) {
        _dvrCheckTimer = Timer.periodic(const Duration(seconds: 4), (_) {
          _checkDvrStatus();
        });
      }
    }

    if (widget.enableBlinkAnimation) {
      _blinkController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..repeat(reverse: true);
      _blinkAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(_blinkController!);
    }

    if (widget.enablePeriodicTimers) {
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant CockpitHeaderBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDvrRecording != null) {
      _dvrRecording = widget.isDvrRecording!;
    }
  }

  Future<void> _checkDvrStatus() async {
    final running = await _launcher.isDvrRecording();
    if (mounted) {
      setState(() {
        _dvrRecording = running;
      });
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _dvrCheckTimer?.cancel();
    _blinkController?.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final themeEngine = context.watch<ThemeEngine?>();
    final colors = themeEngine?.colors ?? const CustomThemeColors();

    final btProvider = context.watch<BluetoothProvider?>();
    final obdProvider = context.watch<ObdProvider?>();

    final isBtConnected = widget.isBtConnected ??
        btProvider?.isConnected ??
        obdProvider?.isDeviceConnected ??
        false;

    final now = widget.nowProvider != null ? widget.nowProvider!() : DateTime.now();
    final timeStr = _formatTime(now);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surfaceCard.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colors.textMuted.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Digital Clock
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 18,
                color: colors.primaryAccent,
              ),
              const SizedBox(width: 8),
              Text(
                timeStr,
                key: const Key('cockpit_header_time'),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: colors.textMain,
                ),
              ),
            ],
          ),

          // Center: OBDrive Portal Controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeaderPortalButton(
                key: const Key('header_open_dashboard'),
                icon: Icons.speed_rounded,
                label: 'FULL DASHBOARD',
                accentColor: colors.primaryAccent,
                colors: colors,
                onTap: widget.onOpenDashboard,
              ),
              const SizedBox(width: 10),
              _buildHeaderPortalButton(
                key: const Key('header_open_trips'),
                icon: Icons.history_rounded,
                label: 'TRIP HISTORY',
                accentColor: colors.secondaryAccent,
                colors: colors,
                onTap: widget.onOpenTrips,
              ),
            ],
          ),

          // Right Controls: DVR Badge, BT Status, Settings
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // DVR: REC Badge
              InkWell(
                key: const Key('dvr_rec_badge'),
                onTap: () => _launcher.launchDvr(),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _dvrRecording
                        ? const Color(0xFF00E676).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _dvrRecording
                          ? const Color(0xFF00E676).withValues(alpha: 0.6)
                          : colors.textMuted.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDvrDot(_dvrRecording),
                      const SizedBox(width: 6),
                      Text(
                        _dvrRecording ? 'DVR: REC' : 'DVR: OFF',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _dvrRecording
                              ? const Color(0xFF00E676)
                              : colors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // BT Status Badge (Tap to open Connections Center)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('bt_status_badge'),
                  onTap: widget.onOpenConnections,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isBtConnected
                          ? colors.secondaryAccent.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isBtConnected
                            ? colors.secondaryAccent.withValues(alpha: 0.6)
                            : colors.textMuted.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bluetooth,
                          size: 15,
                          color: isBtConnected
                              ? colors.secondaryAccent
                              : colors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isBtConnected ? 'BT: Connected' : 'BT: Disconnected',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isBtConnected
                                ? colors.secondaryAccent
                                : colors.textMuted,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Settings Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('cockpit_settings_button'),
                  onTap: () {
                    if (widget.onOpenSettings != null) {
                      widget.onOpenSettings!();
                    } else {
                      showSettingsSheet(context);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.primaryAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colors.primaryAccent.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.settings_outlined,
                      size: 20,
                      color: colors.primaryAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDvrDot(bool isRecording) {
    if (!isRecording) {
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF757575),
        ),
      );
    }

    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF00E676),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E676).withValues(alpha: 0.8),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );

    if (_blinkAnimation != null) {
      return FadeTransition(
        opacity: _blinkAnimation!,
        child: dot,
      );
    }

    return dot;
  }

  Widget _buildHeaderPortalButton({
    required Key key,
    required IconData icon,
    required String label,
    required Color accentColor,
    required CustomThemeColors colors,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: colors.textMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
