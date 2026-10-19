import 'package:url_launcher/url_launcher.dart';

/// Service to launch native navigation apps (Google Maps, Apple Maps)
/// or fall back to browser-based walking directions to guide the driver
/// back to their parked vehicle.
class MapNavigationService {
  const MapNavigationService();

  /// Builds a native geo URI for the given coordinates and optional label.
  static Uri buildGeoUri({
    required double latitude,
    required double longitude,
    String? label,
  }) {
    final encodedLabel = Uri.encodeComponent(label ?? 'Parked Car');
    return Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude($encodedLabel)');
  }

  /// Builds a fallback Google Maps walking navigation browser URI.
  static Uri buildFallbackBrowserUri({
    required double latitude,
    required double longitude,
  }) {
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=walking',
    );
  }

  /// Launches navigation to the given [latitude] and [longitude].
  ///
  /// First attempts to open the coordinates using the native `geo:` URI scheme
  /// via [LaunchMode.externalApplication]. If that returns `false` or throws
  /// an exception, it falls back to a web browser walking directions link.
  ///
  /// An optional [urlLauncher] function can be injected for testing.
  /// Returns `true` if either attempt succeeded.
  Future<bool> launchNavigation({
    required double latitude,
    required double longitude,
    String? label,
    Future<bool> Function(Uri uri, {LaunchMode mode})? urlLauncher,
  }) async {
    final launcher = urlLauncher ?? launchUrl;
    final geoUri = buildGeoUri(
      latitude: latitude,
      longitude: longitude,
      label: label,
    );
    final browserUri = buildFallbackBrowserUri(
      latitude: latitude,
      longitude: longitude,
    );

    try {
      final geoSuccess = await launcher(
        geoUri,
        mode: LaunchMode.externalApplication,
      );
      if (geoSuccess) {
        return true;
      }
    } catch (_) {
      // Geo intent not supported or failed; fall through to browser fallback.
    }

    try {
      return await launcher(
        browserUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
