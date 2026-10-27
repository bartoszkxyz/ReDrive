import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:obdrive/providers/sync_provider.dart';
import 'package:obdrive/services/sync/bluetooth_sync_service.dart';
import 'package:obdrive/services/sync/network_sync_manager.dart';

/// Modal bottom sheet providing deep Phone ↔ Headunit link inspection,
/// real-time TCP ping latency, 4-step automated diagnostic self-test,
/// and live vehicle vitals reported by the Headunit over Android Auto Wi-Fi.
class VehicleLinkModalSheet extends StatefulWidget {
  const VehicleLinkModalSheet({super.key});

  /// Displays the [VehicleLinkModalSheet] in a modal bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const VehicleLinkModalSheet(),
    );
  }

  @override
  State<VehicleLinkModalSheet> createState() => _VehicleLinkModalSheetState();
}

class _VehicleLinkModalSheetState extends State<VehicleLinkModalSheet> {
  bool _isRunningSelfTest = false;
  bool _isSyncing = false;
  LinkSelfTestReport? _selfTestReport;
  int? _pingLatencyMs;
  bool _isSubnetActive = false;
  bool _isLoadingInitialState = true;

  @override
  void initState() {
    super.initState();
    _checkInitialNetworkStatus();
  }

  Future<void> _checkInitialNetworkStatus() async {
    final syncProvider = context.read<SyncProvider>();
    final isSubnet = await syncProvider.isAndroidAutoSubnetActive();
    final ping = await syncProvider.pingHeadunit();

    if (mounted) {
      setState(() {
        _isSubnetActive = isSubnet;
        _pingLatencyMs = ping;
        _isLoadingInitialState = false;
      });
    }
  }

  Future<void> _showEditTargetDialog(BuildContext context, SyncProvider syncProvider) async {
    final controller = TextEditingController(
      text: syncProvider.networkSyncManager.activeTargetHost,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222A),
        title: const Text('Target Headunit IP', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your Headunit IP or pick a preset:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black26,
                hintText: '192.168.43.1',
                hintStyle: const TextStyle(color: Colors.white24),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Hotspot (.43.1)', style: TextStyle(fontSize: 11)),
                  onPressed: () => controller.text = '192.168.43.1',
                ),
                ActionChip(
                  label: const Text('Wi-Fi Direct (.49.1)', style: TextStyle(fontSize: 11)),
                  onPressed: () => controller.text = '192.168.49.1',
                ),
                ActionChip(
                  label: const Text('Carlinkit (.50.2)', style: TextStyle(fontSize: 11)),
                  onPressed: () => controller.text = '192.168.50.2',
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SAVE & PROBE'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      await syncProvider.setCustomTargetHost(controller.text.trim());
      setState(() => _isLoadingInitialState = true);
      await _checkInitialNetworkStatus();
    }
  }

  Future<void> _handleRunSelfTest() async {
    setState(() => _isRunningSelfTest = true);
    final syncProvider = context.read<SyncProvider>();
    try {
      final report = await syncProvider.runLinkSelfTest();
      if (mounted) {
        setState(() {
          _selfTestReport = report;
          _isRunningSelfTest = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunningSelfTest = false;
        });
      }
    }
  }

