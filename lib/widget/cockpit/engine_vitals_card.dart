import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/custom_dashboard_theme.dart';
import '../../core/theme/theme_engine.dart';
import '../../providers/obd_provider.dart';
import '../../screens/dashboard_screen.dart';
import '../../screens/trips_screen.dart';

/// Vital Engine Health & OBDrive Portal Card for the TS18 cockpit launcher.
/// Displays Coolant Temperature, Engine Load percentage, and shortcuts to Dashboard and Trips.
class EngineVitalsCard extends StatelessWidget {
  final int? coolantTemp;
  final double? engineLoad;
  final VoidCallback? onOpenDashboard;
  final VoidCallback? onOpenTrips;
  final VoidCallback? onOpenConnections;

  const EngineVitalsCard({
    super.key,
    this.coolantTemp,
    this.engineLoad,
    this.onOpenDashboard,
    this.onOpenTrips,
    this.onOpenConnections,
  });

  ({String label, Color color}) _getCoolantStatus(int temp, CustomThemeColors colors) {
    if (temp < 70) {
      return (label: 'Warming Up', color: colors.secondaryAccent);
    } else if (temp <= 96) {
      return (label: 'Optimal Working Zone', color: colors.coolantNormal);
    } else if (temp <= 101) {
      return (label: 'Elevated Temp', color: colors.coolantWarning);
    } else {
      return (label: 'OVERHEAT ALERT', color: colors.coolantOverheat);
    }
  }

  ({String label, Color color}) _getLoadStatus(double load, CustomThemeColors colors) {
    if (load < 30.0) {
      return (label: 'Idle / Decel', color: colors.engineLoadLow);
    } else if (load <= 65.0) {
      return (label: 'Cruising / Closed Loop', color: colors.engineLoadMedium);
    } else {
      return (label: 'High Acceleration / Power', color: colors.engineLoadHigh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final obdProvider = context.watch<ObdProvider?>();
    final themeEngine = context.watch<ThemeEngine?>();

    final colors = themeEngine?.colors ?? const CustomThemeColors();
    final effectiveTemp = coolantTemp ?? obdProvider?.data.coolantTemp ?? 0;
    final effectiveLoad = engineLoad ?? obdProvider?.data.engineLoad ?? 0.0;

    final coolantStatus = _getCoolantStatus(effectiveTemp, colors);
    final loadStatus = _getLoadStatus(effectiveLoad, colors);

    return Container(
      key: const Key('engine_vitals_card'),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: colors.textMuted.withValues(alpha: 0.15),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sub-card 1: Coolant Temperature
          Expanded(
            flex: 4,
            child: Container(
              key: const Key('cockpit_coolant_card'),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: colors.background.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: effectiveTemp >= 102
                      ? colors.coolantOverheat.withValues(alpha: 0.6)
                      : colors.textMuted.withValues(alpha: 0.12),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: coolantStatus.color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.thermostat_rounded,
                      size: 20,
                      color: coolantStatus.color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'COOLANT TEMPERATURE',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '$effectiveTemp °C',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: colors.textMain,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: coolantStatus.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: coolantStatus.color.withValues(alpha: 0.5),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                coolantStatus.label,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: coolantStatus.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Sub-card 2: Engine Load
          Expanded(
            flex: 4,
            child: Container(
              key: const Key('cockpit_engine_load_card'),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: colors.background.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: colors.textMuted.withValues(alpha: 0.12),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: loadStatus.color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: loadStatus.color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'ENGINE LOAD',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '${effectiveLoad.toStringAsFixed(0)} %',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: colors.textMain,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: loadStatus.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: loadStatus.color.withValues(alpha: 0.5),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                loadStatus.label,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: loadStatus.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Sub-card 3: OBDrive Portal
          Expanded(
            flex: 4,
            child: Container(
              key: const Key('cockpit_obdrive_portal'),
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: colors.background.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: colors.primaryAccent.withValues(alpha: 0.2),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const Key('open_full_dashboard_button'),
                        onTap: () {
                          if (onOpenDashboard != null) {
                            onOpenDashboard!();
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DashboardScreen(),
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.primaryAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colors.primaryAccent.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bar_chart_rounded,
                                size: 18,
                                color: colors.primaryAccent,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Full Dashboard',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textMain,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const Key('open_trip_history_button'),
                        onTap: () {
                          if (onOpenTrips != null) {
                            onOpenTrips!();
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TripsScreen(),
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.secondaryAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colors.secondaryAccent.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: 18,
                                color: colors.secondaryAccent,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Trip History',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textMain,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const Key('open_connections_button'),
                        onTap: onOpenConnections,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF00E676).withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.settings_input_component_rounded,
                                size: 18,
                                color: Color(0xFF00E676),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Connections',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textMain,
                                ),
                              ),
                            ],
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
    );
  }
}
