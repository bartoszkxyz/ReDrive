import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dtc_code.dart';
import '../models/live_sensor_item.dart';
import '../models/sync_models.dart';
import '../models/vehicle_profile.dart';
import '../obd/pid/pid_key.dart';
import '../obd/pid/pid_registry.dart';
import '../obd/polling/polling_controller.dart';
import '../providers/obd_provider.dart';
import '../providers/sync_provider.dart';
import '../services/dtc/dtc_service.dart';
import '../services/sensor/sensor_statistics_service.dart';
import '../widget/companion/mechanic_report_sheet.dart';

enum DiagnosticTabMode { dtc, liveSensors }

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  DiagnosticTabMode _mode = DiagnosticTabMode.dtc;

  final DtcService _dtcService = DtcService();
  final SensorStatisticsService _statsService = SensorStatisticsService();

  bool _isScanningDtc = false;
  bool _hasScannedDtc = false;
  List<DtcCode> _dtcResults = [];
  String? _dtcErrorMessage;

  String _selectedCategory = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<String> _categories = [
    'All',
    'Engine',
    'Air & Fuel',
    'Temperatures',
    'Electrical',
  ];

  bool _isFullScanActive = false;
  ObdProvider? _obdProvider;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyWatchlist();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _obdProvider = context.read<ObdProvider>();
  }

  void _applyWatchlist() {
    final obd = _obdProvider ?? (mounted ? context.read<ObdProvider>() : null);
    if (obd == null) return;
    if (_isFullScanActive) {
      final allAvailable = obd.supportedKeys.isNotEmpty
          ? {...obd.supportedKeys, PidKey.adapterVoltage}
          : PidRegistry().allKeys;
      obd.setWatchlist(WatchSource.visibleScreen, allAvailable);
    } else {
      obd.setWatchlist(WatchSource.visibleScreen, PidRegistry.coreKeys);
    }
  }

  @override
  void dispose() {
    // Release screen watchlist so background polling stops when user leaves diagnostics
    _obdProvider?.clearWatchlist(WatchSource.visibleScreen);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleScanDtc(ObdProvider obdProvider) async {
    setState(() {
      _isScanningDtc = true;
      _dtcErrorMessage = null;
    });

    try {
      final codes = await _dtcService.scanAllCodes(obdProvider);
      if (!mounted) return;
      setState(() {
        _isScanningDtc = false;
        _hasScannedDtc = true;
        _dtcResults = codes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanningDtc = false;
        _dtcErrorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleClearDtc(ObdProvider obdProvider) async {
    // 1. Pre-flight safety check
    final isVehicleMoving = obdProvider.mode == ObdMode.real &&
        (obdProvider.data.speed > 0 || obdProvider.data.rpm > 0);

    if (isVehicleMoving) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Vehicle must be stationary with engine stopped before clearing trouble codes (${obdProvider.data.speed} km/h, ${obdProvider.data.rpm} RPM).',
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    // 2. User confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B222C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text('Clear Fault Codes?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will send OBD Mode 04 to clear all active trouble codes, reset freeze frame memory, and extinguish the Check Engine Light (MIL).\n\nEnsure repairs have been completed before clearing.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Codes'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _isScanningDtc = true;
    });

    try {
      final success = await _dtcService.clearAllCodes(obdProvider);

      if (!mounted) return;

      setState(() {
        _isScanningDtc = false;
        if (success) {
          _dtcResults = [];
          _hasScannedDtc = true;
          _dtcErrorMessage = null;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Fault codes cleared successfully.'
                : 'Failed to clear codes from ECU.',
          ),
          backgroundColor: success ? Colors.green : Colors.redAccent,
        ),
      );
    } on DtcSafetyException catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanningDtc = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Safety interlock: Vehicle must be stationary with engine stopped (${e.speed} km/h, ${e.rpm} RPM).',
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanningDtc = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanningDtc = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing codes: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleShareMechanicReport(BuildContext context) async {
    SyncProvider? syncProvider;
    try {
      syncProvider = context.read<SyncProvider>();
    } catch (_) {
      syncProvider = null;
    }

    final stored = _dtcResults.where((d) => !d.isPending).toList();
    final pending = _dtcResults.where((d) => d.isPending).toList();

    final MechanicDiagnosticReport report;
    if (syncProvider != null) {
      report = await syncProvider.generateMechanicReport(
        storedDtcs: stored,
        pendingDtcs: pending,
      );
    } else {
      report = MechanicDiagnosticReport(
        reportId: 'rep_${DateTime.now().millisecondsSinceEpoch}',
        generatedAt: DateTime.now(),
        vehicle: VehicleProfile.defaultSuzukiSwiftM15A(),
        currentOdometerKm: 150000.0,
        storedDtcs: stored,
        pendingDtcs: pending,
      );
    }

    if (!context.mounted) return;
    MechanicReportSheet.show(context, report: report);
  }

  @override
  Widget build(BuildContext context) {
    final obdProvider = context.watch<ObdProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    // Update sensor stats in real-time
    _statsService.updateFromData(obdProvider.data);
    _statsService.updateFromValues(obdProvider.latestPidValues);

    final isDemo = obdProvider.mode == ObdMode.demo;
    final isConnected = obdProvider.isEcuConnected || isDemo;

    String statusText = 'OFFLINE';
    Color statusColor = Colors.grey;

    if (obdProvider.isEcuConnected) {
      statusText = 'LIVE OBD';
      statusColor = colorScheme.primary;
    } else if (isDemo) {
      statusText = 'DEMO MODE';
      statusColor = Colors.amber;
    }

    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 850;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            if (isWide)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Diagnostics',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.8,
                          ),
                        ),
                        Text(
                          'ECU CODES & LIVE SENSORS',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 420),
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() => _mode = DiagnosticTabMode.dtc),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _mode == DiagnosticTabMode.dtc
                                          ? colorScheme.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          size: 16,
                                          color: _mode == DiagnosticTabMode.dtc
                                              ? colorScheme.onPrimary
                                              : Colors.white70,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            'Fault Codes (DTC)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: _mode == DiagnosticTabMode.dtc
                                                  ? colorScheme.onPrimary
                                                  : Colors.white70,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() => _mode = DiagnosticTabMode.liveSensors),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _mode == DiagnosticTabMode.liveSensors
                                          ? colorScheme.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.insights_rounded,
                                          size: 16,
                                          color: _mode == DiagnosticTabMode.liveSensors
                                              ? colorScheme.onPrimary
                                              : Colors.white70,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            'Live Sensors',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: _mode == DiagnosticTabMode.liveSensors
                                                  ? colorScheme.onPrimary
                                                  : Colors.white70,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Diagnostics',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSurface,
                              letterSpacing: -0.8,
                            ),
                          ),
                          Text(
                            'ECU CODES & LIVE SENSORS',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
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

              // Mode Selector Segmented Control
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _mode = DiagnosticTabMode.dtc),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _mode == DiagnosticTabMode.dtc
                                  ? colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: _mode == DiagnosticTabMode.dtc
                                      ? colorScheme.onPrimary
                                      : Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Fault Codes (DTC)',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: _mode == DiagnosticTabMode.dtc
                                          ? colorScheme.onPrimary
                                          : Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _mode = DiagnosticTabMode.liveSensors),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _mode == DiagnosticTabMode.liveSensors
                                  ? colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.insights_rounded,
                                  size: 16,
                                  color: _mode == DiagnosticTabMode.liveSensors
                                      ? colorScheme.onPrimary
                                      : Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Live Sensors',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: _mode == DiagnosticTabMode.liveSensors
                                          ? colorScheme.onPrimary
                                          : Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Content Body
            Expanded(
              child: _mode == DiagnosticTabMode.dtc
                  ? _buildDtcView(obdProvider, isConnected)
                  : _buildLiveSensorsView(obdProvider),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // DTC VIEW
  // -------------------------------------------------------------
  Widget _buildDtcView(ObdProvider obdProvider, bool isConnected) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 850;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: isWide ? 6.0 : 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Action Buttons Card
          Container(
            padding: EdgeInsets.all(isWide ? 12 : 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: isWide
                ? Row(
                    children: [
                      ElevatedButton.icon(
                        icon: _isScanningDtc
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.search_rounded),
                        label: Text(_isScanningDtc ? 'Scanning ECU...' : 'Scan For Codes'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isScanningDtc || !isConnected
                            ? null
                            : () => _handleScanDtc(obdProvider),
                      ),
                      if (_dtcResults.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 20),
                          label: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent, width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isScanningDtc || !isConnected
                              ? null
                              : () => _handleClearDtc(obdProvider),
                        ),
                      ],
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        key: const Key('generate_mechanic_report_button'),
                        icon: const Icon(Icons.assignment_outlined, size: 20),
                        label: const Text('Share Mechanic Report'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.6)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _handleShareMechanicReport(context),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          isConnected
                              ? 'Direct ECU OBD query (Mode 03 confirmed & Mode 07 pending).'
                              : 'Connect to OBD device or enable Demo Mode to scan vehicle trouble codes.',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: isConnected ? 0.7 : 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              icon: _isScanningDtc
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                    )
                                  : const Icon(Icons.search_rounded),
                              label: Text(_isScanningDtc ? 'Scanning ECU...' : 'Scan For Codes'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isScanningDtc || !isConnected
                                  ? null
                                  : () => _handleScanDtc(obdProvider),
                            ),
                          ),
                          if (_dtcResults.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 20),
                                label: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.redAccent, width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: _isScanningDtc || !isConnected
                                    ? null
                                    : () => _handleClearDtc(obdProvider),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const Key('generate_mechanic_report_button'),
                          icon: const Icon(Icons.assignment_outlined, size: 20),
                          label: const Text('Share Mechanic Report'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.primary,
                            side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.6)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _handleShareMechanicReport(context),
                        ),
                      ),
                      if (!isConnected) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Connect to OBD device or enable Demo Mode to scan vehicle trouble codes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                        ),
                      ],
                    ],
                  ),
          ),

          SizedBox(height: isWide ? 12 : 16),

          // Scan Error Message
          if (_dtcErrorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.redAccent, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _dtcErrorMessage!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Results Section
          if (_isScanningDtc) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Communicating with ECU (Mode 03 & Mode 07)...',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (!_hasScannedDtc) ...[
            // Prompt to scan
            Container(
              padding: EdgeInsets.symmetric(vertical: isWide ? 22 : 40, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF141A23),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: isWide
                  ? Row(
                      children: [
                        Icon(Icons.directions_car_outlined, size: 44, color: Colors.white.withValues(alpha: 0.3)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ready to Diagnose',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Press "Scan For Codes" above to query all active confirmed and pending diagnostic trouble codes.',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Icon(Icons.directions_car_outlined, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        const Text(
                          'Ready to Diagnose',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Press "Scan For Codes" above to query all active confirmed and pending diagnostic trouble codes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                        ),
                      ],
                    ),
            ),
          ] else if (_dtcResults.isEmpty) ...[
            // Zero codes found (Clean ECU)
            Container(
              padding: EdgeInsets.all(isWide ? 18 : 24),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4), width: 1.5),
              ),
              child: isWide
                  ? Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No Fault Codes Detected',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Your vehicle ECU reported zero stored or pending diagnostic trouble codes. All monitored powertrain subsystems are operating normally.',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : const Column(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.green, size: 54),
                        SizedBox(height: 12),
                        Text(
                          'No Fault Codes Detected',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Your vehicle ECU reported zero stored or pending diagnostic trouble codes. All monitored powertrain subsystems are operating normally.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
            ),
          ] else ...[
            // Codes Found Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_dtcResults.length} FAULT CODE${_dtcResults.length > 1 ? "S" : ""} FOUND',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.redAccent,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'Mode 03 / 07',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // List of DTC Cards (2 columns on landscape/wide)
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        for (int i = 0; i < _dtcResults.length; i += 2)
                          _buildDtcCard(_dtcResults[i]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        for (int i = 1; i < _dtcResults.length; i += 2)
                          _buildDtcCard(_dtcResults[i]),
                      ],
                    ),
                  ),
                ],
              )
            else
              ..._dtcResults.map((code) => _buildDtcCard(code)),
          ],
        ],
      ),
    );
  }

  Widget _buildDtcCard(DtcCode dtc) {
    Color tagColor = Colors.orangeAccent;
    if (dtc.severity == 'Critical') {
      tagColor = Colors.redAccent;
    } else if (dtc.isPending) {
      tagColor = Colors.blueAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151C25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tagColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tagColor, width: 1),
                ),
                child: Text(
                  dtc.code,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: tagColor,
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      dtc.system.toUpperCase(),
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (dtc.isPending) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PENDING',
                        style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            dtc.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            dtc.description,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Symptoms: ', style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(dtc.symptoms, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Causes: ', style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(dtc.possibleCauses, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // LIVE SENSORS VIEW
  // -------------------------------------------------------------
  Widget _buildLiveSensorsView(ObdProvider obdProvider) {
    final colorScheme = Theme.of(context).colorScheme;

    final Set<PidKey>? allowedKeys = _isFullScanActive
        ? (obdProvider.supportedKeys.isNotEmpty
            ? {...obdProvider.supportedKeys, PidKey.adapterVoltage}
            : null)
        : PidRegistry.coreKeys;

    final sensors = _statsService.getFilteredSensors(
      category: _selectedCategory,
      query: _searchQuery,
      allowedKeys: allowedKeys,
    );

    final totalAvailable = obdProvider.supportedKeys.isNotEmpty
        ? obdProvider.supportedKeys.length + 1
        : _statsService.getAllSensors().length;

    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 850;

    final fullScanToggleWidget = Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: isWide ? 8 : 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isFullScanActive
              ? colorScheme.primary.withValues(alpha: 0.6)
              : Colors.white10,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (_isFullScanActive ? colorScheme.primary : Colors.white24)
                  .withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isFullScanActive ? Icons.radar : Icons.speed,
              color: _isFullScanActive ? colorScheme.primary : Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Full Sensor Scan',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: isWide ? 13 : 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (_isFullScanActive ? colorScheme.primary : Colors.white24)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isFullScanActive ? 'ALL CHANNELS' : 'CORE ONLY',
                        style: TextStyle(
                          color: _isFullScanActive
                              ? colorScheme.primary
                              : Colors.white60,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _isFullScanActive
                      ? 'Polling all $totalAvailable available vehicle sensors in real-time.'
                      : 'Monitoring 8 core sensors at high refresh rate (~1.0s).',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isFullScanActive,
            activeTrackColor: colorScheme.primary,
            onChanged: (bool val) {
              setState(() {
                _isFullScanActive = val;
                _applyWatchlist();
              });
            },
          ),
        ],
      ),
    );

    final searchFieldWidget = TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search sensors by name or unit...',
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: colorScheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (val) => setState(() => _searchQuery = val),
    );

    return Column(
      children: [
        if (isWide)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(flex: 5, child: fullScanToggleWidget),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: searchFieldWidget),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: fullScanToggleWidget,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: searchFieldWidget,
          ),
        ],

        const SizedBox(height: 8),

        // Category Pills
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                    backgroundColor: colorScheme.surfaceContainer,
                    selectedColor: colorScheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? colorScheme.onPrimary : Colors.white70,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    side: BorderSide.none,
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        SizedBox(height: isWide ? 8 : 12),

        // Live Sensors List / Grid
        Expanded(
          child: sensors.isEmpty
              ? Center(
                  child: Text(
                    'No sensors match "$_searchQuery"',
                    style: const TextStyle(color: Colors.white54),
                  ),
                )
              : isWide
                  ? GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent: 118,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: sensors.length,
                      itemBuilder: (context, index) =>
                          _buildLiveSensorCard(sensors[index], isWide: true),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      itemCount: sensors.length,
                      itemBuilder: (context, index) =>
                          _buildLiveSensorCard(sensors[index], isWide: false),
                    ),
        ),
      ],
    );
  }

  Widget _buildLiveSensorCard(LiveSensorItem sensor, {bool isWide = false}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: EdgeInsets.only(bottom: isWide ? 0 : 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141A23),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            sensor.category.toUpperCase(),
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sensor.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  sensor.formattedValue,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: colorScheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Mini progress gauge
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: sensor.progressPercentage,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              minHeight: 4,
            ),
          ),

          const SizedBox(height: 8),

          // Statistics footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                sensor.statsSummary,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontFamily: 'Inter',
                ),
              ),
              Text(
                'Samples: ${sensor.sampleCount}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
