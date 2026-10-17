import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/providers/trip_provider.dart';

/// Compact, comprehensive Active Trip Tile for the Home screen.
/// Spans full screen width (two tile slots on split-screen), prioritizing
/// Average Fuel and Instant Fuel economy, while displaying complete complimentary trip telemetry.
class ActiveTripTile extends StatelessWidget {
  final ActiveTripState activeTrip;
  final List<Trip> pastTrips;
  final VoidCallback? onEndTrip;
  final VoidCallback? onStartTrip;

  const ActiveTripTile({
    super.key,
    required this.activeTrip,
    required this.pastTrips,
    this.onEndTrip,
    this.onStartTrip,
  });

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isActive = activeTrip.isActive;
    final Trip? lastTrip = pastTrips.firstOrNull;
    final int pCount = isActive ? activeTrip.problemCount : (lastTrip?.problemCount ?? 0);
    final int sCount = isActive ? activeTrip.suspicionCount : (lastTrip?.suspicionCount ?? 0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF141A23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.08),
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 620;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Status, Duration, Action Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: isActive ? colorScheme.primary : Colors.white38,
                            shape: BoxShape.circle,
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: colorScheme.primary.withValues(alpha: 0.6),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isActive ? 'ACTIVE TRIP' : 'CURRENT TRIP',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: isActive ? colorScheme.primary : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? colorScheme.primary.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isActive
                                  ? _formatDuration(activeTrip.duration)
                                  : (lastTrip != null
                                      ? (isCompact ? 'LAST TRIP' : 'STANDBY • LAST TRIP')
                                      : 'STANDBY'),
                              textScaler: TextScaler.noScaling,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive ? colorScheme.primary : Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Quick Action button
                  if (isActive && onEndTrip != null)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onEndTrip,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.stop_rounded, size: 14, color: Colors.redAccent),
                            SizedBox(width: 4),
                            Text(
                              'End Trip',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (!isActive && onStartTrip != null)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onStartTrip,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 14, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Start Trip',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Primary Section: Avg Fuel and Instant Fuel Hero Readouts
              Row(
                children: [
                  Expanded(
                    child: _PrimaryFuelCard(
                      label: 'AVG FUEL',
                      value: isActive
                          ? (activeTrip.distanceKm > 0.05
                              ? activeTrip.avgFuelConsumption.toStringAsFixed(1)
                              : '--')
                          : (lastTrip != null
                              ? lastTrip.avgFuelConsumption.toStringAsFixed(1)
                              : '--'),
                      unit: 'L/100km',
                      sublabel: isActive
                          ? 'Running average'
                          : (lastTrip != null ? 'Last trip avg' : 'Awaiting drive'),
                      accentColor: colorScheme.primary,
                      iconWidget: SvgPicture.asset(
                        'assets/images/svg/dashboard/fuel.svg',
                        width: 15,
                        height: 15,
                        colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PrimaryFuelCard(
                      label: 'INSTANT FUEL',
                      value: isActive
                          ? (activeTrip.currentSpeed > 0
                              ? activeTrip.instantFuelL100km.toStringAsFixed(1)
                              : activeTrip.instantFuelLPerHour.toStringAsFixed(1))
                          : '--',
                      unit: isActive
                          ? (activeTrip.currentSpeed > 0 ? 'L/100km' : 'L/h')
                          : 'L/100km',
                      sublabel: isActive
                          ? (activeTrip.currentSpeed > 0 ? 'Dynamic flow' : 'Idling stationary')
                          : 'Parked / offline',
                      accentColor: Colors.white,
                      iconWidget: const Icon(
                        Icons.speed_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Trip Health Badge
              _TripHealthBadge(
                problemCount: pCount,
                suspicionCount: sCount,
              ),

              const SizedBox(height: 10),
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.07),
              ),
              const SizedBox(height: 10),

              // Complimentary Metrics
              if (isCompact) ...[
                // Split-screen / mobile: 2 rows of 3 columns
                Row(
                  children: [
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'DISTANCE',
                        value: isActive
                            ? activeTrip.distanceKm.toStringAsFixed(2)
                            : (lastTrip?.distanceKm.toStringAsFixed(2) ?? '0.00'),
                        unit: 'km',
                      ),
                    ),
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'FUEL USED',
                        value: isActive
                            ? activeTrip.fuelConsumedLiters.toStringAsFixed(2)
                            : (lastTrip?.fuelConsumedLiters.toStringAsFixed(2) ?? '0.00'),
                        unit: 'L',
                      ),
                    ),
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'DURATION',
                        value: isActive
                            ? _formatDuration(activeTrip.duration)
                            : (lastTrip != null ? _formatDuration(lastTrip.duration) : '--:--'),
                        unit: '',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'CURRENT SPEED',
                        value: isActive ? '${activeTrip.currentSpeed}' : '0',
                        unit: 'km/h',
                      ),
                    ),
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'AVG SPEED',
                        value: isActive
                            ? activeTrip.avgSpeed.toStringAsFixed(0)
                            : (lastTrip?.avgSpeed.toStringAsFixed(0) ?? '--'),
                        unit: 'km/h',
                      ),
                    ),
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'MAX SPEED',
                        value: isActive
                            ? activeTrip.maxSpeed.toStringAsFixed(0)
                            : (lastTrip?.maxSpeed.toStringAsFixed(0) ?? '--'),
                        unit: 'km/h',
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Wide mode: single row of 6 metrics
                Row(
                  children: [
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'DISTANCE',
                        value: isActive
                            ? activeTrip.distanceKm.toStringAsFixed(2)
                            : (lastTrip?.distanceKm.toStringAsFixed(2) ?? '0.00'),
                        unit: 'km',
                      ),
                    ),
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'FUEL USED',
                        value: isActive
                            ? activeTrip.fuelConsumedLiters.toStringAsFixed(2)
                            : (lastTrip?.fuelConsumedLiters.toStringAsFixed(2) ?? '0.00'),
                        unit: 'L',
                      ),
                    ),
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'DURATION',
                        value: isActive
                            ? _formatDuration(activeTrip.duration)
                            : (lastTrip != null ? _formatDuration(lastTrip.duration) : '--:--'),
                        unit: '',
                      ),
                    ),
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'CURRENT SPEED',
                        value: isActive ? '${activeTrip.currentSpeed}' : '0',
                        unit: 'km/h',
                      ),
                    ),
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'AVG SPEED',
                        value: isActive
                            ? activeTrip.avgSpeed.toStringAsFixed(0)
                            : (lastTrip?.avgSpeed.toStringAsFixed(0) ?? '--'),
                        unit: 'km/h',
                      ),
                    ),
                    Expanded(
                      child: _ComplimentaryMetric(
                        label: 'MAX SPEED',
                        value: isActive
                            ? activeTrip.maxSpeed.toStringAsFixed(0)
                            : (lastTrip?.maxSpeed.toStringAsFixed(0) ?? '--'),
                        unit: 'km/h',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PrimaryFuelCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String sublabel;
  final Color accentColor;
  final Widget iconWidget;

  const _PrimaryFuelCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.sublabel,
    required this.accentColor,
    required this.iconWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B222E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              iconWidget,
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  textScaler: TextScaler.noScaling,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 26,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            sublabel,
            textScaler: TextScaler.noScaling,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComplimentaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _ComplimentaryMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          textScaler: TextScaler.noScaling,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.45),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontFamily: 'Inter',
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(
                unit,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _TripHealthBadge extends StatelessWidget {
  final int problemCount;
  final int suspicionCount;

  const _TripHealthBadge({
    required this.problemCount,
    required this.suspicionCount,
  });

  @override
  Widget build(BuildContext context) {
    final bool isClean = problemCount == 0 && suspicionCount == 0;
    final bool isWarning = problemCount == 0 && suspicionCount > 0;

    final Color badgeColor;
    final Color bgColor;
    final IconData icon;

    if (isClean) {
      badgeColor = const Color(0xFF2ECC71);
      bgColor = const Color(0xFF2ECC71).withValues(alpha: 0.12);
      icon = Icons.check_circle_outline_rounded;
    } else if (isWarning) {
      badgeColor = const Color(0xFFF39C12);
      bgColor = const Color(0xFFF39C12).withValues(alpha: 0.12);
      icon = Icons.warning_amber_rounded;
    } else {
      badgeColor = const Color(0xFFE74C3C);
      bgColor = const Color(0xFFE74C3C).withValues(alpha: 0.15);
      icon = Icons.error_outline_rounded;
    }

    final pLabel = problemCount == 1 ? '1 problem' : '$problemCount problems';
    final sLabel = suspicionCount == 1 ? '1 suspicion' : '$suspicionCount suspicions';
    final text = '$pLabel, $sLabel';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: badgeColor.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: badgeColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                textScaler: TextScaler.noScaling,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
