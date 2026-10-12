import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/models/trip.dart';

void main() {
  group('Trip Model', () {
    test('serializes to and from JSON correctly', () {
      final now = DateTime.now();
      final trip = Trip(
        id: '123456',
        startTime: now,
        endTime: now.add(const Duration(minutes: 25)),
        duration: const Duration(minutes: 25),
        distanceKm: 21.5,
        fuelConsumedLiters: 1.45,
        avgFuelConsumption: 6.74,
        avgSpeed: 51.6,
        maxSpeed: 88.0,
        maxRpm: 3200,
        avgRpm: 1950,
      );

      final json = trip.toJson();
      final restored = Trip.fromJson(json);

      expect(restored.id, trip.id);
      expect(restored.distanceKm, trip.distanceKm);
      expect(restored.fuelConsumedLiters, trip.fuelConsumedLiters);
      expect(restored.avgFuelConsumption, trip.avgFuelConsumption);
      expect(restored.avgSpeed, trip.avgSpeed);
      expect(restored.maxSpeed, trip.maxSpeed);
      expect(restored.maxRpm, trip.maxRpm);
      expect(restored.avgRpm, trip.avgRpm);
      expect(restored.duration.inSeconds, trip.duration.inSeconds);
    });
  });
}
