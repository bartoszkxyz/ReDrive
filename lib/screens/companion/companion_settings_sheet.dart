import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:redrive/core/theme/custom_dashboard_theme.dart';
import 'package:redrive/providers/sync_provider.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';
import 'package:redrive/widget/companion/mechanic_report_sheet.dart';

/// Modal bottom sheet for Headunit Bluetooth synchronization, theme sideloading,
/// and comprehensive mechanic diagnostic report generation.
class CompanionSettingsSheet extends StatefulWidget {
  const CompanionSettingsSheet({super.key});

  /// Displays the [CompanionSettingsSheet] in a modal bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const CompanionSettingsSheet(),
    );
  }

  @override
  State<CompanionSettingsSheet> createState() => _CompanionSettingsSheetState();
}

class _CompanionSettingsSheetState extends State<CompanionSettingsSheet> {
  late CustomDashboardTheme _selectedTheme;
  bool _isSendingTheme = false;

  final List<CustomDashboardTheme> _themePresets = [
    CustomDashboardTheme.amberGlow(),
    CustomDashboardTheme.cyanCyber(),
    CustomDashboardTheme.emeraldDrive(),
    CustomDashboardTheme.monochromeDark(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedTheme = _themePresets.first;
  }

  String _formatSyncTime(DateTime? dt) {
    if (dt == null) return 'Never synced';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} $h:$m';
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

  Future<void> _handleSendTheme(SyncProvider syncProvider) async {
    setState(() => _isSendingTheme = true);
    try {
      final success = await syncProvider.pushCustomTheme(_selectedTheme);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Theme "${_selectedTheme.name}" sent to Headunit!'
                : 'Failed to push theme (headunit unreachable).',
          ),
          backgroundColor: success ? Colors.green : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error pushing theme: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingTheme = false);
      }
    }
  }

  Future<void> _handleOpenMechanicReport(SyncProvider syncProvider) async {
    final report = syncProvider.latestMechanicReport ??
        await syncProvider.generateMechanicReport();
    if (!mounted) return;
    await MechanicReportSheet.show(context, report: report);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final syncProvider = context.watch<SyncProvider>();
    final connectionState = syncProvider.connectionState;
    final connColor = _getConnectionColor(connectionState);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
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
                          Icons.settings_suggest_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Headunit Sync & Settings',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
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
                    // 1. Vehicle Link & Sync Card
                    // ==========================================
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B222C),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: connColor.withValues(alpha: 0.3),
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
                                    const Icon(
                                      Icons.wifi_tethering_rounded,
                                      size: 18,
                                      color: Colors.lightBlueAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Vehicle Link (Android Auto)',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Status badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: connColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: connColor.withValues(alpha: 0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  connectionState.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: connColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              Icon(
                                Icons.router_rounded,
                                size: 14,
                                color: Colors.white54,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Target: 192.168.43.1:7355',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Last Sync: ${_formatSyncTime(syncProvider.lastSyncTime)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              key: const Key('companion_sync_now_button'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => syncProvider.smartSyncWithHeadunit(),
                              icon: const Icon(Icons.sync_rounded, size: 18),
                              label: const Text(
                                'Sync Now',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ==========================================
                    // 2. Storage & Retention Policy
                    // ==========================================
                    const Text(
                      'Storage & Blackbox Retention',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Configure retention duration for high-frequency blackbox data and driving records.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B222C),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white12,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Raw 1 Hz Blackbox Logs (.jsonl)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              (14, '14 Days'),
                              (30, '30 Days'),
                              (90, '90 Days'),
                              (0, 'Keep Forever'),
                            ].map((entry) {
                              final isSelected = syncProvider.rawBlackboxRetentionDays == entry.$1;
                              return ChoiceChip(
                                label: Text(entry.$2),
                                selected: isSelected,
                                selectedColor: colorScheme.primary.withValues(alpha: 0.25),
                                backgroundColor: const Color(0xFF13171F),
                                onSelected: (selected) {
                                  if (selected) {
                                    syncProvider.updateRetentionSettings(rawBlackboxDays: entry.$1);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                          const Divider(color: Colors.white10),
                          const SizedBox(height: 10),
                          const Text(
                            'Trip Summaries & Routes (History)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              (365, '1 Year'),
                              (730, '2 Years'),
                              (0, 'Keep Forever'),
                            ].map((entry) {
                              final isSelected = syncProvider.tripSummaryRetentionDays == entry.$1;
                              return ChoiceChip(
                                label: Text(entry.$2),
                                selected: isSelected,
                                selectedColor: colorScheme.primary.withValues(alpha: 0.25),
                                backgroundColor: const Color(0xFF13171F),
                                onSelected: (selected) {
                                  if (selected) {
                                    syncProvider.updateRetentionSettings(tripSummaryDays: entry.$1);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 14, color: Colors.white54),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Trip summaries average ~4 KB/drive (~1.4 MB for 6 months).',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ==========================================
                    // 2. Theme Sideloading Section
                    // ==========================================
                    const Text(
                      'Theme Sideloading',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose a dashboard aesthetic preset and beam it directly to your headunit cockpit over Bluetooth.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _themePresets.map((preset) {
                        final isSelected = _selectedTheme.id == preset.id;
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: preset.colors.primaryAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(preset.name),
                            ],
                          ),
                          selected: isSelected,
                          selectedColor: preset.colors.primaryAccent
                              .withValues(alpha: 0.25),
                          backgroundColor: const Color(0xFF1B222C),
                          side: BorderSide(
                            color: isSelected
                                ? preset.colors.primaryAccent
                                : Colors.white12,
                            width: 1.5,
                          ),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? preset.colors.primaryAccent
                                : Colors.white70,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedTheme = preset);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('send_theme_button'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _selectedTheme.colors.primaryAccent,
                          side: BorderSide(
                            color: _selectedTheme.colors.primaryAccent,
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isSendingTheme
                            ? null
                            : () => _handleSendTheme(syncProvider),
                        icon: _isSendingTheme
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _selectedTheme.colors.primaryAccent,
                                ),
                              )
                            : const Icon(Icons.send_to_mobile_rounded, size: 18),
                        label: Text(
                          'Send Theme to Headunit',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ==========================================
                    // 3. Diagnostics Section
                    // ==========================================
                    const Text(
                      'Diagnostics & Mechanic Report',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'View confirmed/pending trouble codes, anomaly history, and share a diagnostic export with your mechanic.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        key: const Key('open_mechanic_report_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF232D3B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(
                            color: Colors.white24,
                            width: 1,
                          ),
                        ),
                        onPressed: () => _handleOpenMechanicReport(syncProvider),
                        icon: const Icon(
                          Icons.medical_services_outlined,
                          color: Colors.orangeAccent,
                          size: 18,
                        ),
                        label: const Text(
                          'Open Mechanic Diagnostic Report',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
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
