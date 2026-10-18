import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/custom_dashboard_theme.dart';
import '../../core/theme/theme_engine.dart';
import '../../providers/trip_provider.dart';
import 'instant_fuel_flow_bar.dart';

/// Flight Computer Cockpit Card displaying real-time trip accumulation statistics,
/// a prominent digital timepiece header, and the instant fuel economy flow bar.
class TripFlightComputerCard extends StatelessWidget {
  final ActiveTripState? activeTrip;
  final DateTime Function()? nowProvider;

  const TripFlightComputerCard({
    super.key,
    this.activeTrip,
    this.nowProvider,
  });

  String _formatDateHeader(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    final weekday = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];
    return '$hour:$minute $period • $weekday, $month ${dt.day}, ${dt.year}';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
      return '$hours:$minutes';
    } else {
      final minutes = d.inMinutes.toString().padLeft(2, '0');
      final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripProvider = context.watch<TripProvider?>();
    final themeEngine = context.watch<ThemeEngine?>();

    final colors = themeEngine?.colors ?? const CustomThemeColors();
    final trip = activeTrip ?? tripProvider?.activeTrip ?? ActiveTripState.initial();

    final now = nowProvider != null ? nowProvider!() : DateTime.now();
    final dateHeader = _formatDateHeader(now);

    return Container(
      key: const Key('trip_flight_computer_card'),
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
          // Top Timepiece Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: colors.background.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: colors.primaryAccent.withValues(alpha: 0.2),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.flight_takeoff_rounded,
                  size: 20,
                  color: colors.primaryAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dateHeader,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.textMain,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: trip.isActive
                        ? colors.primaryAccent.withValues(alpha: 0.15)
                        : colors.textMuted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    trip.isActive ? 'RECORDING' : 'READY',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: trip.isActive ? colors.primaryAccent : colors.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 4-Metric Flight Grid
          Expanded(
            child: Column(
              children: [
                // Row 1: Duration & Distance
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _MetricTile(
                          icon: Icons.timer_outlined,
                          label: 'TRIP DURATION',
                          valueWidget: Text(
                            _formatDuration(trip.duration),
                            key: const Key('flight_trip_duration'),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: colors.textMain,
                            ),
                          ),
                          unit: trip.duration.inHours > 0 ? 'hh:mm' : 'mm:ss',
                          colors: colors,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricTile(
                          icon: Icons.alt_route_rounded,
                          label: 'TRIP DISTANCE',
                          valueWidget: Text(
                            '${trip.distanceKm.toStringAsFixed(1)} km',
                            key: const Key('flight_trip_distance'),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: colors.textMain,
                            ),
                          ),
                          unit: 'Distance',
                          colors: colors,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Row 2: Average Fuel & Total Fuel Used
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _MetricTile(
                          icon: Icons.local_gas_station_outlined,
                          label: 'TRIP AVERAGE',
                          valueWidget: Text(
                            '${trip.avgFuelConsumption.toStringAsFixed(1)} L/100km',
                            key: const Key('flight_trip_avg_fuel'),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: colors.primaryAccent,
                            ),
                          ),
                          unit: 'Average Economy',
                          colors: colors,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricTile(
                          icon: Icons.science_outlined,
                          label: 'TOTAL FUEL USED',
                          valueWidget: Text(
                            '${trip.fuelConsumedLiters.toStringAsFixed(2)} L',
                            key: const Key('flight_trip_fuel_used'),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: colors.textMain,
                            ),
                          ),
                          unit: 'Total Consumed',
                          colors: colors,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Bottom Instant Fuel Flow Bar
          InstantFuelFlowBar(
            instantFuelL100km: trip.instantFuelL100km,
            instantFuelLPerHour: trip.instantFuelLPerHour,
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget valueWidget;
  final String unit;
  final CustomThemeColors colors;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.valueWidget,
    required this.unit,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: colors.textMuted.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: colors.secondaryAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: colors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: valueWidget,
          ),
          Text(
            unit,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: colors.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
