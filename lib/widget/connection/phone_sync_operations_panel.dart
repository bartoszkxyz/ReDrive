import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:obdrive/core/app_flavor.dart';
import 'package:obdrive/providers/sync_provider.dart';
import 'package:obdrive/services/sync/bluetooth_sync_service.dart';
import 'package:obdrive/services/sync/network_sync_manager.dart';
import 'package:obdrive/widget/companion/mechanic_report_sheet.dart';

/// Complete Operations Center widget for Phone Companion ↔ Headunit Synchronization.
///
/// Features:
/// 1. Glanceable Live Sync Status & Network Connection details (Android Auto Wi-Fi link).
/// 2. Instant manual "Sync Now" trigger button.
/// 3. Server start/restart on Headunit and Connect to Gateway on Phone Companion.
/// 4. Parked Car Snapshot & DTC Mechanic Diagnostic Report inspection.
/// 5. Technical briefing explaining coexistence with Android Auto over Wi-Fi TCP sockets.
class PhoneSyncOperationsPanel extends StatefulWidget {
  const PhoneSyncOperationsPanel({super.key});

  @override
  State<PhoneSyncOperationsPanel> createState() => _PhoneSyncOperationsPanelState();
}

class _PhoneSyncOperationsPanelState extends State<PhoneSyncOperationsPanel> {
  final TextEditingController _hostController =
      TextEditingController(text: NetworkSyncManager.defaultAndroidAutoGateway);
  bool _isConnecting = false;
  List<String> _localIps = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final syncProvider = context.read<SyncProvider>();
      if (AppConfig.isHeadunit) {
        _refreshLocalIps();
      } else {
        final activeHost = syncProvider.networkSyncManager.activeTargetHost;
        if (activeHost.isNotEmpty) {
          _hostController.text = activeHost;
        }
      }
    });
  }

  Future<void> _refreshLocalIps() async {
    final syncProvider = context.read<SyncProvider>();
    final ips = await syncProvider.networkSyncManager.getLocalIpAddresses();
    if (mounted) {
      setState(() => _localIps = ips);
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  String _formatSyncTime(DateTime? dt) {
    if (dt == null) return 'Never synced';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _handleConnectPhone(SyncProvider syncProvider) async {
    HapticFeedback.mediumImpact();
    setState(() => _isConnecting = true);
    final host = _hostController.text.trim();
    if (host.isNotEmpty) {
      await syncProvider.setCustomTargetHost(host);
    }
    final ok = await syncProvider.connectNetworkSync(
      host: host.isNotEmpty ? host : NetworkSyncManager.defaultAndroidAutoGateway,
    );
    if (mounted) {
      setState(() => _isConnecting = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to connect to Headunit at $host:7355. Ensure Android Auto is connected.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleSyncNow(SyncProvider syncProvider) async {
    HapticFeedback.lightImpact();
    await syncProvider.startSyncSession();
  }

  Future<void> _handleOpenMechanicReport(
    BuildContext context,
    SyncProvider syncProvider,
  ) async {
    HapticFeedback.lightImpact();
    final report = syncProvider.latestMechanicReport ??
        await syncProvider.generateMechanicReport();
    if (context.mounted) {
      await MechanicReportSheet.show(context, report: report);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final syncProvider = context.watch<SyncProvider>();
    final isHeadunit = AppConfig.isHeadunit;

    final connectionState = syncProvider.connectionState;
    final isServerRunning = syncProvider.networkSyncManager.isServerRunning;
    final isConnected = connectionState == SyncConnectionState.connected ||
        connectionState == SyncConnectionState.synced;
    final isSyncing = connectionState == SyncConnectionState.syncing;

    final statusColor = isConnected
        ? const Color(0xFF00E676)
        : (isSyncing
            ? Colors.amber
            : (isServerRunning ? colorScheme.primary : Colors.white38));

    final statusText = isConnected
        ? 'Connected & Synced'
        : (isSyncing
            ? 'Syncing Telemetry & Logs...'
            : (isServerRunning
                ? 'Server Listening (:7355)'
                : 'Disconnected'));

    final snapshot = syncProvider.latestSnapshot;
    final report = syncProvider.latestMechanicReport;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. HERO SYNC STATUS CARD
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header: Role Badge + Status Indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        isHeadunit ? 'HEADUNIT SYNC SERVER' : 'PHONE COMPANION CLIENT',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.6),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Transport Details
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.wifi_tethering_rounded,
                        color: Color(0xFF00E676),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Android Auto Wi-Fi Network',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isHeadunit
                                ? (_localIps.isNotEmpty
                                    ? 'Port 7355 • IP: ${_localIps.join(", ")}'
                                    : 'Port 7355 (All Network Interfaces)')
                                : 'Target Gateway: ${_hostController.text}:7355',
                            style: TextStyle(
                              color: isHeadunit ? Colors.white70 : Colors.white54,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatSyncTime(syncProvider.lastSyncTime),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Action Buttons: Sync Now + Connect/Restart Server
                Row(
                  children: [
                    // Primary Action: SYNC NOW
                    Expanded(
                      flex: 6,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          key: const Key('sync_now_button'),
                          onPressed: isSyncing
                              ? null
                              : () => _handleSyncNow(syncProvider),
                          icon: isSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(
                                  Icons.sync_rounded,
                                  size: 22,
                                  color: Colors.black,
                                ),
                          label: Text(
                            isSyncing ? 'SYNCING...' : 'SYNC NOW',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Colors.black,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Secondary Action: Connect (Phone) or Restart Server (Headunit)
                    Expanded(
                      flex: 4,
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          key: isHeadunit
                              ? const Key('restart_sync_server_button')
                              : const Key('connect_headunit_sync_button'),
                          onPressed: _isConnecting
                              ? null
                              : (isHeadunit
                                  ? () async {
                                      HapticFeedback.lightImpact();
                                      await syncProvider.startNetworkSyncServer();
                                    }
                                  : () => _handleConnectPhone(syncProvider)),
                          icon: Icon(
                            isHeadunit
                                ? Icons.restart_alt_rounded
                                : Icons.link_rounded,
                            size: 20,
                            color: Colors.white70,
                          ),
                          label: Text(
                            isHeadunit ? 'RESTART' : 'CONNECT',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: Colors.white70,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. PHONE HOST INPUT ROW (if on phone)
          if (!isHeadunit) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings_ethernet_rounded, color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  const Text(
                    'Headunit IP:',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('sync_headunit_ip_input'),
                      controller: _hostController,
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '192.168.43.1',
                        hintStyle: TextStyle(color: Colors.white24),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 3. SYNCED DATA SUMMARY: Parked Car Snapshot + Diagnostic Report
          Row(
            children: [
              // Parked Car Snapshot Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.local_parking_rounded, color: colorScheme.primary, size: 18),
                          const SizedBox(width: 6),
                          const Text(
                            'Parked Snapshot',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot != null && snapshot.latitude != null
                            ? '${snapshot.latitude!.toStringAsFixed(4)}, ${snapshot.longitude!.toStringAsFixed(4)}'
                            : 'No GPS fix saved',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        snapshot != null
                            ? 'Fuel: ${snapshot.remainingFuelLiters.toStringAsFixed(1)}L • Batt: ${snapshot.batteryVoltage.toStringAsFixed(1)}V'
                            : 'Waiting for ignition off',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Mechanic Diagnostic Report Card
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const Key('open_mechanic_report_card_button'),
                    onTap: () => _handleOpenMechanicReport(context, syncProvider),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF00E676).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.assignment_rounded, color: Color(0xFF00E676), size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Mechanic Report',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            report != null
                                ? 'DTCs: ${report.storedDtcs.length} stored • ${report.pendingDtcs.length} pending'
                                : 'No active fault codes',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Row(
                            children: [
                              Text(
                                'Tap to inspect & share',
                                style: TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              Icon(Icons.chevron_right_rounded, color: Color(0xFF00E676), size: 14),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 4. ANDROID AUTO ARCHITECTURAL BRIEFING CARD
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF13171F),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.blueAccent.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Android Auto & Sync Compatibility Note',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Android Auto operates via a high-speed local 5GHz Wi-Fi link. Chinese automotive headunits (Topway TS18 MCU) lock the Bluetooth radio to a single SPP channel (reserved for ELM327 telemetry). OBDrive synchronizes trips, blackbox logs, and parked car state over the existing Android Auto Wi-Fi network (Port 7355), delivering maximum speed without Bluetooth dropped packets.',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 11.5,
                          height: 1.4,
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
    );
  }
}
