import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/custom_dashboard_theme.dart';
import '../core/theme/theme_engine.dart';
import '../obd/pid/pid_key.dart';
import '../obd/polling/polling_controller.dart';
import '../providers/obd_provider.dart';
import '../services/headunit/native_app_launcher_service.dart';
import '../widget/cockpit/cockpit_header_bar.dart';
import '../widget/cockpit/engine_vitals_card.dart';
import '../widget/cockpit/tactile_launcher_dock.dart';
import '../widget/cockpit/trip_flight_computer_card.dart';

/// Topway TS18 Headunit Cockpit Launcher Screen (Layout A - 1280 × 720 Landscape).
///
/// Integrates:
/// 1. [CockpitHeaderBar]: digital clock, DVR recording status, Bluetooth state, settings.
/// 2. [TripFlightComputerCard]: large date/timepiece, 4-metric trip grid, instant fuel flow bar.
/// 3. [EngineVitalsCard]: coolant temperature, engine load, and OBDrive portals.
/// 4. [TactileLauncherDock]: automotive shortcuts (TLINK5, Radio, DSP, DVR, App Drawer).
class HeadunitLauncherScreen extends StatefulWidget {
  final NativeAppLauncherService? launcherService;
  final VoidCallback? onOpenDashboard;
  final VoidCallback? onOpenTrips;
  final VoidCallback? onOpenConnections;
  final VoidCallback? onOpenSettings;
  final DateTime Function()? nowProvider;
  final bool enablePeriodicTimers;

  const HeadunitLauncherScreen({
    super.key,
    this.launcherService,
    this.onOpenDashboard,
    this.onOpenTrips,
    this.onOpenConnections,
    this.onOpenSettings,
    this.nowProvider,
    this.enablePeriodicTimers = true,
  });

  @override
  State<HeadunitLauncherScreen> createState() => _HeadunitLauncherScreenState();
}

class _HeadunitLauncherScreenState extends State<HeadunitLauncherScreen> {
  late final NativeAppLauncherService _launcherService;

  @override
  void initState() {
    super.initState();
    _launcherService = widget.launcherService ?? NativeAppLauncherService();

    // Trigger automated background DVR recording for headunit ignition
    _launcherService.startDvrRecording();

    // Register active screen PID watchlist with OBD provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final obdProvider = context.read<ObdProvider?>();
      obdProvider?.setWatchlist(WatchSource.visibleScreen, {
        PidKey.vehicleSpeed,
        PidKey.engineRpm,
        PidKey.coolantTemperature,
        PidKey.adapterVoltage,
        PidKey.engineLoad,
        PidKey.throttlePosition,
        PidKey.mafAirFlowRate,
        PidKey.engineFuelRate,
        PidKey.fuelTankLevel,
        PidKey.fuelSystemStatus,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeEngine = context.watch<ThemeEngine?>();
    final colors = themeEngine?.colors ?? const CustomThemeColors();

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header Bar
              CockpitHeaderBar(
                launcherService: _launcherService,
                onOpenSettings: widget.onOpenSettings,
                onOpenConnections: widget.onOpenConnections,
                nowProvider: widget.nowProvider,
                enablePeriodicTimers: widget.enablePeriodicTimers,
              ),

              const SizedBox(height: 10),

              // Center Section: Flight Computer (Flex 6) + Engine Vitals (Flex 4)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: TripFlightComputerCard(
                        nowProvider: widget.nowProvider,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: EngineVitalsCard(
                        onOpenDashboard: widget.onOpenDashboard,
                        onOpenTrips: widget.onOpenTrips,
                        onOpenConnections: widget.onOpenConnections,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Bottom Automotive Launcher Dock
              TactileLauncherDock(
                launcherService: _launcherService,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
