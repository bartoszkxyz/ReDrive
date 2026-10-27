import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:obdrive/l10n/app_localizations.dart';
import 'package:obdrive/providers/bluetooth_provider.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/sync_provider.dart';
import 'package:obdrive/services/sync/bluetooth_sync_service.dart';
import 'package:obdrive/widget/connection/connection_screen/custom_tab_bar.dart';
import 'package:obdrive/widget/connection/obd_operations_panel.dart';
import 'package:obdrive/widget/connection/phone_sync_operations_panel.dart';
import 'package:obdrive/widget/connection/troubleshooting_panel.dart';
import 'package:obdrive/widget/connection/wifi/wifi_tab.dart';

/// Central Operations Center for all device connections, sync management, and diagnostics:
/// - Tab 1: OBD-II (ELM327): Manual connect/disconnect, live telemetry status, protocol config, adapter tests.
/// - Tab 2: Phone Sync: Android Auto Wi-Fi TCP socket synchronization, parked car status, mechanic report.
/// - Tab 3: Wi-Fi / TCP: Direct emulator and Wi-Fi adapter connection.
/// - Tab 4: Diagnostics: Step-by-step connection checklists, adapter hardware test, and blackbox log viewer.
class ConnectionScreen extends StatefulWidget {
  final ConnectionTab initialTab;

  const ConnectionScreen({
    super.key,
    this.initialTab = ConnectionTab.obd,
  });

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late ConnectionTab _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final btProvider = context.watch<BluetoothProvider>();
    final obdProvider = context.watch<ObdProvider>();
    final syncProvider = context.watch<SyncProvider>();

    final isEcuPolling = obdProvider.isEcuConnected;
    final isObdConnected = btProvider.isConnected || obdProvider.isDeviceConnected;
    final isSyncConnected = syncProvider.connectionState == SyncConnectionState.connected ||
        syncProvider.connectionState == SyncConnectionState.synced;
    final isSyncServer = syncProvider.networkSyncManager.isServerRunning;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Operations Header with live glanceable connection pills
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.connection,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                          letterSpacing: -0.6,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Operations & Diagnostics Center',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white54,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),

                  // Quick Live Status Badges
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // OBD Status Chip
                      GestureDetector(
                        onTap: () => setState(() => _selectedTab = ConnectionTab.obd),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: isEcuPolling
                                ? const Color(0xFF00E676).withValues(alpha: 0.15)
                                : (isObdConnected
                                    ? Colors.amber.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isEcuPolling
                                  ? const Color(0xFF00E676).withValues(alpha: 0.5)
                                  : (isObdConnected
                                      ? Colors.amber.withValues(alpha: 0.5)
                                      : Colors.white24),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isEcuPolling
                                      ? const Color(0xFF00E676)
                                      : (isObdConnected ? Colors.amber : Colors.white38),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isEcuPolling
                                    ? 'OBD: Polling'
                                    : (isObdConnected ? 'OBD: Ready' : 'OBD: Off'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isEcuPolling
                                      ? const Color(0xFF00E676)
                                      : (isObdConnected ? Colors.amber : Colors.white60),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Sync Status Chip
                      GestureDetector(
                        onTap: () => setState(() => _selectedTab = ConnectionTab.sync),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSyncConnected
                                ? const Color(0xFF00E676).withValues(alpha: 0.15)
                                : (isSyncServer
                                    ? colorScheme.primary.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSyncConnected
                                  ? const Color(0xFF00E676).withValues(alpha: 0.5)
                                  : (isSyncServer
                                      ? colorScheme.primary.withValues(alpha: 0.5)
                                      : Colors.white24),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSyncConnected
                                      ? const Color(0xFF00E676)
                                      : (isSyncServer ? colorScheme.primary : Colors.white38),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isSyncConnected
                                    ? 'Sync: Synced'
                                    : (isSyncServer ? 'Sync: :7355' : 'Sync: Off'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSyncConnected
                                      ? const Color(0xFF00E676)
                                      : (isSyncServer ? colorScheme.primary : Colors.white60),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Tactical Tab Bar
              CustomTabBar(
                selectedTab: _selectedTab,
                onTabSelected: (tab) {
                  setState(() => _selectedTab = tab);
                },
              ),

              const SizedBox(height: 14),

              // Tab View Content
              Expanded(
                child: IndexedStack(
                  index: _selectedTab.index,
                  children: const [
                    ObdOperationsPanel(),
                    PhoneSyncOperationsPanel(),
                    WifiTab(),
                    TroubleshootingPanel(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
