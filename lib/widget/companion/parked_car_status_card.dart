import 'package:flutter/material.dart';
import 'package:obdrive/models/sync_models.dart';

/// Card widget displaying the latest parked vehicle status, including
/// parking GPS coordinates, remaining fuel, estimated range, battery voltage,
/// and odometer reading.
class ParkedCarStatusCard extends StatelessWidget {
  final ParkedCarSnapshot snapshot;
  final VoidCallback? onTap;

  const ParkedCarStatusCard({
    super.key,
    required this.snapshot,
    this.onTap,
  });

  static String _formatTimestamp(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final month = (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $month ${dt.year}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const Key('parked_car_status_card'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Vehicle Icon, Name, and Timestamp
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.directions_car_rounded,
                        color: colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            snapshot.vehicleName,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTimestamp(snapshot.timestamp),
                            key: const Key('parked_car_timestamp'),
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildLocationBadge(colorScheme),
                  ],
                ),
                const SizedBox(height: 16),

                // Metrics Grid: Fuel, Range, Battery, Odometer
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        label: 'Fuel Level',
                        value:
                            '${snapshot.remainingFuelLiters.toStringAsFixed(1)} L (${snapshot.fuelLevelPercent.toStringAsFixed(0)}%)',
                        valueKey: const Key('parked_car_fuel'),
                        icon: Icons.local_gas_station_rounded,
                        iconColor: colorScheme.primary,
                        colorScheme: colorScheme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricTile(
                        label: 'Est. Range',
                        value: '~${snapshot.estimatedRangeKm.toStringAsFixed(0)} km',
                        valueKey: const Key('parked_car_range'),
                        icon: Icons.route_rounded,
                        iconColor: Colors.blueAccent,
                        colorScheme: colorScheme,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        label: 'Battery Voltage',
                        value: '${snapshot.batteryVoltage.toStringAsFixed(2)} V',
                        valueKey: const Key('parked_car_battery'),
                        icon: Icons.battery_charging_full_rounded,
                        iconColor: snapshot.batteryVoltage < 12.0
                            ? Colors.redAccent
                            : Colors.greenAccent,
                        colorScheme: colorScheme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricTile(
                        label: 'Odometer',
                        value: '${snapshot.odometerKm.toStringAsFixed(0)} km',
                        valueKey: const Key('parked_car_odometer'),
                        icon: Icons.speed_rounded,
                        iconColor: Colors.orangeAccent,
                        colorScheme: colorScheme,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationBadge(ColorScheme colorScheme) {
    final hasCoords = snapshot.hasCoordinates;
    final locationText = hasCoords
        ? '${snapshot.latitude!.toStringAsFixed(4)}, ${snapshot.longitude!.toStringAsFixed(4)}'
        : 'Location unavailable';

    return Container(
      key: const Key('parked_car_location_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: hasCoords
            ? Colors.greenAccent.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasCoords
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasCoords ? Icons.location_on_rounded : Icons.location_off_rounded,
            size: 13,
            color: hasCoords ? Colors.greenAccent : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            locationText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color:
                  hasCoords ? Colors.greenAccent : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Key valueKey,
    required IconData icon,
    required Color iconColor,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            key: valueKey,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
