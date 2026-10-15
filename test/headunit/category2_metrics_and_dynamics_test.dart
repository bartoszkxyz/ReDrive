import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/screens/dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Category 2 & Zero-Overhead Telemetry — Unit Tests', () {
    test('FuelSystemStatus enum mapping and properties', () {
      expect(FuelSystemStatus.fromNumeric(1), FuelSystemStatus.openLoopWarmup);
      expect(FuelSystemStatus.fromNumeric(1).label, 'Open Loop (Cold Warmup)');
      expect(FuelSystemStatus.fromNumeric(1).shortCode, 'OL-Warm');
      expect(FuelSystemStatus.fromNumeric(1).isClosedLoop, isFalse);

      expect(FuelSystemStatus.fromNumeric(2), FuelSystemStatus.closedLoop);
      expect(FuelSystemStatus.fromNumeric(2).label, 'Closed Loop (O2 Feedback)');
      expect(FuelSystemStatus.fromNumeric(2).shortCode, 'CL');
      expect(FuelSystemStatus.fromNumeric(2).isClosedLoop, isTrue);

      expect(FuelSystemStatus.fromNumeric(4), FuelSystemStatus.openLoopLoadOrDecel);
      expect(FuelSystemStatus.fromNumeric(4).label, 'Open Loop (Power / Decel)');
      expect(FuelSystemStatus.fromNumeric(4).shortCode, 'OL-Drive');
      expect(FuelSystemStatus.fromNumeric(4).isClosedLoop, isFalse);

      expect(FuelSystemStatus.fromNumeric(8), FuelSystemStatus.openLoopFault);
      expect(FuelSystemStatus.fromNumeric(8).label, 'Open Loop (System Fault)');
      expect(FuelSystemStatus.fromNumeric(8).isClosedLoop, isFalse);

      expect(FuelSystemStatus.fromNumeric(16), FuelSystemStatus.closedLoopFault);
      expect(FuelSystemStatus.fromNumeric(16).label, 'Closed Loop (Feedback Fault)');
      expect(FuelSystemStatus.fromNumeric(16).isClosedLoop, isTrue);

      expect(FuelSystemStatus.fromNumeric(99), FuelSystemStatus.unknown);
      expect(FuelSystemStatus.fromNumeric(99).shortCode, '--');
    });

    test('ObdData fuel tank and DTE calculations for Suzuki Swift 45L tank', () {
      double calcRemainingLiters(double percent) => (percent * 45.0) / 100.0;
      double calcDteKm(double remainingLiters) =>
          remainingLiters <= 0.0 ? 0.0 : (remainingLiters / 6.8) * 100.0;

      final fullLiters = calcRemainingLiters(100.0);
      final fullDte = calcDteKm(fullLiters);
      final dataFull = ObdData(
        fuelLevelPercent: 100.0,
        remainingFuelLiters: fullLiters,
        estimatedRangeKm: fullDte,
      );
      expect(dataFull.remainingFuelLiters, 45.0);
      expect(dataFull.estimatedRangeKm, closeTo(661.76, 0.1));

      final halfLiters = calcRemainingLiters(50.0);
      final halfDte = calcDteKm(halfLiters);
      final dataHalf = ObdData(
        fuelLevelPercent: 50.0,
        remainingFuelLiters: halfLiters,
        estimatedRangeKm: halfDte,
      );
      expect(dataHalf.remainingFuelLiters, 22.5);
      expect(dataHalf.estimatedRangeKm, closeTo(330.88, 0.1));

      final emptyLiters = calcRemainingLiters(0.0);
      final emptyDte = calcDteKm(emptyLiters);
      final dataEmpty = ObdData(
        fuelLevelPercent: 0.0,
        remainingFuelLiters: emptyLiters,
        estimatedRangeKm: emptyDte,
      );
      expect(dataEmpty.remainingFuelLiters, 0.0);
      expect(dataEmpty.estimatedRangeKm, 0.0);
    });

    test('ObdData horsepower and torque mathematical models for M15A', () {
      // MAF = 40.0 g/s -> HP = 40 * 1.25 = 50.0 HP
      // RPM = 3000 -> Torque = (50.0 * 7127) / 3000 = 118.78 N·m
      const hp = 40.0 * 1.25;
      const torque = (hp * 7127.0) / 3000.0;
      const data = ObdData(
        rpm: 3000,
        maf: 40.0,
        horsepower: hp,
        torqueNm: torque,
      );

      expect(data.horsepower, 50.0);
      expect(data.torqueNm, closeTo(118.78, 0.1));
    });

    test('ObdData relative throttle normalizes idle rest (13%) to 0%', () {
      // Idle rest: 13.0% -> relativeThrottle should be 0.0%
      const idleData = ObdData(throttlePosition: 13.0, relativeThrottle: 0.0);
      expect(idleData.relativeThrottle, 0.0);

      // Half throttle: ~49.0% -> relativeThrottle should be ~50.0%
      const midData = ObdData(throttlePosition: 49.0, relativeThrottle: 50.0);
      expect(midData.relativeThrottle, 50.0);

      // WOT: 85.0% -> relativeThrottle should be 100.0%
      const wotData = ObdData(throttlePosition: 85.0, relativeThrottle: 100.0);
      expect(wotData.relativeThrottle, 100.0);
    });
  });

  group('Category 2 & Zero-Overhead Telemetry — ObdProvider Demo Mode', () {
    late ObdProvider obdProvider;

    setUp(() {
      obdProvider = ObdProvider();
    });

    tearDown(() {
      obdProvider.dispose();
    });

    test('startDemoMode sets realistic Category 2 and dynamic values', () async {
      obdProvider.startDemoMode();
      expect(obdProvider.mode, ObdMode.demo);

      // Wait a short moment for the first demo frame to tick
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final data = obdProvider.data;
      expect(data.fuelLevelPercent, greaterThan(0.0));
      expect(data.remainingFuelLiters, greaterThan(0.0));
      expect(data.estimatedRangeKm, greaterThan(0.0));
      expect(data.manifoldPressure, greaterThan(0.0));
      expect(data.timingAdvance, greaterThan(0.0));
      expect(data.fuelSystemStatus, isNot(FuelSystemStatus.unknown));
    });
  });

  group('Category 2 & Zero-Overhead Telemetry — Dashboard UI Rendering', () {
    late ObdProvider obdProvider;
    late TripProvider tripProvider;

    setUp(() {
      obdProvider = ObdProvider();
      tripProvider = TripProvider();
    });

    tearDown(() {
      tripProvider.dispose();
      obdProvider.dispose();
    });

    testWidgets('DashboardScreen renders all sections, cards, and dynamic badges', (tester) async {
      tester.view.physicalSize = const Size(1024, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Seed with rich telemetry data
      obdProvider.setDataForTesting(const ObdData(
        speed: 65,
        rpm: 2400,
        coolantTemp: 88,
        voltage: 14.2,
        horsepower: 48.5,
        torqueNm: 115.0,
        accelerationG: 0.12,
        relativeThrottle: 28.5,
        engineLoad: 38.0,
        manifoldPressure: 55.0,
        timingAdvance: 24.5,
        maf: 32.0,
        fuelLevelPercent: 68.0,
        remainingFuelLiters: 30.6,
        estimatedRangeKm: 450.0,
        shortTermFuelTrim: -1.2,
        longTermFuelTrim: 2.5,
        fuelSystemStatus: FuelSystemStatus.closedLoop,
        isDfcoActive: true,
      ));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ObdProvider>.value(value: obdProvider),
            ChangeNotifierProvider<TripProvider>.value(value: tripProvider),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check section titles
      expect(find.text('DRIVE & ENGINE TELEMETRY'), findsOneWidget);
      expect(find.text('POWER & DRIVING DYNAMICS'), findsOneWidget);
      expect(find.text('INTAKE & COMBUSTION HEALTH'), findsOneWidget);
      expect(find.text('FUEL TANK & AIR-FUEL TRIMS'), findsOneWidget);
      expect(find.text('TRIP & CONSUMPTION'), findsOneWidget);

      // Check individual cards
      expect(find.text('SPEED'), findsOneWidget);
      expect(find.text('RPM'), findsNWidgets(2)); // Card header title and animated unit
      expect(find.text('COOLANT'), findsOneWidget);
      expect(find.text('VOLTAGE'), findsOneWidget);
      expect(find.text('HORSEPOWER'), findsOneWidget);
      expect(find.text('TORQUE'), findsOneWidget);
      expect(find.text('G-FORCE'), findsOneWidget);
      expect(find.text('THROTTLE'), findsOneWidget);
      expect(find.text('ENGINE LOAD'), findsOneWidget);
      expect(find.text('MANIFOLD MAP'), findsOneWidget);
      expect(find.text('IGN TIMING'), findsOneWidget);
      expect(find.text('AIR FLOW (MAF)'), findsOneWidget);
      expect(find.text('FUEL TANK'), findsOneWidget);
      expect(find.text('EST RANGE (DTE)'), findsOneWidget);
      expect(find.text('SHORT TRIM (STFT)'), findsOneWidget);
      expect(find.text('LONG TRIM (LTFT)'), findsOneWidget);
      expect(find.text('FUEL ECONOMY'), findsOneWidget);
      expect(find.text('TRIP DISTANCE'), findsOneWidget);

      // Check live badges
      expect(find.text('DFCO ACTIVE'), findsOneWidget);
      expect(find.text('LOOP: CL'), findsOneWidget);
    });
  });
}
