import 'package:redrive/models/trip_route_point.dart';

/// Downsamples high-rate GPS+OBD updates into a permanent lightweight polyline
/// (~1 point every [minIntervalSeconds] or [minDistanceMeters], plus always keeping
/// the first and last point, capped at [maxPoints]).
class RouteDownsampler {
  final double minIntervalSeconds;
  final double minDistanceMeters;
  final int maxPoints;

  final List<TripRoutePoint> _points = [];

  RouteDownsampler({
    this.minIntervalSeconds = 5.0,
    this.minDistanceMeters = 25.0,
    this.maxPoints = 1500,
  });

  /// The list of recorded route points.
  List<TripRoutePoint> get points => List.unmodifiable(_points);

  /// Resets the accumulator for a new trip.
  void reset() {
    _points.clear();
  }

  /// Restores checkpointed route points from disk or state recovery.
  void loadCheckpointPoints(List<TripRoutePoint> savedPoints) {
    _points
      ..clear()
      ..addAll(savedPoints);
    if (_points.length > maxPoints) {
      _decimate();
    }
  }

  /// Appends [candidate] if it satisfies interval or distance thresholds,
  /// or if [force] is true, or if no points have been recorded yet.
  /// If the point count exceeds [maxPoints], evenly decimates intermediate
  /// points while preserving the first and last point.
  bool recordPoint(TripRoutePoint candidate, {bool force = false}) {
    final shouldRecord = force ||
        _points.isEmpty ||
        (candidate.elapsedSeconds - _points.last.elapsedSeconds) >=
            minIntervalSeconds ||
        TripRoutePoint.distanceMeters(
              _points.last.latitude,
              _points.last.longitude,
              candidate.latitude,
              candidate.longitude,
            ) >=
            minDistanceMeters;

    if (!shouldRecord) {
      return false;
    }

    _points.add(candidate);
    if (_points.length > maxPoints) {
      _decimate();
    }
    return true;
  }

  void _decimate() {
    if (_points.length <= maxPoints) return;
    if (maxPoints <= 0) {
      _points.clear();
      return;
    }
    if (maxPoints == 1) {
      final first = _points.first;
      _points
        ..clear()
        ..add(first);
      return;
    }

    final n = _points.length;
    final decimated = <TripRoutePoint>[];
    for (var i = 0; i < maxPoints; i++) {
      final idx = ((i * (n - 1)) / (maxPoints - 1)).round();
      decimated.add(_points[idx]);
    }
    _points
      ..clear()
      ..addAll(decimated);
  }

  /// Downsamples a list of [rawPoints] in batch mode, always preserving
  /// the first and last point, subject to [minIntervalSeconds], [minDistanceMeters],
  /// and [maxPoints].
  static List<TripRoutePoint> downsample(
    List<TripRoutePoint> rawPoints, {
    double minIntervalSeconds = 5.0,
    double minDistanceMeters = 25.0,
    int maxPoints = 1500,
  }) {
    if (rawPoints.isEmpty) return const [];
    if (rawPoints.length == 1) return List.of(rawPoints);

    final downsampler = RouteDownsampler(
      minIntervalSeconds: minIntervalSeconds,
      minDistanceMeters: minDistanceMeters,
      maxPoints: maxPoints,
    );

    for (var i = 0; i < rawPoints.length; i++) {
      final isLast = i == rawPoints.length - 1;
      downsampler.recordPoint(rawPoints[i], force: isLast);
    }

    return downsampler.points;
  }
}
