import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/screens/home_screen.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/widget/home_screen/active_trip_tile.dart';
import 'package:redrive/widget/home_screen/engine_temp_card.dart';
import 'package:redrive/widget/home_screen/fuel_load_card.dart';

void main() {
  group('EngineTempCard', () {
    testWidgets('shows WARMING UP for cold coolant (< 50°C)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EngineTempCard(
              coolantTemp: 35,
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ENGINE TEMP'), findsOneWidget);
      expect(find.text('WARMING UP'), findsOneWidget);
      expect(find.text('35'), findsOneWidget);
      expect(find.text('Engine cold • Keep revs low'), findsOneWidget);
    });

    testWidgets('shows READY TO DRIVE for optimal coolant (75°C - 98°C)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EngineTempCard(
              coolantTemp: 88,
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('READY TO DRIVE'), findsOneWidget);
      expect(find.text('88'), findsOneWidget);
      expect(find.text('Optimal operating temp • Ready to drive'), findsOneWidget);
    });

    testWidgets('shows OVERHEATING for high coolant (> 108°C)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EngineTempCard(
              coolantTemp: 112,
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('OVERHEATING'), findsOneWidget);
      expect(find.text('112'), findsOneWidget);
      expect(find.text('Overheating alert! Stop safely'), findsOneWidget);
    });

    testWidgets('shows STANDBY and dashes when offline', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EngineTempCard(
              coolantTemp: 0,
              isConnected: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('STANDBY'), findsOneWidget);
      expect(find.text('--'), findsOneWidget);
    });
  });

  group('EngineLoadCard', () {
    testWidgets('shows LIGHT for low load (< 20%)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EngineLoadCard(
              load: 14.5,
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ENGINE LOAD'), findsOneWidget);
      expect(find.text('LIGHT'), findsOneWidget);
      expect(find.text('14.5'), findsOneWidget);
      expect(find.text('Low demand • Coasting / Idle'), findsOneWidget);
    });

    testWidgets('shows EFFICIENT for eco range (20% - 55%)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EngineLoadCard(
              load: 38.2,
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('EFFICIENT'), findsOneWidget);
      expect(find.text('38.2'), findsOneWidget);
      expect(find.text('Optimal eco range • Peak efficiency'), findsOneWidget);
    });

    testWidgets('shows MODERATE for acceleration load (55% - 75%)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EngineLoadCard(
              load: 64.0,
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MODERATE'), findsOneWidget);
      expect(find.text('64.0'), findsOneWidget);
      expect(find.text('Moderate load • Normal acceleration'), findsOneWidget);
    });

    testWidgets('shows INEFFICIENT for heavy fuel demand load (> 75%)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EngineLoadCard(
              load: 85.0,
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('INEFFICIENT'), findsOneWidget);
      expect(find.text('85.0'), findsOneWidget);
      expect(find.text('Heavy engine load • Inefficient'), findsOneWidget);
    });

    testWidgets('shows STANDBY and dashes when offline', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EngineLoadCard(
              load: 0.0,
              isConnected: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('STANDBY'), findsOneWidget);
      expect(find.text('--'), findsOneWidget);
    });
  });

  group('ActiveTripTile', () {
    testWidgets('displays active trip metrics with Avg Fuel and Instant Fuel', (tester) async {
      final activeTrip = ActiveTripState(
        isActive: true,
        startTime: DateTime.now().subtract(const Duration(minutes: 15)),
        duration: const Duration(minutes: 15, seconds: 30),
        distanceKm: 12.4,
        fuelConsumedLiters: 0.88,
        avgFuelConsumption: 7.1,
        instantFuelL100km: 6.4,
        instantFuelLPerHour: 0.8,
        avgSpeed: 48.0,
        maxSpeed: 82.0,
        maxRpm: 3200,
        currentSpeed: 55,
        currentRpm: 2100,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveTripTile(
              activeTrip: activeTrip,
              pastTrips: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ACTIVE TRIP'), findsOneWidget);
      expect(find.text('AVG FUEL'), findsOneWidget);
      expect(find.text('7.1'), findsOneWidget);
      expect(find.text('INSTANT FUEL'), findsOneWidget);
      expect(find.text('6.4'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('12.40'), findsOneWidget);
      expect(find.text('FUEL USED'), findsOneWidget);
      expect(find.text('0.88'), findsOneWidget);
      expect(find.text('CURRENT SPEED'), findsOneWidget);
      expect(find.text('55'), findsOneWidget);
      expect(find.text('AVG SPEED'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(find.text('MAX SPEED'), findsOneWidget);
      expect(find.text('82'), findsOneWidget);
    });

    testWidgets('displays standby state and previous trip data when idle', (tester) async {
      final pastTrip = Trip(
        id: 'trip-1',
        startTime: DateTime.now().subtract(const Duration(hours: 2)),
        endTime: DateTime.now().subtract(const Duration(hours: 1)),
        duration: const Duration(minutes: 42),
        distanceKm: 28.5,
        fuelConsumedLiters: 1.95,
        avgFuelConsumption: 6.8,
        avgSpeed: 52.0,
        maxSpeed: 96.0,
        maxRpm: 3400,
        avgRpm: 2200,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveTripTile(
              activeTrip: ActiveTripState.initial(),
              pastTrips: [pastTrip],
              onStartTrip: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CURRENT TRIP'), findsOneWidget);
      expect(find.text('STANDBY • LAST TRIP'), findsOneWidget);
      expect(find.text('6.8'), findsOneWidget);
      expect(find.text('28.50'), findsOneWidget);
      expect(find.text('Start Trip'), findsOneWidget);
    });
  });

  group('HomeScreen Layout Tests', () {
    late ObdProvider obdProvider;
    late TripProvider tripProvider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      obdProvider = ObdProvider();
      tripProvider = TripProvider();
    });

    tearDown(() {
      obdProvider.dispose();
      tripProvider.dispose();
    });

    Widget createHomeScreen() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ObdProvider>.value(value: obdProvider),
          ChangeNotifierProvider<TripProvider>.value(value: tripProvider),
        ],
        child: const MaterialApp(
          localizationsDelegates: [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      );
    }

    testWidgets('renders split-screen layout (< 850px) without overflow', (tester) async {
      tester.view.physicalSize = const Size(450, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byType(EngineTempCard), findsOneWidget);
      expect(find.byType(EngineLoadCard), findsOneWidget);
      expect(find.byType(ActiveTripTile), findsOneWidget);
      expect(find.text('ENGINE TEMP'), findsOneWidget);
      expect(find.text('ENGINE LOAD'), findsOneWidget);
      expect(find.text('CURRENT TRIP'), findsOneWidget);
      expect(find.text('AVG FUEL'), findsOneWidget);
      expect(find.text('INSTANT FUEL'), findsOneWidget);
    });

    testWidgets('renders wide headunit layout (>= 850px) without overflow', (tester) async {
      tester.view.physicalSize = const Size(1024, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byType(EngineTempCard), findsOneWidget);
      expect(find.byType(EngineLoadCard), findsOneWidget);
      expect(find.byType(ActiveTripTile), findsOneWidget);
      expect(find.text('Suzuki Swift M15A (1.5L)'), findsOneWidget);
      expect(find.text('OBD-II ADAPTER'), findsOneWidget);
    });
  });
}
