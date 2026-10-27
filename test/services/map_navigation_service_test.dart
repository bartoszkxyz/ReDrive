import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/services/navigation/map_navigation_service.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  group('MapNavigationService URI builders', () {
    test('buildGeoUri encodes coordinates and default label', () {
      final uri = MapNavigationService.buildGeoUri(
        latitude: 42.6977,
        longitude: 23.3219,
      );

      expect(uri.scheme, 'geo');
      expect(
        uri.toString(),
        'geo:42.6977,23.3219?q=42.6977,23.3219(Parked%20Car)',
      );
    });

    test('buildGeoUri encodes custom vehicle label', () {
      final uri = MapNavigationService.buildGeoUri(
        latitude: 37.7749,
        longitude: -122.4194,
        label: 'My Suzuki Swift',
      );

      expect(
        uri.toString(),
        'geo:37.7749,-122.4194?q=37.7749,-122.4194(My%20Suzuki%20Swift)',
      );
    });

    test('buildFallbackBrowserUri generates walking navigation link', () {
      final uri = MapNavigationService.buildFallbackBrowserUri(
        latitude: 42.6977,
        longitude: 23.3219,
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['destination'], '42.6977,23.3219');
      expect(uri.queryParameters['travelmode'], 'walking');
    });
  });

  group('MapNavigationService launchNavigation', () {
    const service = MapNavigationService();

    test('returns true when geo URI succeeds without calling fallback', () async {
      final launchedUris = <Uri>[];
      final launchModes = <LaunchMode>[];

      final success = await service.launchNavigation(
        latitude: 42.6977,
        longitude: 23.3219,
        label: 'Swift GT',
        urlLauncher: (uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
          launchedUris.add(uri);
          launchModes.add(mode);
          return true;
        },
      );

      expect(success, isTrue);
      expect(launchedUris.length, 1);
      expect(launchedUris.first.scheme, 'geo');
      expect(
        launchedUris.first.toString(),
        contains('geo:42.6977,23.3219?q=42.6977,23.3219(Swift%20GT)'),
      );
      expect(launchModes.first, LaunchMode.externalApplication);
    });

    test('falls back to browser walking URL when geo URI returns false', () async {
      final launchedUris = <Uri>[];
      final launchModes = <LaunchMode>[];

      final success = await service.launchNavigation(
        latitude: 42.6977,
        longitude: 23.3219,
        urlLauncher: (uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
          launchedUris.add(uri);
          launchModes.add(mode);
          if (uri.scheme == 'geo') {
            return false;
          }
          return true;
        },
      );

      expect(success, isTrue);
      expect(launchedUris.length, 2);
      expect(launchedUris[0].scheme, 'geo');
      expect(launchedUris[1].scheme, 'https');
      expect(launchedUris[1].host, 'www.google.com');
      expect(launchModes[0], LaunchMode.externalApplication);
      expect(launchModes[1], LaunchMode.externalApplication);
    });

    test('falls back to browser walking URL when geo URI throws exception', () async {
      final launchedUris = <Uri>[];

      final success = await service.launchNavigation(
        latitude: 42.6977,
        longitude: 23.3219,
        urlLauncher: (uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
          launchedUris.add(uri);
          if (uri.scheme == 'geo') {
            throw Exception('PlatformActivityNotFoundException: No activity found to handle geo intent');
          }
          return true;
        },
      );

      expect(success, isTrue);
      expect(launchedUris.length, 2);
      expect(launchedUris[1].scheme, 'https');
    });

    test('returns false when both geo URI and browser fallback fail', () async {
      final launchedUris = <Uri>[];

      final success = await service.launchNavigation(
        latitude: 42.6977,
        longitude: 23.3219,
        urlLauncher: (uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
          launchedUris.add(uri);
          return false;
        },
      );

      expect(success, isFalse);
      expect(launchedUris.length, 2);
    });

    test('returns false when both geo URI and browser fallback throw', () async {
      final success = await service.launchNavigation(
        latitude: 42.6977,
        longitude: 23.3219,
        urlLauncher: (uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
          throw Exception('Unable to open URL');
        },
      );

      expect(success, isFalse);
    });
  });
}
