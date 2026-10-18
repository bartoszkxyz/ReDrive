import 'package:redrive/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:redrive/obd/pid/pid_key.dart';
import 'package:redrive/obd/polling/polling_controller.dart';
import 'package:redrive/obd/source/obd_source_state.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/widget/home_screen/active_trip_tile.dart';
import 'package:redrive/widget/home_screen/connections_buttons.dart';
import 'package:redrive/widget/home_screen/engine_load_card.dart';
import 'package:redrive/widget/home_screen/engine_temp_card.dart';
import 'package:redrive/widget/home_screen/header_bar.dart';

import 'package:redrive/core/app_flavor.dart';
import 'package:redrive/obd/connection/tcp_obd_connection.dart';
import 'package:redrive/providers/sync_provider.dart';
import 'package:redrive/widget/companion/parked_car_status_card.dart';
import 'package:redrive/widget/companion/sync_status_pill.dart';
import '../providers/obd_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

String _connectionMessage(BuildContext context, ObdSourceState state) {
  final l = AppLocalizations.of(context);
  switch (state) {
    case ObdSourceState.disconnected:
      return l.preparing;
    case ObdSourceState.connecting:
      return l.connectingEcu;
    case ObdSourceState.initializing:
      return l.initializing;
    case ObdSourceState.polling:
      return l.connected;
    case ObdSourceState.recovering:
      return l.recovering;
    case ObdSourceState.error:
      return l.connectionError;
  }
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<ObdProvider>().setWatchlist(WatchSource.visibleScreen, {
        PidKey.vehicleSpeed,
        PidKey.engineRpm,
        PidKey.coolantTemperature,
        PidKey.mafAirFlowRate,
        PidKey.engineLoad,
        PidKey.engineFuelRate,
      });
    });
  }

  Future<void> _handleConnect(
    ObdProvider obdProvider,
    AppLocalizations l,
  ) async {
    final isDeviceConnected = obdProvider.isDeviceConnected;
    final isReal = obdProvider.mode == ObdMode.real;
    final isReconnecting = obdProvider.isReconnecting;

    if (!isDeviceConnected) {
      final tcp = TcpObdConnection();
      final connected = await tcp.connect();
      if (!mounted) return;
      if (connected) {
        obdProvider.attachConnection(tcp);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.connectAdapterFirst)),
        );
        return;
      }
    }
    if (isReal) {
      await obdProvider.stopRealMode();
      return;
    }
    if (!mounted) return;
    if (isReconnecting) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.reconnectWait)));
      return;
    }

    await _connectWithDialog(obdProvider);

    if (obdProvider.mode != ObdMode.real && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.ecuFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final obdProvider = context.watch<ObdProvider>();
    final tripProvider = context.watch<TripProvider>();

    SyncProvider? syncProvider;
    try {
      syncProvider = context.watch<SyncProvider>();
    } catch (_) {
      syncProvider = null;
    }

    final obdData = obdProvider.data;
    final activeTrip = tripProvider.activeTrip;
    final bool isDeviceConnected = obdProvider.isDeviceConnected;
    final bool isObdConnected = obdProvider.isEcuConnected;
    final colorScheme = Theme.of(context).colorScheme;

    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 850;

    final engineTempCard = EngineTempCard(
      coolantTemp: obdData.coolantTemp,
      isConnected: isObdConnected,
      isDemo: obdProvider.mode == ObdMode.demo,
    );

    final engineLoadCard = EngineLoadCard(
      load: obdData.engineLoad,
      isConnected: isObdConnected,
      isDemo: obdProvider.mode == ObdMode.demo,
      title: l.engineLoad,
    );

    final showParkedCarCard = syncProvider?.latestSnapshot != null &&
        (AppConfig.current.flavor.isPhone || syncProvider?.latestSnapshot != null);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: isWide ? 10.0 : 12.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HeaderBar(
                  trailing: syncProvider != null
                      ? SyncStatusPill(
                          connectionState: syncProvider.connectionState,
                          lastSyncTime: syncProvider.lastSyncTime,
                          onTap: () {
                            syncProvider?.startSyncSession();
                          },
                        )
                      : null,
                ),
                SizedBox(height: isWide ? 14 : 20),

                if (showParkedCarCard) ...[
                  ParkedCarStatusCard(snapshot: syncProvider!.latestSnapshot!),
                  SizedBox(height: isWide ? 14 : 16),
                ],

                if (isWide) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 195,
                          child: engineTempCard,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 195,
                          child: engineLoadCard,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 4,
                        child: SizedBox(
                          height: 195,
                          child: _VehicleStatusPanel(
                            isConnected: isObdConnected,
                            isDeviceConnected: isDeviceConnected,
                            isDemo: obdProvider.mode == ObdMode.demo,
                            onConnect: () => _handleConnect(obdProvider, l),
                            onToggleDemo: () {
                              if (obdProvider.mode == ObdMode.demo) {
                                obdProvider.stopDemoMode();
                              } else {
                                obdProvider.startDemoMode();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ActiveTripTile(
                    activeTrip: activeTrip,
                    pastTrips: tripProvider.pastTrips,
                    onEndTrip: () => tripProvider.manualEndTrip(),
                    onStartTrip: () => tripProvider.manualStartTrip(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.directions_car_rounded, size: 16, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Suzuki Swift M15A (1.5L)',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.auto_mode_rounded, size: 16, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Auto-trip start & save (>10 km)',
                              style: TextStyle(
                                color: colorScheme.onSurface.withValues(alpha: 0.7),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 190,
                          child: engineTempCard,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 190,
                          child: engineLoadCard,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ActiveTripTile(
                    activeTrip: activeTrip,
                    pastTrips: tripProvider.pastTrips,
                    onEndTrip: () => tripProvider.manualEndTrip(),
                    onStartTrip: () => tripProvider.manualStartTrip(),
                  ),
                  const SizedBox(height: 14),
                  ConnectionButtons(
                    isConnected: isObdConnected,
                    onConnect: () => _handleConnect(obdProvider, l),
                  ),
                ],

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _connectWithDialog(ObdProvider obdProvider) async {
    var isCancelled = false;

    _showConnectingDialog(
      onCancel: () async {
        isCancelled = true;
        await obdProvider.stopRealMode();
      },
    );

    await obdProvider.startRealMode();

    if (!mounted || isCancelled) return;

    Navigator.of(context, rootNavigator: true).pop();
  }

  void _showConnectingDialog({required Future<void> Function() onCancel}) {
    final l = AppLocalizations.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Selector<ObdProvider, ObdSourceState>(
                  selector: (_, obd) => obd.state,
                  builder: (context, state, _) => Text(
                    _connectionMessage(context, state),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await onCancel();

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: Text(l.cancel),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VehicleStatusPanel extends StatelessWidget {
  final bool isConnected;
  final bool isDeviceConnected;
  final bool isDemo;
  final VoidCallback onConnect;
  final VoidCallback? onToggleDemo;

  const _VehicleStatusPanel({
    required this.isConnected,
    required this.isDeviceConnected,
    required this.isDemo,
    required this.onConnect,
    this.onToggleDemo,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    String statusText = 'OFFLINE';
    Color statusColor = Colors.grey;
    String statusSubtitle = 'Tap Connect to pair with vehicle';

    if (isConnected) {
      statusText = 'LIVE OBD';
      statusColor = colorScheme.primary;
      statusSubtitle = 'Streaming real-time ECU telemetry';
    } else if (isDemo) {
      statusText = 'DEMO MODE';
      statusColor = Colors.amber;
      statusSubtitle = 'Simulating driving dynamics';
    } else if (isDeviceConnected) {
      statusText = 'ADAPTER PAIRED';
      statusColor = Colors.blueAccent;
      statusSubtitle = 'Ready to initialize OBD-II session';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.bluetooth_connected_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'OBD-II ADAPTER',
                        textScaler: TextScaler.noScaling,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Row(
                children: [
                  if (onToggleDemo != null) ...[
                    InkWell(
                      onTap: onToggleDemo,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDemo ? Colors.amber.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDemo ? Colors.amber : Colors.white24,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          isDemo ? 'STOP DEMO' : 'TRY DEMO',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: isDemo ? Colors.amber : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor, width: 1.2),
                    ),
                    child: Text(
                      statusText,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Text(
            statusSubtitle,
            textScaler: TextScaler.noScaling,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          ConnectionButtons(
            isConnected: isConnected,
            onConnect: onConnect,
          ),
        ],
      ),
    );
  }
}
