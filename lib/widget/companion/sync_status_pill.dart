import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obdrive/services/sync/bluetooth_sync_service.dart';

/// Compact indicator pill showing Bluetooth / Wi-Fi synchronization state between
/// the Headunit and Phone companion.
/// Single-tap opens the Vehicle Link Modal; double-tap triggers haptic link test & sync.
class SyncStatusPill extends StatelessWidget {
  final SyncConnectionState connectionState;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final DateTime? lastSyncTime;

  const SyncStatusPill({
    super.key,
    required this.connectionState,
    this.onTap,
    this.onDoubleTap,
    this.lastSyncTime,
  });

  Color _getColor() {
    switch (connectionState) {
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

  String _getLabel() {
    switch (connectionState) {
      case SyncConnectionState.disconnected:
        return 'Disconnected';
      case SyncConnectionState.listening:
        return 'Listening...';
      case SyncConnectionState.connecting:
      case SyncConnectionState.syncing:
        return 'Syncing...';
      case SyncConnectionState.connected:
        return 'Connected';
      case SyncConnectionState.synced:
        return 'Synced';
      case SyncConnectionState.error:
        return 'Sync Error';
    }
  }

  bool get _isAnimated =>
      connectionState == SyncConnectionState.connecting ||
      connectionState == SyncConnectionState.syncing;

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final label = _getLabel();

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: 'Tap to view connection status, double-tap to sync',
        child: InkWell(
          key: const Key('sync_status_pill'),
          onTap: onTap,
          onDoubleTap: onDoubleTap != null
              ? () {
                  HapticFeedback.lightImpact();
                  onDoubleTap!();
                }
              : null,
          borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isAnimated)
                SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: color,
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