  Future<void> _handleSyncNow() async {
    setState(() => _isSyncing = true);
    final syncProvider = context.read<SyncProvider>();
    try {
      final success = await syncProvider.smartSyncWithHeadunit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Sync completed successfully!'
                : 'Sync timed out. Verify Headunit is awake and connected to Android Auto.',
          ),
          backgroundColor: success ? Colors.green : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync error: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Color _getConnectionColor(SyncConnectionState state) {
    switch (state) {
      case SyncConnectionState.disconnected:
        return Colors.grey;
      case SyncConnectionState.listening:
        return Colors.amber;
      case SyncConnectionState.connecting:
      case SyncConnectionState.syncing:
        return Colors.blueAccent;
      case SyncConnectionState.connected:
        return Colors.lightBlueAccent;
      case SyncConnectionState.synced:
        return Colors.greenAccent;
      case SyncConnectionState.error:
        return Colors.redAccent;
    }
  }

  String _formatSyncTime(DateTime? dt) {
    if (dt == null) return 'Never synced';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final syncProvider = context.watch<SyncProvider>();
    final connectionState = syncProvider.connectionState;
    final connColor = _getConnectionColor(connectionState);
    final snapshot = syncProvider.latestSnapshot;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF13171F),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.wifi_tethering_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Vehicle Link & Diagnostics',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ==========================================
                    // 1. Live Link Status Card
                    // ==========================================
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B222C),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: connColor.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: connColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        connectionState.name.toUpperCase(),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: connColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Subnet badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _isSubnetActive
                                      ? Colors.greenAccent.withValues(alpha: 0.15)
                                      : Colors.amberAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _isSubnetActive
                                        ? Colors.greenAccent.withValues(alpha: 0.4)
                                        : Colors.amberAccent.withValues(alpha: 0.4),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  _isSubnetActive
                                      ? '🚗 In-Car (Android Auto)'
                                      : '📱 Away / Cellular',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _isSubnetActive
                                        ? Colors.greenAccent
                                        : Colors.amberAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Ping latency & Gateway details
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        const Text(
                                          'Target Gateway',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.white54,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          key: const Key('edit_target_gateway_button'),
                                          onTap: () => _showEditTargetDialog(context, syncProvider),
                                          child: const Icon(
                                            Icons.edit_rounded,
                                            size: 13,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    GestureDetector(
                                      onTap: () => _showEditTargetDialog(context, syncProvider),
                                      child: Text(
                                        '${syncProvider.networkSyncManager.activeTargetHost}:${syncProvider.networkSyncManager.serverPort}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          decoration: TextDecoration.underline,
                                          decorationStyle: TextDecorationStyle.dotted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'TCP Ping Latency',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white54,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _isLoadingInitialState
                                          ? 'Probing...'
                                          : _pingLatencyMs != null
                                              ? '${_pingLatencyMs}ms (Online)'
                                              : 'Unreachable',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _pingLatencyMs != null
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          if (snapshot != null) ...[
                            const SizedBox(height: 14),
                            const Divider(color: Colors.white10),
                            const SizedBox(height: 8),
                            const Text(
                              'Reported Vehicle State',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white54,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                Text(
                                  'Battery: ${snapshot.batteryVoltage.toStringAsFixed(1)}V',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                                Text(
                                  'Fuel: ${snapshot.fuelLevelPercent.toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                                Text(
                                  'Odo: ${snapshot.odometerKm.toStringAsFixed(0)} km',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ==========================================
                    // 2. 4-Step Link Self-Test Panel
                    // ==========================================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Link Self-Test',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          key: const Key('run_self_test_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF263345),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _isRunningSelfTest ? null : _handleRunSelfTest,
                          icon: _isRunningSelfTest
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded, size: 16),
                          label: Text(
                            _isRunningSelfTest ? 'Testing...' : 'Run Test',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Self-test results or placeholder
                    if (_selfTestReport != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171D25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selfTestReport!.overallSuccess
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.redAccent.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            for (final step in _selfTestReport!.steps) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      step.status == LinkStepStatus.passed
                                          ? Icons.check_circle_rounded
                                          : step.status == LinkStepStatus.warning
                                              ? Icons.warning_amber_rounded
                                              : Icons.cancel_rounded,
                                      size: 18,
                                      color: step.status == LinkStepStatus.passed
                                          ? Colors.greenAccent
                                          : step.status == LinkStepStatus.warning
                                              ? Colors.amberAccent
                                              : Colors.redAccent,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            step.title,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            step.details,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white60,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (step.pingMs != null)
                                      Text(
                                        '${step.pingMs}ms',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            if (_selfTestReport!.diagnosticTip != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _selfTestReport!.overallSuccess
                                      ? Colors.green.withValues(alpha: 0.12)
                                      : Colors.amber.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _selfTestReport!.diagnosticTip!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _selfTestReport!.overallSuccess
                                        ? Colors.greenAccent
                                        : Colors.amberAccent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171D25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12, width: 1),
                        ),
                        child: const Text(
                          'Tap "Run Test" to sequentially verify Phone Wi-Fi, Android Auto subnet (192.168.43.x), Headunit socket ping, and frame handshake.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ==========================================
                    // 3. Actions Section
                    // ==========================================
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: Colors.white54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Last Sync: ${_formatSyncTime(syncProvider.lastSyncTime)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        key: const Key('link_sheet_sync_now_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isSyncing ? null : _handleSyncNow,
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.sync_rounded, size: 20),
                        label: Text(
                          _isSyncing ? 'Connecting & Syncing...' : 'Sync Now',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
