import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:obdrive/models/trip_route_point.dart';

/// Service providing 1 Hz GPS location fixes for active trip route recording
/// and parked-car location snapshots, with deterministic simulated trajectory
/// generation for Demo Mode and offline testing.
class GpsLocationService {
  static const EventChannel _gpsEventChannel =
      EventChannel('com.example.obdrive/gps_stream');

  final StreamController<GpsFix> _fixController =
      StreamController<GpsFix>.broadcast();
  StreamSubscription<dynamic>? _platformSubscription;

  GpsFix? _lastFix;

  // Simulated route state for Demo Mode (curved urban/highway loop)
  double _simLat;
  double _simLon;
  double _simHeadingRad;
  double _simElapsedSec = 0.0;

  GpsLocationService({
    double initialSimLat = 42.6977,
    double initialSimLon = 23.3219,
    double initialHeadingRad = 0.45,
  })  : _simLat = initialSimLat,
        _simLon = initialSimLon,
        _simHeadingRad = initialHeadingRad;

  Stream<GpsFix> get fixStream => _fixController.stream;
  GpsFix? get lastFix => _lastFix;

  /// Starts listening to platform GPS updates if available on the host device.
  void startPlatformListening() {
    if (_platformSubscription != null) return;
    try {
      _platformSubscription =
          _gpsEventChannel.receiveBroadcastStream().listen((dynamic event) {
        if (event is Map) {
          final fix = GpsFix.fromJson(Map<String, dynamic>.from(event));
          injectFix(fix);
        }
      }, onError: (_) {});
    } on MissingPluginException {
      // Safe no-op in unit tests or platforms without native GPS channel.
    } catch (_) {}
  }

  /// Stops listening to platform GPS updates.
  Future<void> stopPlatformListening() async {
    await _platformSubscription?.cancel();
    _platformSubscription = null;
  }

  /// Injects a hardware or test [GpsFix] and broadcasts it to listeners.
  void injectFix(GpsFix fix) {
    _lastFix = fix;
    if (!_fixController.isClosed) {
      _fixController.add(fix);
    }
  }

  /// Resets the simulated trajectory to the starting coordinate.
  void resetSimulation({
    double initialSimLat = 42.6977,
    double initialSimLon = 23.3219,
    double initialHeadingRad = 0.45,
  }) {
    _simLat = initialSimLat;
    _simLon = initialSimLon;
    _simHeadingRad = initialHeadingRad;
    _simElapsedSec = 0.0;
    _lastFix = null;
  }

  /// Advances a realistic curved GPS trajectory based on [speedKmh] and [dtSeconds]
  /// for Demo Mode or synthetic route generation.
  GpsFix advanceSimulatedRoute({
    required double speedKmh,
    required double dtSeconds,
    required DateTime timestamp,
  }) {
    final safeDt = dtSeconds.clamp(0.0, 15.0);
    _simElapsedSec += safeDt;

    final distanceMeters = (speedKmh / 3.6) * safeDt;
    // Gentle sinusoidal heading curve simulating urban turns and highway bends
    _simHeadingRad += math.sin(_simElapsedSec * 0.035) * 0.025 * safeDt;

    const metersPerDegLat = 111320.0;
    final metersPerDegLon =
        111320.0 * math.cos(_simLat * math.pi / 180.0).abs().clamp(0.1, 1.0);

    _simLat += (distanceMeters * math.cos(_simHeadingRad)) / metersPerDegLat;
    _simLon += (distanceMeters * math.sin(_simHeadingRad)) / metersPerDegLon;

    final altitude = 550.0 + 15.0 * math.sin(_simElapsedSec * 0.01);
    final fix = GpsFix(
      latitude: double.parse(_simLat.toStringAsFixed(6)),
      longitude: double.parse(_simLon.toStringAsFixed(6)),
      altitudeMeters: double.parse(altitude.toStringAsFixed(1)),
      speedKmh: speedKmh,
      timestamp: timestamp,
    );
    injectFix(fix);
    return fix;
  }

  void dispose() {
    _platformSubscription?.cancel();
    _fixController.close();
  }
}
