import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/models/trip_anomaly.dart';
import 'package:obdrive/models/trip_route_point.dart';
import 'package:obdrive/services/trip/trip_timeseries_service.dart';

/// Telemetry visualization mode for color-coding the route vector polyline.
enum RouteColorMode {
  speed,
  rpm,
  fuel;

  String get label {
    switch (this) {
      case RouteColorMode.speed:
        return 'Speed (km/h)';
      case RouteColorMode.rpm:
        return 'Engine RPM';
      case RouteColorMode.fuel:
        return 'Fuel (L/100km)';
    }
  }
}

/// Resolves segment color based on the selected [RouteColorMode] and point telemetry.
Color getRoutePointColor(TripRoutePoint point, RouteColorMode mode) {
  switch (mode) {
    case RouteColorMode.speed:
      if (point.speedKmh < 30.0) return Colors.cyanAccent;
      if (point.speedKmh <= 80.0) return Colors.greenAccent;
      return Colors.orangeAccent;
    case RouteColorMode.rpm:
      if (point.rpm < 2200) return Colors.cyanAccent;
      if (point.rpm <= 3800) return Colors.greenAccent;
      return Colors.redAccent;
    case RouteColorMode.fuel:
      if (point.fuelL100km < 5.5) return Colors.greenAccent;
      if (point.fuelL100km <= 9.0) return Colors.amberAccent;
      return Colors.redAccent;
  }
}

/// Interactive post-trip route vector inspector widget with timeline scrubbing,
/// color-coded telemetry segments, anomaly pin indicators, and synchronized telemetry readout.
class TripRouteInspector extends StatefulWidget {
  final Trip trip;
  final List<TripTimeseriesSample>? timeseriesSamples;

  const TripRouteInspector({
    super.key,
    required this.trip,
    this.timeseriesSamples,
  });

  @override
  State<TripRouteInspector> createState() => _TripRouteInspectorState();
}

class _TripRouteInspectorState extends State<TripRouteInspector> {
  RouteColorMode _colorMode = RouteColorMode.speed;
  int _scrubberIndex = 0;
  TripAnomalyEpisode? _selectedAnomaly;

  List<TripRoutePoint> get _effectivePoints {
    final samples = widget.timeseriesSamples;
    if (samples != null && samples.isNotEmpty) {
      final validSamples = samples
          .where((s) => s.latitude != null && s.longitude != null)
          .toList();
      if (validSamples.isNotEmpty) {
        return validSamples
            .map(
              (s) => TripRoutePoint(
                latitude: s.latitude!,
                longitude: s.longitude!,
                speedKmh: s.gpsSpeedKmh ?? s.data.speed.toDouble(),
                rpm: s.data.rpm,
                fuelRateLph: s.data.instantFuelLPerHour,
                fuelL100km: s.data.instantFuelL100km,
                engineLoadPercent: s.data.engineLoad,
                coolantTempC: s.data.coolantTemp,
                shortTermFuelTrim: s.data.shortTermFuelTrim,
                longTermFuelTrim: s.data.longTermFuelTrim,
                elapsedSeconds: s.elapsedSeconds,
              ),
            )
            .toList();
      }
    }
    return widget.trip.routePoints;
  }

