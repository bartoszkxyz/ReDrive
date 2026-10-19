import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/models/sync_models.dart';
import 'package:redrive/services/navigation/map_navigation_service.dart';
import 'package:redrive/widget/companion/parked_car_map_card.dart';
import 'package:url_launcher/url_launcher.dart';

class _MockMapNavigationService extends MapNavigationService {
  int launchCount = 0;
  double? lastLatitude;
  double? lastLongitude;
  String? lastLabel;

  @override
  Future<bool> launchNavigation({
    required double latitude,
    required double longitude,
    String? label,
    Future<bool> Function(Uri uri, {LaunchMode mode})? urlLauncher,
  }) async {
    launchCount++;
    lastLatitude = latitude;
    lastLongitude = longitude;
    lastLabel = label;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedTime = DateTime(2026, 10, 19, 14, 30);

  final testSnapshotWithCoords = ParkedCarSnapshot(
    timestamp: fixedTime,
    vehicleId: 'swift_07',
    vehicleName: 'Suzuki Swift Sport',
    latitude: 42.6977,
    longitude: 23.3219,
    remainingFuelLiters: 35.5,
    fuelLevelPercent: 79.0,
    estimatedRangeKm: 512.0,
    batteryVoltage: 12.6,
    coolantTempC: 86.0,
    odometerKm: 154210.0,
    lastTripId: 'trip_1001',
  );

  final testSnapshotWithoutCoords = ParkedCarSnapshot(
    timestamp: fixedTime,
    vehicleId: 'swift_07',
    vehicleName: 'Suzuki Swift Sport',
    latitude: null,
    longitude: null,
    remainingFuelLiters: 35.5,
    fuelLevelPercent: 79.0,
    estimatedRangeKm: 512.0,
    batteryVoltage: 11.8,
    coolantTempC: 86.0,
    odometerKm: 154210.0,
  );

  Widget buildTestCard({
    required ParkedCarSnapshot snapshot,
    VoidCallback? onRefuelFull,
    MapNavigationService? navigationService,
    VoidCallback? onTap,
  }) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ParkedCarMapCard(
            snapshot: snapshot,
            onRefuelFull: onRefuelFull,
            navigationService: navigationService,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  group('ParkedCarMapCard', () {
    testWidgets('renders vehicle name, battery, odometer, fuel, and navigate button with coordinates',
        (tester) async {
      await tester.pumpWidget(
        buildTestCard(
          snapshot: testSnapshotWithCoords,
          onRefuelFull: () {},
        ),
      );
      await tester.pump();

      // Card root
      expect(find.byKey(const Key('parked_car_map_card')), findsOneWidget);

      // Vehicle header and location badge
      expect(find.text('Suzuki Swift Sport'), findsOneWidget);
      expect(find.byKey(const Key('parked_car_timestamp')), findsOneWidget);
      expect(find.byKey(const Key('parked_car_location_badge')), findsOneWidget);
      expect(find.text('GPS Locked'), findsOneWidget);

      // Embedded Map & Navigate button
      expect(find.byKey(const Key('parked_car_flutter_map')), findsOneWidget);
      expect(find.byKey(const Key('navigate_to_car_button')), findsOneWidget);
      expect(find.text('Navigate to Car'), findsOneWidget);

      // Battery Metric
      expect(find.byKey(const Key('parked_car_battery')), findsOneWidget);
      expect(find.text('12.6 V'), findsOneWidget);
      expect(find.text('Healthy'), findsOneWidget);

      // Odometer Metric
      expect(find.byKey(const Key('parked_car_odometer')), findsOneWidget);
      expect(find.text('154210 km'), findsOneWidget);

      // Fuel & Range Metric
      expect(find.byKey(const Key('parked_car_fuel')), findsOneWidget);
      expect(find.text('35.5 L (79%)'), findsOneWidget);
      expect(find.text('~512 km'), findsOneWidget);
      expect(find.byKey(const Key('quick_refuel_full_button')), findsOneWidget);
      expect(find.text('Full Refill'), findsOneWidget);
    });

    testWidgets('renders "No GPS coordinates" placeholder and hides Navigate button when coordinates are null',
        (tester) async {
      await tester.pumpWidget(
        buildTestCard(
          snapshot: testSnapshotWithoutCoords,
        ),
      );
      await tester.pump();

      // Badge displays No GPS Fix
      expect(find.byKey(const Key('parked_car_location_badge')), findsOneWidget);
      expect(find.text('No GPS Fix'), findsOneWidget);

      // Placeholder rendered, map and navigate button omitted
      expect(
        find.text('No GPS coordinates recorded for this parking spot'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('parked_car_flutter_map')), findsNothing);
      expect(find.byKey(const Key('navigate_to_car_button')), findsNothing);

      // Battery reflects Low status (< 12.0 V)
      expect(find.text('11.8 V'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
    });

    testWidgets('tapping Navigate button calls navigationService.launchNavigation',
        (tester) async {
      final mockNav = _MockMapNavigationService();

      await tester.pumpWidget(
        buildTestCard(
          snapshot: testSnapshotWithCoords,
          navigationService: mockNav,
        ),
      );
      await tester.pump();

      final navButtonFinder = find.byKey(const Key('navigate_to_car_button'));
      expect(navButtonFinder, findsOneWidget);

      await tester.tap(navButtonFinder);
      await tester.pump();

      expect(mockNav.launchCount, 1);
      expect(mockNav.lastLatitude, 42.6977);
      expect(mockNav.lastLongitude, 23.3219);
      expect(mockNav.lastLabel, 'Suzuki Swift Sport');
    });

    testWidgets('tapping "Full Refill" chip triggers onRefuelFull callback',
        (tester) async {
      int refuelTaps = 0;

      await tester.pumpWidget(
        buildTestCard(
          snapshot: testSnapshotWithCoords,
          onRefuelFull: () {
            refuelTaps++;
          },
        ),
      );
      await tester.pump();

      final refuelButtonFinder =
          find.byKey(const Key('quick_refuel_full_button'));
      expect(refuelButtonFinder, findsOneWidget);

      await tester.tap(refuelButtonFinder);
      await tester.pump();

      expect(refuelTaps, 1);
    });

    testWidgets('tapping outer card triggers onTap callback', (tester) async {
      int cardTaps = 0;

      await tester.pumpWidget(
        buildTestCard(
          snapshot: testSnapshotWithCoords,
          onTap: () {
            cardTaps++;
          },
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('parked_car_map_card')));
      await tester.pump();

      expect(cardTaps, 1);
    });

    testWidgets('falls back to "My Vehicle" when vehicleName is empty',
        (tester) async {
      final emptyNameSnapshot = testSnapshotWithCoords.copyWith(vehicleName: '   ');

      await tester.pumpWidget(
        buildTestCard(snapshot: emptyNameSnapshot),
      );
      await tester.pump();

      expect(find.text('My Vehicle'), findsOneWidget);
    });

    testWidgets('hides fuel section when remainingFuelLiters and fuelLevelPercent are 0',
        (tester) async {
      final zeroFuelSnapshot = testSnapshotWithCoords.copyWith(
        remainingFuelLiters: 0,
        fuelLevelPercent: 0,
      );

      await tester.pumpWidget(
        buildTestCard(snapshot: zeroFuelSnapshot),
      );
      await tester.pump();

      expect(find.byKey(const Key('parked_car_fuel')), findsNothing);
      expect(find.byKey(const Key('quick_refuel_full_button')), findsNothing);
      expect(find.byKey(const Key('parked_car_battery')), findsOneWidget);
      expect(find.byKey(const Key('parked_car_odometer')), findsOneWidget);
    });

    test('formatTimestamp formats today, yesterday, relative hours, and dates', () {
      final now = DateTime(2026, 10, 19, 15, 0);

      // Today
      final todayTime = DateTime(2026, 10, 19, 14, 30);
      expect(
        ParkedCarMapCard.formatTimestamp(todayTime, now),
        'Parked today at 14:30',
      );

      // Yesterday
      final yesterdayTime = DateTime(2026, 10, 18, 14, 30);
      expect(
        ParkedCarMapCard.formatTimestamp(yesterdayTime, now),
        'Parked yesterday at 14:30',
      );

      // 2h ago (different day boundary or fallback)
      final pastDate = DateTime(2026, 10, 10, 9, 15);
      expect(
        ParkedCarMapCard.formatTimestamp(pastDate, now),
        'Parked on 10 Oct 2026, 09:15',
      );
    });
  });
}
