import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/sync_models.dart';
import 'package:redrive/models/trip_anomaly.dart';

/// Modal bottom sheet displaying a comprehensive mechanic diagnostic report
/// including confirmed/pending DTCs, recent anomaly episodes, and vehicle telemetry.
class MechanicReportSheet extends StatelessWidget {
  final MechanicDiagnosticReport report;

  const MechanicReportSheet({
    super.key,
    required this.report,
  });

  /// Displays the [MechanicReportSheet] in a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required MechanicDiagnosticReport report,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MechanicReportSheet(report: report),
    );
  }

  static String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final month = (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $month ${dt.year}, $h:$m';
  }

  Future<void> _handleShare(BuildContext context) async {
    final summaryText = report.toFormattedTextSummary();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await Clipboard.setData(ClipboardData(text: summaryText));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;

    return Container(
      constraints: BoxConstraints(
        maxHeight: size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mechanic Diagnostic Report',
                        key: const Key('mechanic_report_title'),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${report.vehicle.name} • VIN: ${report.vehicle.vin ?? "N/A"} • ${_formatDate(report.generatedAt)}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: colorScheme.onSurfaceVariant,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Scrollable Body
          Flexible(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Summary Stats Row
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryBadge(
                        label: 'Stored DTCs',
                        count: report.storedDtcs.length,
                        color: report.storedDtcs.isNotEmpty
                            ? Colors.redAccent
                            : Colors.greenAccent,
                        colorScheme: colorScheme,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSummaryBadge(
                        label: 'Pending DTCs',
                        count: report.pendingDtcs.length,
                        color: report.pendingDtcs.isNotEmpty
                            ? Colors.orangeAccent
                            : Colors.greenAccent,
                        colorScheme: colorScheme,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSummaryBadge(
                        label: 'Anomalies',
                        count: report.recentAnomalies.length,
                        color: report.recentAnomalies.isNotEmpty
                            ? Colors.amberAccent
                            : Colors.greenAccent,
                        colorScheme: colorScheme,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Vehicle & Odometer Info Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Odometer',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${report.currentOdometerKm.toStringAsFixed(1)} km',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Fuel Type',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            report.vehicle.fuelType.label,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Stored DTCs Section
                _buildSectionTitle(
                  title: 'Confirmed Trouble Codes (Mode 03)',
                  count: report.storedDtcs.length,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),
                if (report.storedDtcs.isEmpty)
                  _buildEmptyState('No stored DTCs detected.', colorScheme)
                else
                  ...report.storedDtcs.map((dtc) => _buildDtcItem(dtc, colorScheme)),

                const SizedBox(height: 20),

                // Pending DTCs Section
                _buildSectionTitle(
                  title: 'Pending Trouble Codes (Mode 07)',
                  count: report.pendingDtcs.length,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),
                if (report.pendingDtcs.isEmpty)
                  _buildEmptyState('No pending DTCs detected.', colorScheme)
                else
                  ...report.pendingDtcs.map((dtc) => _buildDtcItem(dtc, colorScheme)),

                const SizedBox(height: 20),

                // Anomaly Episodes Section
                _buildSectionTitle(
                  title: 'Recent Anomaly Episodes',
                  count: report.recentAnomalies.length,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),
                if (report.recentAnomalies.isEmpty)
                  _buildEmptyState('No anomalies detected.', colorScheme)
                else
                  ...report.recentAnomalies
                      .map((anom) => _buildAnomalyItem(anom, colorScheme)),

                // Latest Parked Telemetry (if available)
                if (report.latestSnapshot != null) ...[
                  const SizedBox(height: 20),
                  _buildSectionTitle(
                    title: 'Latest Parked Telemetry',
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),
                  _buildSnapshotInfo(report.latestSnapshot!, colorScheme),
                ],
              ],
            ),
          ),

          // Bottom Share Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('mechanic_report_share_button'),
                icon: const Icon(Icons.share_rounded, size: 20),
                label: const Text('Share Diagnostic Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () => _handleShare(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBadge({
    required String label,
    required int count,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required String title,
    int? count,
    required ColorScheme colorScheme,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState(String message, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildDtcItem(DtcCode dtc, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dtc.isPending
              ? Colors.orangeAccent.withValues(alpha: 0.3)
              : Colors.redAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dtc.code,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (dtc.severity.toLowerCase() == 'critical'
                          ? Colors.redAccent
                          : Colors.orangeAccent)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dtc.severity,
                  style: TextStyle(
                    color: dtc.severity.toLowerCase() == 'critical'
                        ? Colors.redAccent
                        : Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dtc.description,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          if (dtc.possibleCauses.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Possible Causes: ${dtc.possibleCauses}',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnomalyItem(TripAnomalyEpisode anom, ColorScheme colorScheme) {
    final severityColor = anom.severity == AnomalySeverity.problem
        ? Colors.redAccent
        : Colors.amberAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: severityColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  anom.title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  anom.severity.name.toUpperCase(),
                  style: TextStyle(
                    color: severityColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            anom.description,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotInfo(
    ParkedCarSnapshot snapshot,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Battery Voltage: ${snapshot.batteryVoltage.toStringAsFixed(2)} V',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Fuel: ${snapshot.remainingFuelLiters.toStringAsFixed(1)} L (${snapshot.fuelLevelPercent.toStringAsFixed(0)}%)',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Est. Range: ~${snapshot.estimatedRangeKm.toStringAsFixed(0)} km',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (snapshot.hasCoordinates)
                Text(
                  'GPS: ${snapshot.latitude!.toStringAsFixed(4)}, ${snapshot.longitude!.toStringAsFixed(4)}',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
