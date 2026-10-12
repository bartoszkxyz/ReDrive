import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      });
    });
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
    );
    final voltageCard = TelemetryCard(
      title: 'VOLTAGE',
      value: obdData.voltage,
      fractionDigits: 1,
      valueSuffix: '',
      unit: 'V',
      iconPath: 'assets/images/svg/dashboard/settings.svg',
      progress: ((obdData.voltage - 10) / 6).clamp(0.0, 1.0),
    );
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
      iconPath: 'assets/images/svg/bottomBar/dtc.svg',
      progress: (activeTrip.distanceKm / 50.0).clamp(0.0, 1.0),
    );
    final loadCard = TelemetryCard(
      title: 'ENGINE LOAD',
      value: obdData.engineLoad,
      fractionDigits: 1,
      valueSuffix: '',
      unit: '%',
      iconPath: 'assets/images/svg/dashboard/engine.svg',
      progress: (obdData.engineLoad / 100.0).clamp(0.0, 1.0),
    );
    final throttleCard = TelemetryCard(
      title: 'THROTTLE',
      value: obdData.throttlePosition,
      fractionDigits: 1,
      valueSuffix: '',
      unit: '%',
      iconPath: 'assets/images/svg/dashboard/speed.svg',
      progress: (obdData.throttlePosition / 100.0).clamp(0.0, 1.0),
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
              SizedBox(height: isWide ? 14 : 20),

              if (isWide) ...[
                // Row 1 (4 cards)
                Row(
                  children: [
                    Expanded(child: SizedBox(height: cardHeight, child: speedCard)),
                    const SizedBox(width: 12),
                    Expanded(child: SizedBox(height: cardHeight, child: rpmCard)),
                    const SizedBox(width: 12),
                    Expanded(child: SizedBox(height: cardHeight, child: coolantCard)),
                    const SizedBox(width: 12),
                    Expanded(child: SizedBox(height: cardHeight, child: voltageCard)),
                  ],
                ),
                const SizedBox(height: 12),

                // Row 2 (4 cards)
                Row(
                  children: [
                    Expanded(child: SizedBox(height: cardHeight, child: fuelCard)),
                    const SizedBox(width: 12),
                    Expanded(child: SizedBox(height: cardHeight, child: distanceCard)),
                    const SizedBox(width: 12),
                    Expanded(child: SizedBox(height: cardHeight, child: loadCard)),
                    const SizedBox(width: 12),
                    Expanded(child: SizedBox(height: cardHeight, child: throttleCard)),
                  ],
                ),
              ] else ...[
                // Speed & RPM Cards
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(height: cardHeight, child: speedCard),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(height: cardHeight, child: rpmCard),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Coolant Temp & Voltage Cards
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(height: cardHeight, child: coolantCard),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(height: cardHeight, child: voltageCard),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Fuel Economy & Trip Distance Cards
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(height: cardHeight, child: fuelCard),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(height: cardHeight, child: distanceCard),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Engine Load & Throttle Cards
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(height: cardHeight, child: loadCard),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(height: cardHeight, child: throttleCard),
                    ),
                  ],
                ),
              ],
              SizedBox(height: isWide ? 14 : 20),

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
