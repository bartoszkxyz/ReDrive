import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:redrive/obd/models/fuel_system_status.dart';
import 'package:redrive/obd/pid/pid_key.dart';
import 'package:redrive/obd/polling/polling_controller.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/widget/home_screen/telemetry_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<ObdProvider>().setWatchlist(WatchSource.visibleScreen, {
        PidKey.vehicleSpeed,
        PidKey.engineRpm,
        PidKey.coolantTemperature,
        PidKey.adapterVoltage,
        PidKey.engineLoad,
        PidKey.throttlePosition,
        PidKey.mafAirFlowRate,
        PidKey.engineFuelRate,
        // Category 2 Expanded Sensor Metrics
        PidKey.shortTermFuelTrim1,
        PidKey.longTermFuelTrim1,
        PidKey.timingAdvance,
        PidKey.intakeManifoldPressure,
        PidKey.fuelTankLevel,
        PidKey.fuelSystemStatus,
      });
    });
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 14.0, bottom: 8.0),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardRow4({
    required bool isWide,
    required double cardHeight,
    required Widget card1,
    required Widget card2,
    required Widget card3,
    required Widget card4,
  }) {
    if (isWide) {
      return Row(
        children: [
          Expanded(child: SizedBox(height: cardHeight, child: card1)),
          const SizedBox(width: 12),
          Expanded(child: SizedBox(height: cardHeight, child: card2)),
          const SizedBox(width: 12),
          Expanded(child: SizedBox(height: cardHeight, child: card3)),
          const SizedBox(width: 12),
          Expanded(child: SizedBox(height: cardHeight, child: card4)),
        ],
      );
    } else {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: SizedBox(height: cardHeight, child: card1)),
              const SizedBox(width: 12),
              Expanded(child: SizedBox(height: cardHeight, child: card2)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SizedBox(height: cardHeight, child: card3)),
              const SizedBox(width: 12),
              Expanded(child: SizedBox(height: cardHeight, child: card4)),
            ],
          ),
        ],
      );
    }
  }

  Widget _buildCardRow2({
    required double cardHeight,
    required Widget card1,
    required Widget card2,
  }) {
    return Row(
      children: [
        Expanded(child: SizedBox(height: cardHeight, child: card1)),
        const SizedBox(width: 12),
        Expanded(child: SizedBox(height: cardHeight, child: card2)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final obdProvider = context.watch<ObdProvider>();
    final tripProvider = context.watch<TripProvider>();
    final obdData = obdProvider.data;
    final activeTrip = tripProvider.activeTrip;
    final colorScheme = Theme.of(context).colorScheme;

    final isReal = obdProvider.mode == ObdMode.real;
    final isDemo = obdProvider.mode == ObdMode.demo;
    final isEcuConnected = obdProvider.isEcuConnected;

    String statusText = 'OFFLINE';
    Color statusColor = Colors.grey;

    if (isEcuConnected) {
      statusText = 'LIVE OBD';
      statusColor = colorScheme.primary;
    } else if (isDemo) {
      statusText = 'DEMO MODE';
      statusColor = Colors.amber;
    } else if (obdProvider.isDeviceConnected) {
      statusText = 'CONNECTED (IDLE)';
      statusColor = Colors.blueAccent;
    }

    final fuelUnit = obdData.speed > 0 ? 'L/100km' : 'L/h';
    final fuelValue = obdData.speed > 0
        ? activeTrip.instantFuelL100km
        : activeTrip.instantFuelLPerHour;

    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 850;
    final double cardHeight = isWide ? 160.0 : 190.0;

    // --- Threshold Problem & Warning Evaluations ---

    // Coolant Temperature
    Color? coolantStatusColor;
    String? coolantStatusBadge;
    if (obdData.coolantTemp > 104) {
      coolantStatusColor = const Color(0xFFEF4444); // Red Overheating
      coolantStatusBadge = 'OVERHEAT';
    } else if (obdData.coolantTemp >= 99) {
      coolantStatusColor = const Color(0xFFF59E0B); // Amber Elevated
      coolantStatusBadge = 'ELEVATED';
    } else if (obdData.coolantTemp > 0 && obdData.coolantTemp < 65) {
      coolantStatusColor = const Color(0xFF38BDF8); // Sky Blue Warmup
      coolantStatusBadge = 'WARMUP';
    }

    // Battery / Adapter Voltage
    Color? voltageStatusColor;
    String? voltageStatusBadge;
    if (obdData.voltage > 0) {
      if (obdData.voltage < 11.8 || obdData.voltage >= 15.4) {
        voltageStatusColor = const Color(0xFFEF4444); // Red Problem
        voltageStatusBadge = obdData.voltage < 11.8 ? 'LOW BATT' : 'OVERVOLT';
      } else if (obdData.voltage < 12.8 || obdData.voltage >= 15.0) {
        voltageStatusColor = const Color(0xFFF59E0B); // Amber Warning
        voltageStatusBadge = obdData.voltage < 12.8 ? 'LOW VOLT' : 'HIGH VOLT';
      }
    }

    // Manifold Absolute Pressure (Vacuum leak detection at idle)
    Color? mapStatusColor;
    String? mapStatusBadge;
    if (obdData.speed == 0 && obdData.rpm > 500 && obdData.relativeThrottle <= 1.5) {
      if (obdData.manifoldPressure >= 55.0) {
        mapStatusColor = const Color(0xFFEF4444); // Red High Idle Pressure / Leak
        mapStatusBadge = 'LEAK?';
      } else if (obdData.manifoldPressure >= 46.0) {
        mapStatusColor = const Color(0xFFF59E0B); // Amber Low Vacuum
        mapStatusBadge = 'LOW VAC';
      }
    }

    // Fuel Tank & Range
    Color? fuelTankStatusColor;
    String? fuelTankStatusBadge;
    if (obdData.fuelLevelPercent > 0) {
      if (obdData.fuelLevelPercent <= 10.0) {
        fuelTankStatusColor = const Color(0xFFEF4444); // Red Critical Reserve
        fuelTankStatusBadge = 'RESERVE';
      } else if (obdData.fuelLevelPercent <= 18.0) {
        fuelTankStatusColor = const Color(0xFFF59E0B); // Amber Low Fuel
        fuelTankStatusBadge = 'LOW FUEL';
      }
    }

    Color? rangeStatusColor;
    String? rangeStatusBadge;
    if (obdData.estimatedRangeKm > 0) {
      if (obdData.estimatedRangeKm <= 30.0) {
        rangeStatusColor = const Color(0xFFEF4444);
        rangeStatusBadge = 'CRITICAL';
      } else if (obdData.estimatedRangeKm <= 60.0) {
        rangeStatusColor = const Color(0xFFF59E0B);
        rangeStatusBadge = 'LOW';
      }
    }

    // Short-Term Fuel Trim (STFT)
    Color? stftStatusColor;
    String? stftStatusBadge;
    final stftVal = obdData.shortTermFuelTrim;
    if (stftVal.abs() >= 15.0) {
      stftStatusColor = const Color(0xFFEF4444); // Red Imminent DTC threshold
      stftStatusBadge = stftVal > 0 ? 'HIGH LEAN' : 'HIGH RICH';
    } else if (stftVal.abs() >= 10.0) {
      stftStatusColor = const Color(0xFFF59E0B); // Amber Warning
      stftStatusBadge = stftVal > 0 ? 'LEAN' : 'RICH';
    }

    // Long-Term Fuel Trim (LTFT)
    Color? ltftStatusColor;
    String? ltftStatusBadge;
    final ltftVal = obdData.longTermFuelTrim;
    if (ltftVal.abs() >= 15.0) {
      ltftStatusColor = const Color(0xFFEF4444); // Red Imminent P0171/P0172
      ltftStatusBadge = ltftVal > 0 ? 'CHECK LEAN' : 'CHECK RICH';
    } else if (ltftVal.abs() >= 10.0) {
      ltftStatusColor = const Color(0xFFF59E0B); // Amber Warning
      ltftStatusBadge = ltftVal > 0 ? 'LEAN TRIM' : 'RICH TRIM';
    }

    // --- Section 1: Core Drive Telemetry ---
    final speedCard = TelemetryCard(
      title: 'SPEED',
      value: obdData.speed.toDouble(),
      fractionDigits: 0,
      valueSuffix: '',
      unit: 'km/h',
      iconPath: 'assets/images/svg/dashboard/speed.svg',
      progress: (obdData.speed / 240).clamp(0.0, 1.0),
    );
    final rpmCard = TelemetryCard(
      title: 'RPM',
      value: obdData.rpm / 1000,
      fractionDigits: 1,
      valueSuffix: 'K',
      unit: 'rpm',
      iconPath: 'assets/images/svg/dashboard/engine.svg',
      progress: (obdData.rpm / 8000).clamp(0.0, 1.0),
    );
    final coolantCard = TelemetryCard(
      title: 'COOLANT',
      value: obdData.coolantTemp.toDouble(),
      fractionDigits: 0,
      valueSuffix: '',
      unit: '°C',
      iconPath: 'assets/images/svg/dashboard/temp.svg',
      progress: ((obdData.coolantTemp + 40) / 160).clamp(0.0, 1.0),
      statusColor: coolantStatusColor,
      statusBadge: coolantStatusBadge,
    );
    final voltageCard = TelemetryCard(
      title: 'VOLTAGE',
      value: obdData.voltage,
      fractionDigits: 1,
      valueSuffix: '',
      unit: 'V',
      iconPath: 'assets/images/svg/dashboard/settings.svg',
      progress: ((obdData.voltage - 10) / 6).clamp(0.0, 1.0),
      statusColor: voltageStatusColor,
      statusBadge: voltageStatusBadge,
    );

    // --- Section 2: Power & Driving Dynamics ---
    final hpCard = TelemetryCard(
      title: 'HORSEPOWER',
      value: obdData.horsepower,
      fractionDigits: 1,
      valueSuffix: '',
      unit: 'HP',
      iconPath: 'assets/images/svg/dashboard/engine.svg',
      progress: (obdData.horsepower / 110.0).clamp(0.0, 1.0),
    );
    final torqueCard = TelemetryCard(
      title: 'TORQUE',
      value: obdData.torqueNm,
      fractionDigits: 1,
      valueSuffix: '',
      unit: 'N·m',
      iconPath: 'assets/images/svg/dashboard/settings.svg',
      progress: (obdData.torqueNm / 140.0).clamp(0.0, 1.0),
    );
    final gForceCard = TelemetryCard(
      title: 'G-FORCE',
      value: obdData.accelerationG,
      fractionDigits: 2,
      valueSuffix: '',
      unit: 'g',
      iconPath: 'assets/images/svg/dashboard/speed.svg',
      progress: ((obdData.accelerationG + 0.5) / 1.0).clamp(0.0, 1.0),
    );
    final throttleCard = TelemetryCard(
      title: 'THROTTLE',
      value: obdData.relativeThrottle,
      fractionDigits: 1,
      valueSuffix: '',
      unit: '%',
      iconPath: 'assets/images/svg/dashboard/speed.svg',
      progress: (obdData.relativeThrottle / 100.0).clamp(0.0, 1.0),
    );

    // --- Section 3: Intake & Combustion Health ---
    final loadCard = TelemetryCard(
      title: 'ENGINE LOAD',
      value: obdData.engineLoad,
      fractionDigits: 1,
      valueSuffix: '',
      unit: '%',
      iconPath: 'assets/images/svg/dashboard/engine.svg',
      progress: (obdData.engineLoad / 100.0).clamp(0.0, 1.0),
    );
    final mapCard = TelemetryCard(
      title: 'MANIFOLD MAP',
      value: obdData.manifoldPressure,
      fractionDigits: 0,
      valueSuffix: '',
      unit: 'kPa',
      iconPath: 'assets/images/svg/dashboard/engine.svg',
      progress: (obdData.manifoldPressure / 120.0).clamp(0.0, 1.0),
      statusColor: mapStatusColor,
      statusBadge: mapStatusBadge,
    );
    final timingCard = TelemetryCard(
      title: 'IGN TIMING',
      value: obdData.timingAdvance,
      fractionDigits: 1,
      valueSuffix: '',
      unit: '°BTDC',
      iconPath: 'assets/images/svg/dashboard/temp.svg',
      progress: ((obdData.timingAdvance + 10) / 60.0).clamp(0.0, 1.0),
    );
    final mafCard = TelemetryCard(
      title: 'AIR FLOW (MAF)',
      value: obdData.maf,
      fractionDigits: 1,
      valueSuffix: '',
      unit: 'g/s',
      iconPath: 'assets/images/svg/dashboard/temp.svg',
      progress: (obdData.maf / 90.0).clamp(0.0, 1.0),
    );

    // --- Section 4: Fuel Tank & Air-Fuel Trims ---
    final fuelTankCard = TelemetryCard(
      title: 'FUEL TANK',
      value: obdData.fuelLevelPercent,
      fractionDigits: 0,
      valueSuffix: '',
      unit: obdData.remainingFuelLiters > 0
          ? '% (${obdData.remainingFuelLiters.toStringAsFixed(0)}L)'
          : '%',
      iconPath: 'assets/images/svg/dashboard/fuel.svg',
      progress: (obdData.fuelLevelPercent / 100.0).clamp(0.0, 1.0),
      statusColor: fuelTankStatusColor,
      statusBadge: fuelTankStatusBadge,
    );
    final rangeCard = TelemetryCard(
      title: 'EST RANGE (DTE)',
      value: obdData.estimatedRangeKm,
      fractionDigits: 0,
      valueSuffix: '',
      unit: 'km',
      iconPath: 'assets/images/svg/bottomBar/dtc.svg',
      progress: (obdData.estimatedRangeKm / 600.0).clamp(0.0, 1.0),
      statusColor: rangeStatusColor,
      statusBadge: rangeStatusBadge,
    );
    final stftCard = TelemetryCard(
      title: 'SHORT TRIM (STFT)',
      value: obdData.shortTermFuelTrim,
      fractionDigits: 1,
      valueSuffix: '',
      unit: '%',
      iconPath: 'assets/images/svg/dashboard/fuel.svg',
      progress: ((obdData.shortTermFuelTrim + 25) / 50.0).clamp(0.0, 1.0),
      statusColor: stftStatusColor,
      statusBadge: stftStatusBadge,
    );
    final ltftCard = TelemetryCard(
      title: 'LONG TRIM (LTFT)',
      value: obdData.longTermFuelTrim,
      fractionDigits: 1,
      valueSuffix: '',
      unit: '%',
      iconPath: 'assets/images/svg/dashboard/fuel.svg',
      progress: ((obdData.longTermFuelTrim + 25) / 50.0).clamp(0.0, 1.0),
      statusColor: ltftStatusColor,
      statusBadge: ltftStatusBadge,
    );

    // --- Section 5: Trip & Efficiency ---
    final fuelCard = TelemetryCard(
      title: 'FUEL ECONOMY',
      value: fuelValue,
      fractionDigits: 1,
      valueSuffix: '',
      unit: fuelUnit,
      iconPath: 'assets/images/svg/dashboard/fuel.svg',
      progress: (fuelValue / 20.0).clamp(0.0, 1.0),
    );
    final distanceCard = TelemetryCard(
      title: 'TRIP DISTANCE',
      value: activeTrip.distanceKm,
      fractionDigits: 2,
      valueSuffix: '',
      unit: 'km',
      iconPath: 'assets/images/svg/bottomBar/trips.svg',
      progress: (activeTrip.distanceKm / 50.0).clamp(0.0, 1.0),
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: isWide ? 10.0 : 12.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dashboard',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: isWide ? 26 : 32,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                          letterSpacing: -0.8,
                        ),
                      ),
                      Text(
                        'LIVE SENSOR TELEMETRY',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: isWide ? 11 : 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  Flexible(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (obdData.isDfcoActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF10B981),
                                width: 1.5,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.eco,
                                    size: 14, color: Color(0xFF10B981)),
                                SizedBox(width: 4),
                                Text(
                                  'DFCO ACTIVE',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: Color(0xFF10B981),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (obdData.fuelSystemStatus !=
                            FuelSystemStatus.unknown)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: (obdData.fuelSystemStatus.isClosedLoop
                                      ? const Color(0xFF06B6D4)
                                      : Colors.orangeAccent)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: obdData.fuelSystemStatus.isClosedLoop
                                    ? const Color(0xFF06B6D4)
                                    : Colors.orangeAccent,
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              'LOOP: ${obdData.fuelSystemStatus.shortCode}',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: obdData.fuelSystemStatus.isClosedLoop
                                    ? const Color(0xFF06B6D4)
                                    : Colors.orangeAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 1. Drive & Engine Telemetry
              _buildSectionHeader('DRIVE & ENGINE TELEMETRY', colorScheme),
              _buildCardRow4(
                isWide: isWide,
                cardHeight: cardHeight,
                card1: speedCard,
                card2: rpmCard,
                card3: coolantCard,
                card4: voltageCard,
              ),

              // 2. Power & Dynamics
              _buildSectionHeader('POWER & DRIVING DYNAMICS', colorScheme),
              _buildCardRow4(
                isWide: isWide,
                cardHeight: cardHeight,
                card1: hpCard,
                card2: torqueCard,
                card3: gForceCard,
                card4: throttleCard,
              ),

              // 3. Intake & Combustion Health
              _buildSectionHeader('INTAKE & COMBUSTION HEALTH', colorScheme),
              _buildCardRow4(
                isWide: isWide,
                cardHeight: cardHeight,
                card1: loadCard,
                card2: mapCard,
                card3: timingCard,
                card4: mafCard,
              ),

              // 4. Fuel Tank & Air-Fuel Trims
              _buildSectionHeader('FUEL TANK & AIR-FUEL TRIMS', colorScheme),
              _buildCardRow4(
                isWide: isWide,
                cardHeight: cardHeight,
                card1: fuelTankCard,
                card2: rangeCard,
                card3: stftCard,
                card4: ltftCard,
              ),

              // 5. Trip & Consumption
              _buildSectionHeader('TRIP & CONSUMPTION', colorScheme),
              _buildCardRow2(
                cardHeight: cardHeight,
                card1: fuelCard,
                card2: distanceCard,
              ),

              const SizedBox(height: 16),

              // Live Trip Summary Banner
              if (activeTrip.isActive) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141A23),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'TRIP IN PROGRESS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.primary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fuel: ${activeTrip.fuelConsumedLiters.toStringAsFixed(2)} L • Avg: ${activeTrip.distanceKm > 0.05 ? activeTrip.avgFuelConsumption.toStringAsFixed(1) : '--'} L/100'
                            '${obdData.remainingFuelLiters > 0 ? " • Tank: ${obdData.remainingFuelLiters.toStringAsFixed(1)}L" : ""}'
                            '${obdData.horsepower > 0 ? " • Power: ${obdData.horsepower.toStringAsFixed(0)} HP" : ""}'
                            '${obdData.maf > 0 ? " • MAF: ${obdData.maf.toStringAsFixed(1)} g/s" : ""}'
                            '${obdData.engineFuelRate > 0 ? " • Rate: ${obdData.engineFuelRate.toStringAsFixed(1)} L/h" : ""}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${activeTrip.duration.inMinutes}m ${activeTrip.duration.inSeconds.remainder(60)}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Quick Controls when offline
              if (!isReal && !isDemo) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'No live data streaming. Connect to an ELM327 adapter/emulator or activate Demo Mode to calculate live fuel and track trips.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Start Demo'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => obdProvider.startDemoMode(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
