import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:obdrive/models/sync_models.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/models/vehicle_profile.dart';
import 'package:obdrive/providers/garage_provider.dart';
import 'package:obdrive/providers/sync_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/widget/companion/parked_car_map_card.dart';

/// Hero status overview tab for the phone companion application.
/// Displays the parked vehicle's location and vitals, latest drive summary,
/// and upcoming scheduled maintenance notifications.
class CompanionStatusTab extends StatelessWidget {
  final void Function(int tabIndex)? onNavigateTab;

  const CompanionStatusTab({
    super.key,
    this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final garageProvider = context.watch<GarageProvider>();
    final tripProvider = context.watch<TripProvider>();

    final activeProfile = garageProvider.activeProfile;
    final odo = tripProvider.effectiveOdometerKm;
    final latestTrip = tripProvider.pastTrips.firstOrNull;

    final snapshot = syncProvider.latestSnapshot ??
        ParkedCarSnapshot(
          timestamp: DateTime.now(),
          vehicleId: activeProfile.id,
          vehicleName:
              activeProfile.name.isEmpty ? 'My Vehicle' : activeProfile.name,
          odometerKm: odo,
          remainingFuelLiters: activeProfile.virtualTankCurrentLiters ?? 0.0,
          fuelLevelPercent: activeProfile.virtualFuelPercent ?? 0.0,
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            ParkedCarMapCard(
              snapshot: snapshot,
              onRefuelFull: () async {
                await garageProvider.refuelFull();
                final current = syncProvider.latestSnapshot;
                if (current != null) {
                  final active = garageProvider.activeProfile;
                  const nominalEconomy = 6.8;
                  final fullLiters = active.fuelTankCapacityLiters;
                  final updated = current.copyWith(
                    remainingFuelLiters: fullLiters,
                    fuelLevelPercent: 100.0,
                    estimatedRangeKm: fullLiters > 0
                        ? (fullLiters / nominalEconomy) * 100.0
                        : current.estimatedRangeKm,
                  );
                  await syncProvider.syncService.updateParkedSnapshot(updated);
                } else {
                  await syncProvider.captureParkedSnapshot();
                }
              },
            ),
            const SizedBox(height: 16),
            _LatestDriveCard(
              trip: latestTrip,
              onViewTrip: () => onNavigateTab?.call(1),
            ),
            const SizedBox(height: 16),
            _UpcomingServiceBanner(
              activeProfile: activeProfile,
              currentOdometerKm: odo,
              onViewGarage: () => onNavigateTab?.call(2),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _LatestDriveCard extends StatelessWidget {
  final Trip? trip;
  final VoidCallback? onViewTrip;

  const _LatestDriveCard({
    this.trip,
    this.onViewTrip,
  });

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final isToday =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    if (isToday) return 'Today, $h:$m';

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == dt.year &&
        yesterday.month == dt.month &&
        yesterday.day == dt.day;
    if (isYesterday) return 'Yesterday, $h:$m';

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
      'Dec'
    ];
    final month =
        (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : '';
    return '${dt.day} $month, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (trip == null) {
      return Container(
        key: const Key('latest_drive_card'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white10,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.route_rounded,
                color: Colors.white54,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No Trips Recorded Yet',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No trips recorded yet. Complete a drive with OBDrive Headunit to see trip summaries and GPS telemetry here.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final t = trip!;
    final problemCount = t.problemCount;
    final hasProblems = problemCount > 0;

    return Container(
      key: const Key('latest_drive_card'),
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
          onTap: onViewTrip,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.speed_rounded,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text(
                              'Latest Drive',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatRelativeTime(t.startTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _MetricCell(
                      label: 'Distance',
                      value: '${t.distanceKm.toStringAsFixed(1)} km',
                    ),
                    _MetricCell(
                      label: 'Duration',
                      value: '${t.duration.inMinutes} min',
                    ),
                    _MetricCell(
                      label: 'Avg Fuel',
                      value: '${t.avgFuelConsumption.toStringAsFixed(1)} L/100km',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasProblems
                            ? Colors.redAccent.withValues(alpha: 0.15)
                            : Colors.greenAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasProblems
                              ? Colors.redAccent.withValues(alpha: 0.4)
                              : Colors.greenAccent.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasProblems
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 13,
                            color: hasProblems
                                ? Colors.redAccent
                                : Colors.greenAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$problemCount problems',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: hasProblems
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          visualDensity: VisualDensity.compact,
                          foregroundColor: colorScheme.primary,
                        ),
                        onPressed: onViewTrip,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text(
                          'View Trip',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
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
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCell({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingServiceBanner extends StatelessWidget {
  final VehicleProfile activeProfile;
  final double currentOdometerKm;
  final VoidCallback? onViewGarage;

  const _UpcomingServiceBanner({
    required this.activeProfile,
    required this.currentOdometerKm,
    this.onViewGarage,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final overdueItems = activeProfile.maintenanceItems
        .where((i) => i.isOverdue(currentOdometerKm))
        .toList()
      ..sort((a, b) =>
          a.remainingKm(currentOdometerKm).compareTo(b.remainingKm(currentOdometerKm)));

    final dueSoonItems = activeProfile.maintenanceItems
        .where((i) => i.isDueSoon(currentOdometerKm))
        .toList()
      ..sort((a, b) =>
          a.remainingKm(currentOdometerKm).compareTo(b.remainingKm(currentOdometerKm)));

    final hasOverdue = overdueItems.isNotEmpty;
    final hasDueSoon = dueSoonItems.isNotEmpty;

    if (!hasOverdue && !hasDueSoon) {
      return Container(
        key: const Key('upcoming_service_banner'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.greenAccent.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: Colors.greenAccent,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'All scheduled maintenance up to date',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.greenAccent,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final MaintenanceItem urgentItem =
        hasOverdue ? overdueItems.first : dueSoonItems.first;
    final remKm = urgentItem.remainingKm(currentOdometerKm);
    final accentColor = hasOverdue ? Colors.redAccent : Colors.orangeAccent;
    final distanceText = hasOverdue
        ? 'Overdue by ${remKm.abs().toStringAsFixed(0)} km'
        : 'Due in ${remKm.toStringAsFixed(0)} km';

    return Container(
      key: const Key('upcoming_service_banner'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onViewGarage,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasOverdue
                        ? Icons.warning_amber_rounded
                        : Icons.build_circle_outlined,
                    color: accentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        urgentItem.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        distanceText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor.withValues(alpha: 0.2),
                    foregroundColor: accentColor,
                    elevation: 0,
                    side: BorderSide(
                      color: accentColor.withValues(alpha: 0.5),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onViewGarage,
                  child: const Text(
                    'View Garage',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