  void _jumpToAnomaly(TripAnomalyEpisode episode, List<TripRoutePoint> points) {
    if (points.isEmpty) return;
    int bestIdx = 0;
    if (episode.elapsedSeconds != null) {
      double minDiff = double.infinity;
      for (int i = 0; i < points.length; i++) {
        final diff = (points[i].elapsedSeconds - episode.elapsedSeconds!).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestIdx = i;
        }
      }
    } else if (episode.latitude != null && episode.longitude != null) {
      double minDiff = double.infinity;
      for (int i = 0; i < points.length; i++) {
        final dLat = points[i].latitude - episode.latitude!;
        final dLon = points[i].longitude - episode.longitude!;
        final distSq = dLat * dLat + dLon * dLon;
        if (distSq < minDiff) {
          minDiff = distSq;
          bestIdx = i;
        }
      }
    }
    setState(() {
      _selectedAnomaly = episode;
      _scrubberIndex = bestIdx;
    });
  }

  String _formatDuration(double seconds) {
    final totalSec = seconds.round();
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    final h = totalSec ~/ 3600;
    if (h > 0) {
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final points = _effectivePoints;

    if (points.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'No GPS route points recorded for this trip.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
      );
    }

    final safeScrubberIndex = _scrubberIndex.clamp(0, points.length - 1);
    final curPt = points[safeScrubberIndex];
    final totalDuration = points.last.elapsedSeconds > 0
        ? points.last.elapsedSeconds
        : widget.trip.duration.inSeconds.toDouble();
    final maxSlider = (points.length > 1 ? points.length - 1 : 1).toDouble();
    final divisions = points.length > 1 ? points.length - 1 : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Color-Coded Mode Selector
        _buildModeSelector(),
        const SizedBox(height: 12),

        // 2. Route Vector Canvas
        SizedBox(
          height: 220,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CustomPaint(
              key: const Key('trip_route_canvas'),
              painter: _RouteCanvasPainter(
                points: points,
                anomalies: widget.trip.anomalies,
                colorMode: _colorMode,
                scrubberIndex: safeScrubberIndex,
                selectedAnomalyId: _selectedAnomaly?.id,
              ),
            ),
          ),
        ),

        // Clickable Anomaly Pin chips/buttons
        if (widget.trip.anomalies.isNotEmpty) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: widget.trip.anomalies.map((episode) {
                final isSelected = _selectedAnomaly?.id == episode.id;
                final isProblem = episode.severity == AnomalySeverity.problem;
                final accentColor =
                    isProblem ? Colors.redAccent : Colors.amberAccent;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    key: Key('anomaly_pin_${episode.id}'),
                    onTap: () => _jumpToAnomaly(episode, points),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accentColor.withValues(alpha: 0.25)
                            : const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? accentColor
                              : accentColor.withValues(alpha: 0.4),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isProblem
                                ? Icons.error_rounded
                                : Icons.warning_amber_rounded,
                            size: 14,
                            color: accentColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            episode.title,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color:
                                  isSelected ? Colors.white : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        const SizedBox(height: 12),

        // 3. Interactive Timeline Scrubber
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Elapsed: ${_formatDuration(curPt.elapsedSeconds)}',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            Text(
              'Total: ${_formatDuration(totalDuration)}',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.lightBlueAccent,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayColor: Colors.lightBlueAccent.withValues(alpha: 0.2),
            trackHeight: 4,
          ),
          child: Slider(
            key: const Key('trip_route_scrubber_slider'),
            min: 0.0,
            max: maxSlider,
            divisions: divisions,
            value: safeScrubberIndex.toDouble().clamp(0.0, maxSlider),
            onChanged: (val) {
              setState(() {
                _scrubberIndex = val.round().clamp(0, points.length - 1);
              });
            },
          ),
        ),

        const SizedBox(height: 8),

        // 4. Synchronized Telemetry Readout Card
        Container(
          key: const Key('scrubber_telemetry_card'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedAnomaly != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: (_selectedAnomaly!.severity == AnomalySeverity.problem
                            ? Colors.redAccent
                            : Colors.amberAccent)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          _selectedAnomaly!.severity == AnomalySeverity.problem
                              ? Colors.redAccent
                              : Colors.amberAccent,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _selectedAnomaly!.severity == AnomalySeverity.problem
                            ? Icons.error_rounded
                            : Icons.warning_amber_rounded,
                        color: _selectedAnomaly!.severity ==
                                AnomalySeverity.problem
                            ? Colors.redAccent
                            : Colors.amberAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedAnomaly!.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _selectedAnomaly!.severity ==
                                        AnomalySeverity.problem
                                    ? Colors.redAccent
                                    : Colors.amberAccent,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _selectedAnomaly!.description,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white54,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          setState(() => _selectedAnomaly = null);
                        },
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TelemetryMetric(
                    label: 'Speed',
                    value: '${curPt.speedKmh.toStringAsFixed(0)} km/h',
                  ),
                  _TelemetryMetric(
                    label: 'RPM',
                    value: '${curPt.rpm} RPM',
                  ),
                  _TelemetryMetric(
                    label: 'Fuel',
                    value: '${curPt.fuelL100km.toStringAsFixed(1)} L/100km',
                    subValue: '${curPt.fuelRateLph.toStringAsFixed(1)} L/h',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TelemetryMetric(
                    label: 'Load',
                    value: '${curPt.engineLoadPercent.toStringAsFixed(0)}%',
                  ),
                  _TelemetryMetric(
                    label: 'Coolant',
                    value: '${curPt.coolantTempC}°C',
                  ),
                  _TelemetryMetric(
                    label: 'STFT / LTFT',
                    value:
                        '${curPt.shortTermFuelTrim.toStringAsFixed(1)}% / ${curPt.longTermFuelTrim.toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        _buildModeButton(
          RouteColorMode.speed,
          const Key('route_color_mode_speed'),
        ),
        const SizedBox(width: 8),
        _buildModeButton(
          RouteColorMode.rpm,
          const Key('route_color_mode_rpm'),
        ),
        const SizedBox(width: 8),
        _buildModeButton(
          RouteColorMode.fuel,
          const Key('route_color_mode_fuel'),
        ),
      ],
    );
  }

  Widget _buildModeButton(RouteColorMode mode, Key key) {
    final isSelected = _colorMode == mode;
    Color activeColor;
    switch (mode) {
      case RouteColorMode.speed:
        activeColor = Colors.cyanAccent;
        break;
      case RouteColorMode.rpm:
        activeColor = Colors.greenAccent;
        break;
      case RouteColorMode.fuel:
        activeColor = Colors.amberAccent;
        break;
    }
    return Expanded(
      child: InkWell(
        key: key,
        onTap: () {
          setState(() {
            _colorMode = mode;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : Colors.white.withValues(alpha: 0.12),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            mode.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? activeColor : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _TelemetryMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;

  const _TelemetryMetric({
    required this.label,
    required this.value,
    this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (subValue != null)
            Text(
              subValue!,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// Canvas painter drawing vector route polyline, coordinate grid lines, compass badge,
/// start/end pins, anomaly markers, and the glowing interactive scrubber cursor.
class _RouteCanvasPainter extends CustomPainter {
  final List<TripRoutePoint> points;
  final List<TripAnomalyEpisode> anomalies;
  final RouteColorMode colorMode;
  final int scrubberIndex;
  final String? selectedAnomalyId;

  _RouteCanvasPainter({
    required this.points,
    required this.anomalies,
    required this.colorMode,
    required this.scrubberIndex,
    this.selectedAnomalyId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(canvasRect, const Radius.circular(16));

    // Dark automotive vector canvas background
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF0D1117));
    canvas.clipRRect(rrect);

    // Subtle coordinate grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.6)
      ..strokeWidth = 1.0;
    final hStep = size.height / 4.0;
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, i * hStep),
        Offset(size.width, i * hStep),
        gridPaint,
      );
    }
    final wStep = size.width / 5.0;
    for (int i = 1; i < 5; i++) {
      canvas.drawLine(
        Offset(i * wStep, 0),
        Offset(i * wStep, size.height),
        gridPaint,
      );
    }

    // Compass badge ('N') in top-right corner
    _drawCompassBadge(canvas, size);

    if (points.isEmpty) return;

    // Calculate bounding box across points and anomalies with safe auto-scaling
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    for (final a in anomalies) {
      final lat = a.latitude;
      final lon = a.longitude;
      if (lat != null && lon != null) {
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lon < minLon) minLon = lon;
        if (lon > maxLon) maxLon = lon;
      }
    }

    // Safe handling when all lat/lon points are identical or span is minimal
    if ((maxLat - minLat).abs() < 1e-6) {
      minLat -= 0.001;
      maxLat += 0.001;
    }
    if ((maxLon - minLon).abs() < 1e-6) {
      minLon -= 0.001;
      maxLon += 0.001;
    }

    const double padding = 28.0;
    final availW = math.max(10.0, size.width - 2 * padding);
    final availH = math.max(10.0, size.height - 2 * padding);

    final latMean = (minLat + maxLat) / 2.0;
    final lonMean = (minLon + maxLon) / 2.0;
    final cosLat = math.cos(latMean * math.pi / 180.0).abs().clamp(0.2, 1.0);

    final worldW = (maxLon - minLon) * cosLat;
    final worldH = (maxLat - minLat);

    final scale = math.min(availW / worldW, availH / worldH);
    final centerX = size.width / 2.0;
    final centerY = size.height / 2.0;

    Offset toCanvas(double lat, double lon) {
      final x = centerX + ((lon - lonMean) * cosLat) * scale;
      final y = centerY - ((lat - latMean)) * scale;
      return Offset(x, y);
    }

    // Draw route polyline segments
    if (points.length >= 2) {
      for (int i = 0; i < points.length - 1; i++) {
        final p1 = points[i];
        final p2 = points[i + 1];
        final off1 = toCanvas(p1.latitude, p1.longitude);
        final off2 = toCanvas(p2.latitude, p2.longitude);
        final segmentColor = getRoutePointColor(p1, colorMode);

        final segPaint = Paint()
          ..color = segmentColor
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(off1, off2, segPaint);
      }
    }

    // Draw Start Pin (green circle)
    final startPos = toCanvas(points.first.latitude, points.first.longitude);
    canvas.drawCircle(
      startPos,
      6.5,
      Paint()..color = Colors.greenAccent,
    );
    canvas.drawCircle(
      startPos,
      2.5,
      Paint()..color = Colors.white,
    );

    // Draw End Pin (checkered/white circle)
    final endPos = toCanvas(points.last.latitude, points.last.longitude);
    canvas.drawCircle(
      endPos,
      6.5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      endPos,
      3.5,
      Paint()..color = const Color(0xFF0D1117),
    );
    canvas.drawCircle(
      endPos,
      1.5,
      Paint()..color = Colors.white,
    );

    // Draw Anomaly / Power-Loss Pins
    for (final episode in anomalies) {
      double? lat = episode.latitude;
      double? lon = episode.longitude;

      if ((lat == null || lon == null) &&
          episode.elapsedSeconds != null &&
          points.isNotEmpty) {
        TripRoutePoint bestPt = points.first;
        double bestDiff =
            (points.first.elapsedSeconds - episode.elapsedSeconds!).abs();
        for (final pt in points) {
          final diff = (pt.elapsedSeconds - episode.elapsedSeconds!).abs();
          if (diff < bestDiff) {
            bestDiff = diff;
            bestPt = pt;
          }
        }
        lat = bestPt.latitude;
        lon = bestPt.longitude;
      }

      if (lat != null && lon != null) {
        final pos = toCanvas(lat, lon);
        final isProblem = episode.severity == AnomalySeverity.problem;
        final pinColor = isProblem ? Colors.redAccent : Colors.amberAccent;
        final isSelected = selectedAnomalyId == episode.id;

        if (isSelected) {
          canvas.drawCircle(
            pos,
            13,
            Paint()..color = pinColor.withValues(alpha: 0.35),
          );
          canvas.drawCircle(
            pos,
            11,
            Paint()
              ..color = pinColor.withValues(alpha: 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }

        canvas.drawCircle(
          pos,
          7.5,
          Paint()..color = const Color(0xFF0D1117),
        );
        canvas.drawCircle(
          pos,
          6.5,
          Paint()..color = pinColor,
        );
        canvas.drawCircle(
          pos,
          2.5,
          Paint()..color = Colors.white,
        );
      }
    }

    // Draw Interactive Scrubber Cursor
    if (scrubberIndex >= 0 && scrubberIndex < points.length) {
      final curPt = points[scrubberIndex];
      final curPos = toCanvas(curPt.latitude, curPt.longitude);

      canvas.drawCircle(
        curPos,
        14,
        Paint()..color = Colors.white.withValues(alpha: 0.25),
      );
      canvas.drawCircle(
        curPos,
        9,
        Paint()..color = Colors.white.withValues(alpha: 0.5),
      );
      canvas.drawCircle(
        curPos,
        5.5,
        Paint()..color = Colors.white,
      );
    }
  }

  void _drawCompassBadge(Canvas canvas, Size size) {
    final compassCenter = Offset(size.width - 24, 24);
    canvas.drawCircle(
      compassCenter,
      14,
      Paint()..color = const Color(0xFF161B22),
    );
    canvas.drawCircle(
      compassCenter,
      14,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // North arrow triangle
    final arrowPath = Path()
      ..moveTo(compassCenter.dx, compassCenter.dy - 10)
      ..lineTo(compassCenter.dx - 4, compassCenter.dy - 4)
      ..lineTo(compassCenter.dx + 4, compassCenter.dy - 4)
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = Colors.redAccent);

    // Text 'N'
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(compassCenter.dx - textPainter.width / 2, compassCenter.dy - 2),
    );
  }

  @override
  bool shouldRepaint(covariant _RouteCanvasPainter oldDelegate) {
    return oldDelegate.scrubberIndex != scrubberIndex ||
        oldDelegate.colorMode != colorMode ||
        oldDelegate.selectedAnomalyId != selectedAnomalyId ||
        oldDelegate.points != points ||
        oldDelegate.anomalies != anomalies;
  }
}

/// Modal bottom sheet presenting the full [TripRouteInspector].
class TripRouteInspectorSheet extends StatelessWidget {
  final Trip trip;
  final List<TripTimeseriesSample>? timeseriesSamples;

  const TripRouteInspectorSheet({
    super.key,
    required this.trip,
    this.timeseriesSamples,
  });

  /// Displays the route inspector as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required Trip trip,
    List<TripTimeseriesSample>? timeseriesSamples,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => TripRouteInspectorSheet(
        trip: trip,
        timeseriesSamples: timeseriesSamples,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              TripRouteInspector(
                trip: trip,
                timeseriesSamples: timeseriesSamples,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
