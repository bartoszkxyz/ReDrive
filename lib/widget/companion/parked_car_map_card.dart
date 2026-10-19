import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:redrive/models/sync_models.dart';
import 'package:redrive/services/navigation/map_navigation_service.dart';

/// Card widget displaying the latest parked vehicle status with an embedded
/// OpenStreetMap tile snippet, GPS coordinates lock status, quick navigation
/// launcher, battery health, odometer, and fuel metrics.
class ParkedCarMapCard extends StatelessWidget {
  final ParkedCarSnapshot snapshot;
  final VoidCallback? onRefuelFull;
  final MapNavigationService? navigationService;
  final VoidCallback? onTap;

  const ParkedCarMapCard({
    super.key,
    required this.snapshot,
    this.onRefuelFull,
    this.navigationService,
    this.onTap,
  });

  /// Formats the parked timestamp into a human-friendly string (e.g.
  /// 'Parked today at 14:30', 'Parked yesterday at 14:30', or 'Parked 2h ago').
  static String formatTimestamp(DateTime dt, [DateTime? currentNow]) {
    final now = currentNow ?? DateTime.now();
    final difference = now.difference(dt);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');

    final isToday =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    if (isToday) {
      return 'Parked today at $h:$m';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == dt.year &&
        yesterday.month == dt.month &&
        yesterday.day == dt.day;
    if (isYesterday) {
      return 'Parked yesterday at $h:$m';
    }

    if (!difference.isNegative && difference.inHours < 24 && difference.inHours >= 1) {
      return 'Parked ${difference.inHours}h ago';
    }

    const months = [
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
      'Dec',
    ];
    final month =
        (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : '';
    return 'Parked on ${dt.day} $month ${dt.year}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const Key('parked_car_map_card'),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(colorScheme),
                const SizedBox(height: 12),
                _buildMapSection(context, colorScheme),
                const SizedBox(height: 12),
                _buildMetricsSection(colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    final vehicleName =
        snapshot.vehicleName.trim().isEmpty ? 'My Vehicle' : snapshot.vehicleName;

    return Row(
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
                vehicleName,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatTimestamp(snapshot.timestamp),
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
    );
  }

  Widget _buildLocationBadge(ColorScheme colorScheme) {
    final hasCoords = snapshot.hasCoordinates;
    final badgeText = hasCoords ? 'GPS Locked' : 'No GPS Fix';
    final badgeColor =
        hasCoords ? Colors.greenAccent : colorScheme.onSurfaceVariant;

    return Container(
      key: const Key('parked_car_location_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasCoords ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
            size: 13,
            color: badgeColor,
          ),
          const SizedBox(width: 4),
          Text(
            badgeText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection(BuildContext context, ColorScheme colorScheme) {
    if (snapshot.hasCoordinates) {
      final point = LatLng(snapshot.latitude!, snapshot.longitude!);

      return SizedBox(
        height: 180,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              IgnorePointer(
                child: FlutterMap(
                  key: const Key('parked_car_flutter_map'),
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 16.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.redrive',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 44,
                          height: 44,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.primary,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      colorScheme.primary.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                Icons.directions_car_rounded,
                                size: 22,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: _buildNavigateButton(colorScheme),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off_rounded,
              size: 32,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              'No GPS coordinates recorded for this parking spot',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigateButton(ColorScheme colorScheme) {
    return FilledButton.icon(
      key: const Key('navigate_to_car_button'),
      onPressed: () {
        final service = navigationService ?? const MapNavigationService();
        service.launchNavigation(
          latitude: snapshot.latitude!,
          longitude: snapshot.longitude!,
          label: snapshot.vehicleName.trim().isNotEmpty
              ? snapshot.vehicleName
              : 'Parked Car',
        );
      },
      icon: const Icon(Icons.navigation_rounded, size: 16),
      label: const Text(
        'Navigate to Car',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.surface.withValues(alpha: 0.9),
        foregroundColor: colorScheme.primary,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsSection(ColorScheme colorScheme) {
    final hasFuel =
        snapshot.remainingFuelLiters > 0 || snapshot.fuelLevelPercent > 0;

    return Column(
      children: [
        if (hasFuel) ...[
          _buildFuelTile(colorScheme),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(child: _buildBatteryTile(colorScheme)),
            const SizedBox(width: 10),
            Expanded(child: _buildOdometerTile(colorScheme)),
          ],
        ),
      ],
    );
  }

  Widget _buildFuelTile(ColorScheme colorScheme) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_gas_station_rounded,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Fuel & Range',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (onRefuelFull != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const Key('quick_refuel_full_button'),
                    onTap: onRefuelFull,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_gas_station_rounded,
                            size: 11,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Full Refill',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${snapshot.remainingFuelLiters.toStringAsFixed(1)} L (${snapshot.fuelLevelPercent.toStringAsFixed(0)}%)',
                key: const Key('parked_car_fuel'),
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '~${snapshot.estimatedRangeKm.toStringAsFixed(0)} km',
                key: const Key('parked_car_range'),
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryTile(ColorScheme colorScheme) {
    final isHealthy = snapshot.batteryVoltage >= 12.0;
    final statusLabel = isHealthy ? 'Healthy' : 'Low';

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
              Icon(
                Icons.battery_charging_full_rounded,
                size: 14,
                color: isHealthy ? Colors.greenAccent : Colors.redAccent,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Battery Voltage',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(
                  '${snapshot.batteryVoltage.toStringAsFixed(1)} V',
                  key: const Key('parked_car_battery'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isHealthy ? Colors.greenAccent : Colors.redAccent)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: isHealthy ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOdometerTile(ColorScheme colorScheme) {
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
              Icon(
                Icons.speed_rounded,
                size: 14,
                color: Colors.orangeAccent,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Odometer',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${snapshot.odometerKm.toStringAsFixed(0)} km',
            key: const Key('parked_car_odometer'),
            overflow: TextOverflow.ellipsis,
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
