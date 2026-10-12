import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/providers/trip_provider.dart';

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tripProvider = context.watch<TripProvider>();
    final active = tripProvider.activeTrip;
    final pastTrips = tripProvider.pastTrips;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Screen Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trips & Fuel',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSurface,
                              letterSpacing: -0.8,
                            ),
                          ),
                          Text(
                            'HISTORY & LOGS',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      if (pastTrips.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white60),
                          tooltip: 'Clear History',
                          onPressed: () => _confirmClearHistory(context, tripProvider),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Active Trip Card
                  if (active.isActive) ...[
                    _ActiveTripCard(active: active, onEnd: () => tripProvider.manualEndTrip()),
                    const SizedBox(height: 20),
                  ],

                  // Lifetime Statistics Bar
                  _LifetimeStatsCard(
                    totalDistance: tripProvider.totalDistance,
                    totalFuel: tripProvider.totalFuelConsumed,
                    avgFuel: tripProvider.overallAvgFuel,
                    tripsCount: pastTrips.length,
                  ),
                  const SizedBox(height: 24),

                  // Section Title
                  Text(
                    'PAST TRIPS',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                ]),
              ),
            ),

            // Past Trips List or Empty State
            if (pastTrips.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: 64,
                          color: colorScheme.primary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Trips Recorded Yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Connect to your OBD2 adapter or start Demo Mode to automatically record driving trips, distance, and fuel economy.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final trip = pastTrips[index];
                      return _PastTripCard(
                        trip: trip,
                        onDelete: () => tripProvider.deleteTrip(trip.id),
                      );
                    },
                    childCount: pastTrips.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ],
        ),
      ),
    );
  }

  void _confirmClearHistory(BuildContext context, TripProvider provider) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2229),
        title: const Text('Clear All Trips?'),
        content: const Text('This will permanently delete all recorded trip history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              provider.clearHistory();
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _ActiveTripCard extends StatelessWidget {
  final ActiveTripState active;
  final VoidCallback onEnd;

  const _ActiveTripCard({required this.active, required this.onEnd});

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141A23),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ACTIVE TRIP',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                      letterSpacing: 1.2,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Text(
                _formatDuration(active.duration),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'DISTANCE',
                  value: active.distanceKm.toStringAsFixed(2),
                  unit: 'km',
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: _MetricTile(
                  label: 'AVG FUEL',
                  value: active.distanceKm > 0.05
                      ? active.avgFuelConsumption.toStringAsFixed(1)
                      : '--',
                  unit: 'L/100km',
                  color: colorScheme.primary,
                ),
              ),
              Expanded(
                child: _MetricTile(
                  label: 'INSTANT',
                  value: active.currentSpeed > 0
                      ? active.instantFuelL100km.toStringAsFixed(1)
                      : active.instantFuelLPerHour.toStringAsFixed(1),
                  unit: active.currentSpeed > 0 ? 'L/100km' : 'L/h',
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'FUEL USED',
                  value: active.fuelConsumedLiters.toStringAsFixed(2),
                  unit: 'L',
                  color: Colors.white70,
                ),
              ),
              Expanded(
                child: _MetricTile(
                  label: 'AVG SPEED',
                  value: active.avgSpeed.toStringAsFixed(0),
                  unit: 'km/h',
                  color: Colors.white70,
                ),
              ),
              Expanded(
                child: _MetricTile(
                  label: 'MAX SPEED',
                  value: active.maxSpeed.toStringAsFixed(0),
                  unit: 'km/h',
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onEnd,
              child: const Text('Finish & Save Trip'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LifetimeStatsCard extends StatelessWidget {
  final double totalDistance;
  final double totalFuel;
  final double avgFuel;
  final int tripsCount;

  const _LifetimeStatsCard({
    required this.totalDistance,
    required this.totalFuel,
    required this.avgFuel,
    required this.tripsCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatColumn(
            label: 'Total Distance',
            value: '${totalDistance.toStringAsFixed(1)} km',
          ),
          _StatDivider(),
          _StatColumn(
            label: 'Total Fuel',
            value: '${totalFuel.toStringAsFixed(1)} L',
          ),
          _StatDivider(),
          _StatColumn(
            label: 'Avg Economy',
            value: totalDistance > 0 ? '${avgFuel.toStringAsFixed(1)} L/100' : '--',
            highlight: true,
          ),
          _StatDivider(),
          _StatColumn(
            label: 'Trips',
            value: '$tripsCount',
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _StatColumn({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: highlight ? colorScheme.primary : Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      width: 1,
      color: Colors.white.withValues(alpha: 0.1),
    );
  }
}

class _PastTripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onDelete;

  const _PastTripCard({required this.trip, required this.onDelete});

  String _formatDate(DateTime dt) {
    final month = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][dt.month - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $month ${dt.year}, $h:$m';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(trip.startTime),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
              Row(
                children: [
                  Text(
                    _formatDuration(trip.duration),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TripMetric(
                label: 'Distance',
                value: '${trip.distanceKm.toStringAsFixed(2)} km',
              ),
              _TripMetric(
                label: 'Fuel Used',
                value: '${trip.fuelConsumedLiters.toStringAsFixed(2)} L',
              ),
              _TripMetric(
                label: 'Avg Economy',
                value: '${trip.avgFuelConsumption.toStringAsFixed(1)} L/100',
                color: colorScheme.primary,
              ),
              _TripMetric(
                label: 'Max Speed',
                value: '${trip.maxSpeed.toStringAsFixed(0)} km/h',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _TripMetric({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: color ?? Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.5),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              unit,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
