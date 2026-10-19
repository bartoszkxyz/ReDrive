import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/obd/source/obd_source_state.dart';
import 'package:redrive/providers/bluetooth_provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/widget/connection/bluetooth/bluetooth_tab.dart';
import 'package:redrive/widget/settings/obd_adapter_test_sheet.dart';

/// Comprehensive OBD-II (ELM327) Operations Center widget.
///
/// Provides:
/// 1. Prominent manual Connect / Disconnect and Demo mode controls.
/// 2. Real-time telemetry connection status (ECU polling, adapter state, voltage, RPM).
/// 3. One-tap interactive OBD adapter diagnostic handshake test (`ObdAdapterTestSheet`).
/// 4. Protocol selector for vehicle-specific timing (Suzuki ATSP5 KWP / CAN).
/// 5. Discovered & Paired Bluetooth devices list.
class ObdOperationsPanel extends StatefulWidget {
  const ObdOperationsPanel({super.key});

  @override
  State<ObdOperationsPanel> createState() => _ObdOperationsPanelState();
}

class _ObdOperationsPanelState extends State<ObdOperationsPanel> {
  bool _isConnectingManual = false;

  Future<void> _handleManualConnect(
    BuildContext context,
    BluetoothProvider btProvider,
    ObdProvider obdProvider,
  ) async {
    HapticFeedback.mediumImpact();
    setState(() => _isConnectingManual = true);

    try {
      if (!btProvider.isConnected) {
        final ok = await btProvider.autoConnectLastDevice(
          settleDelay: Duration.zero,
          maxAttempts: 3,
        );
        if (!ok && btProvider.discoveredDevices.isNotEmpty) {
          await btProvider.connectToDevice(btProvider.discoveredDevices.first);
        }
      }

      if (context.mounted && (btProvider.isConnected || obdProvider.isDeviceConnected)) {
        await obdProvider.startRealMode();
      }
    } finally {
      if (mounted) {
        setState(() => _isConnectingManual = false);
      }
    }
  }

  Future<void> _handleManualDisconnect(
    ObdProvider obdProvider,
    BluetoothProvider btProvider,
  ) async {
    HapticFeedback.mediumImpact();
    await obdProvider.stopRealMode();
    await btProvider.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final btProvider = context.watch<BluetoothProvider>();
    final obdProvider = context.watch<ObdProvider>();
    final l = AppLocalizations.of(context);

    final isEcuPolling = obdProvider.isEcuConnected;
    final isDeviceConnected = btProvider.isConnected || obdProvider.isDeviceConnected;
    final isDemoMode = obdProvider.mode == ObdMode.demo;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. HERO MANUAL CONNECTION & OPERATIONS CARD
          _buildHeroConnectionCard(
            context: context,
            colorScheme: colorScheme,
            btProvider: btProvider,
            obdProvider: obdProvider,
            isEcuPolling: isEcuPolling,
            isDeviceConnected: isDeviceConnected,
            isDemoMode: isDemoMode,
            l: l,
          ),

          const SizedBox(height: 14),

          // 2. DIAGNOSTIC TOOLING & PROTOCOL SELECTOR ROW
          Row(
            children: [
              // Adapter Handshake Test Tool Button
              Expanded(
                flex: 5,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const Key('run_adapter_test_button'),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      showObdAdapterTestSheet(context, obdProvider);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF00E676).withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.speed_rounded,
                              color: Color(0xFF00E676),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Test OBD Adapter',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'ATZ / ATRV / 0100 Test',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Protocol Selector Card
              const Expanded(
                flex: 5,
                child: ProtocolSelectorCard(),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 3. SCANNER / DEVICE DISCOVERY PANEL
          BluetoothScanStatusCard(onRefresh: () => btProvider.startScan()),

          const SizedBox(height: 10),

          Container(
            height: 260,
            decoration: BoxDecoration(
              color: const Color(0xFF131315),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BluetoothDeviceList(onScan: () => btProvider.startScan()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroConnectionCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required BluetoothProvider btProvider,
    required ObdProvider obdProvider,
    required bool isEcuPolling,
    required bool isDeviceConnected,
    required bool isDemoMode,
    required AppLocalizations l,
  }) {
    final statusColor = isEcuPolling
        ? const Color(0xFF00E676)
        : (isDemoMode
            ? Colors.purpleAccent
            : (isDeviceConnected
                ? colorScheme.primary
                : (btProvider.isConnecting || obdProvider.state == ObdSourceState.connecting
                    ? Colors.amber
                    : Colors.white38)));

    final statusText = isEcuPolling
        ? 'ECU Polling Active (Mode 01)'
        : (isDemoMode
            ? 'Demo Simulator Active'
            : (isDeviceConnected
                ? 'Adapter Connected (Ready)'
                : (btProvider.isConnecting || obdProvider.state == ObdSourceState.connecting
                    ? 'Connecting to ELM327...'
                    : 'Disconnected')));

    final deviceName = btProvider.connectedDevice?.name ?? 'Bluetooth ELM327';
    final deviceAddress = btProvider.connectedDevice?.address ?? 'No device paired';
    final voltage = obdProvider.data.voltage > 0
        ? '${obdProvider.data.voltage.toStringAsFixed(1)} V'
        : '-- V';
    final rpm = obdProvider.data.rpm > 0 ? '${obdProvider.data.rpm} RPM' : '-- RPM';

    return Container(
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
          // Header Row: Status badge & Live telemetry pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.6),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              if (isEcuPolling || isDemoMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        voltage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(' • ', style: TextStyle(color: Colors.white38)),
                      Text(
                        rpm,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // Device Details
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.bluetooth_connected_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      deviceAddress,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Action Buttons: Manual Connect + Demo Mode
          Row(
            children: [
              // Main Manual Connect/Disconnect Button
              Expanded(
                flex: 6,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    key: const Key('manual_obd_connect_button'),
                    onPressed: _isConnectingManual
                        ? null
                        : () {
                            if (isEcuPolling || isDeviceConnected) {
                              _handleManualDisconnect(obdProvider, btProvider);
                            } else {
                              _handleManualConnect(context, btProvider, obdProvider);
                            }
                          },
                    icon: _isConnectingManual
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Icon(
                            isEcuPolling || isDeviceConnected
                                ? Icons.power_settings_new_rounded
                                : Icons.play_arrow_rounded,
                            size: 22,
                            color: isEcuPolling || isDeviceConnected
                                ? Colors.white
                                : Colors.black,
                          ),
                    label: Text(
                      isEcuPolling || isDeviceConnected
                          ? 'DISCONNECT OBD'
                          : 'CONNECT TO OBD',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: isEcuPolling || isDeviceConnected
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isEcuPolling || isDeviceConnected
                          ? const Color(0xFFD32F2F)
                          : colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Demo Mode Switcher
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    key: const Key('manual_obd_demo_button'),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      if (isDemoMode) {
                        obdProvider.stopDemoMode();
                      } else {
                        obdProvider.startDemoMode();
                      }
                    },
                    icon: Icon(
                      isDemoMode ? Icons.stop_rounded : Icons.smart_toy_rounded,
                      size: 20,
                      color: isDemoMode ? Colors.purpleAccent : Colors.white70,
                    ),
                    label: Text(
                      isDemoMode ? 'STOP DEMO' : 'DEMO MODE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: isDemoMode ? Colors.purpleAccent : Colors.white70,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isDemoMode
                            ? Colors.purpleAccent
                            : colorScheme.outlineVariant.withValues(alpha: 0.35),
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
    );
  }
}
