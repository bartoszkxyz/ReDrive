import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obdrive/models/dtc_code.dart';
import 'package:obdrive/models/sync_models.dart';
import 'package:obdrive/models/trip_anomaly.dart';

/// Modal bottom sheet displaying a comprehensive mechanic diagnostic report
/// including confirmed/pending DTCs, recent anomaly episodes, and vehicle telemetry.
class MechanicReportSheet extends StatefulWidget {
  final MechanicDiagnosticReport report;
  final String? initialLanguage;

  const MechanicReportSheet({
    super.key,
    required this.report,
    this.initialLanguage,
  });

  /// Displays the [MechanicReportSheet] in a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required MechanicDiagnosticReport report,
    String? initialLanguage,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MechanicReportSheet(
        report: report,
        initialLanguage: initialLanguage,
      ),
    );
  }

  @override
  State<MechanicReportSheet> createState() => _MechanicReportSheetState();
}

class _MechanicReportSheetState extends State<MechanicReportSheet> {
  late String _selectedLanguage;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.initialLanguage ??
        (WidgetsBinding.instance.platformDispatcher.locale.languageCode
                    .toLowerCase() ==
                'pl'
            ? 'pl'
            : 'en');
  }

  bool get _isPl => _selectedLanguage == 'pl';

  static String _formatDate(DateTime dt, {bool isPl = false}) {
    final enMonths = [
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
    final plMonths = [
      'sty',
      'lut',
      'mar',
      'kwi',
      'maj',
      'cze',
      'lip',
      'sie',
      'wrz',
      'paź',
      'lis',
      'gru'
    ];
    final months = isPl ? plMonths : enMonths;
    final month = (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $month ${dt.year}, $h:$m';
  }

  Future<void> _handleShare(BuildContext context) async {
    final summaryText =
        widget.report.toFormattedTextSummary(language: _selectedLanguage);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isPl
              ? 'Skopiowano raport do schowka'
              : 'Report copied to clipboard',
        ),
        duration: const Duration(seconds: 2),
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
                        _isPl
                            ? 'Raport Diagnostyczny Pojazdu'
                            : 'Mechanic Diagnostic Report',
                        key: const Key('mechanic_report_title'),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.report.vehicle.name} • VIN: ${widget.report.vehicle.vin ?? (_isPl ? "Brak danych" : "N/A")} • ${_formatDate(widget.report.generatedAt, isPl: _isPl)}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<String>(
                      key: const Key('mechanic_report_language_toggle'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: const [
                        ButtonSegment<String>(
                          value: 'en',
                          label: Text(
                            'EN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ButtonSegment<String>(
                          value: 'pl',
                          label: Text(
                            'PL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      selected: {_selectedLanguage},
                      onSelectionChanged: (newSelection) {
                        if (newSelection.isNotEmpty) {
                          setState(() {
                            _selectedLanguage = newSelection.first;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: colorScheme.onSurfaceVariant,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
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
                        label: _isPl ? 'Zapisane DTC' : 'Stored DTCs',
                        count: widget.report.storedDtcs.length,
                        color: widget.report.storedDtcs.isNotEmpty
                            ? Colors.redAccent
                            : Colors.greenAccent,
                        colorScheme: colorScheme,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSummaryBadge(
                        label: _isPl ? 'Oczekujące DTC' : 'Pending DTCs',
                        count: widget.report.pendingDtcs.length,
                        color: widget.report.pendingDtcs.isNotEmpty
                            ? Colors.orangeAccent
                            : Colors.greenAccent,
                        colorScheme: colorScheme,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSummaryBadge(
                        label: _isPl ? 'Anomalie' : 'Anomalies',
                        count: widget.report.recentAnomalies.length,
                        color: widget.report.recentAnomalies.isNotEmpty
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
                            _isPl ? 'Przebieg całkowity' : 'Current Odometer',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.report.currentOdometerKm.toStringAsFixed(1)} km',
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
                            _isPl ? 'Rodzaj paliwa' : 'Fuel Type',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isPl
                                ? MechanicDiagnosticReport.fuelTypeToPl(
                                    widget.report.vehicle.fuelType)
                                : widget.report.vehicle.fuelType.label,
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
                  title: _isPl
                      ? 'Potwierdzone kody błędów (Tryb 03)'
                      : 'Confirmed Trouble Codes (Mode 03)',
                  count: widget.report.storedDtcs.length,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),
                if (widget.report.storedDtcs.isEmpty)
                  _buildEmptyState(
                    _isPl
                        ? 'Brak zapisanych kodów DTC.'
                        : 'No stored DTCs detected.',
                    colorScheme,
                  )
                else
                  ...widget.report.storedDtcs
                      .map((dtc) => _buildDtcItem(dtc, colorScheme)),

                const SizedBox(height: 20),

                // Pending DTCs Section
                _buildSectionTitle(
                  title: _isPl
                      ? 'Oczekujące kody błędów (Tryb 07)'
                      : 'Pending Trouble Codes (Mode 07)',
                  count: widget.report.pendingDtcs.length,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),
                if (widget.report.pendingDtcs.isEmpty)
                  _buildEmptyState(
                    _isPl
                        ? 'Brak oczekujących kodów DTC.'
                        : 'No pending DTCs detected.',
                    colorScheme,
                  )
                else
                  ...widget.report.pendingDtcs
                      .map((dtc) => _buildDtcItem(dtc, colorScheme)),

                const SizedBox(height: 20),

                // Anomaly Episodes Section
                _buildSectionTitle(
                  title: _isPl
                      ? 'Ostatnie wykryte anomalie'
                      : 'Recent Anomaly Episodes',
                  count: widget.report.recentAnomalies.length,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),
                if (widget.report.recentAnomalies.isEmpty)
                  _buildEmptyState(
                    _isPl
                        ? 'Brak wykrytych anomalii.'
                        : 'No anomalies detected.',
                    colorScheme,
                  )
                else
                  ...widget.report.recentAnomalies
                      .map((anom) => _buildAnomalyItem(anom, colorScheme)),

                // Latest Parked Telemetry (if available)
                if (widget.report.latestSnapshot != null) ...[
                  const SizedBox(height: 20),
                  _buildSectionTitle(
                    title: _isPl
                        ? 'Ostatnia telemetria postoju'
                        : 'Latest Parked Telemetry',
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 8),
                  _buildSnapshotInfo(
                    widget.report.latestSnapshot!,
                    colorScheme,
                  ),
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
                label: Text(
                  _isPl
                      ? 'Udostępnij raport diagnostyczny'
                      : 'Share Diagnostic Report',
                ),
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
                  _isPl
                      ? MechanicDiagnosticReport.severityToPl(dtc.severity)
                      : dtc.severity,
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
              _isPl
                  ? 'Możliwe przyczyny / zalecane kroki: ${dtc.possibleCauses}'
                  : 'Possible Causes: ${dtc.possibleCauses}',
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
                  _isPl
                      ? MechanicDiagnosticReport.severityToPl(anom.severity.name)
                          .toUpperCase()
                      : anom.severity.name.toUpperCase(),
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
                _isPl
                    ? 'Napięcie akumulatora: ${snapshot.batteryVoltage.toStringAsFixed(2)} V'
                    : 'Battery Voltage: ${snapshot.batteryVoltage.toStringAsFixed(2)} V',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _isPl
                    ? 'Pozostałe paliwo: ${snapshot.remainingFuelLiters.toStringAsFixed(1)} L (${snapshot.fuelLevelPercent.toStringAsFixed(0)}%)'
                    : 'Fuel: ${snapshot.remainingFuelLiters.toStringAsFixed(1)} L (${snapshot.fuelLevelPercent.toStringAsFixed(0)}%)',
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
                _isPl
                    ? 'Szacowany zasięg: ~${snapshot.estimatedRangeKm.toStringAsFixed(0)} km'
                    : 'Est. Range: ~${snapshot.estimatedRangeKm.toStringAsFixed(0)} km',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (snapshot.hasCoordinates)
                Text(
                  _isPl
                      ? 'Pozycja GPS: ${snapshot.latitude!.toStringAsFixed(4)}, ${snapshot.longitude!.toStringAsFixed(4)}'
                      : 'GPS: ${snapshot.latitude!.toStringAsFixed(4)}, ${snapshot.longitude!.toStringAsFixed(4)}',
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
