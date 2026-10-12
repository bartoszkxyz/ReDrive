import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/services/settings/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TripProvider Min Trip Distance Threshold', () {
    test('defaults to 10.0 km', () async {
      final provider = TripProvider();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(provider.minTripDistanceKm, 10.0);
      provider.dispose();
    });

    test('updates and persists user configured min trip distance', () async {
      final provider = TripProvider();
      await Future.delayed(const Duration(milliseconds: 50));

      await provider.setMinTripDistanceKm(15.0);
      expect(provider.minTripDistanceKm, 15.0);

      final saved = await AppPreferences.getMinTripDistanceKm();
      expect(saved, 15.0);

      provider.dispose();
    });
  });

  group('TripProvider Direct OBD Stream Binding', () {
    test('bindToObd processes telemetry continuously from ObdProvider', () async {
      final tripProvider = TripProvider();
      final obdProvider = ObdProvider();

      tripProvider.bindToObd(obdProvider);

      expect(tripProvider.activeTrip.isActive, isFalse);

      await obdProvider.startDemoMode();
      await Future.delayed(const Duration(milliseconds: 300));

      expect(tripProvider.activeTrip.isActive, isTrue);
      expect(tripProvider.activeTrip.currentSpeed, greaterThan(0));

      await obdProvider.stopDemoMode();
      tripProvider.dispose();
      obdProvider.dispose();
    });
  });
}
