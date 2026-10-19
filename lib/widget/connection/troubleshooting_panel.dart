import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/widget/settings/log_viewer_sheet.dart';
import 'package:redrive/widget/settings/obd_adapter_test_sheet.dart';

/// Diagnostics & Troubleshooting Panel for in-car and mobile connection issues.
class TroubleshootingPanel extends StatelessWidget {
  const TroubleshootingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final obdProvider = context.watch<ObdProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. QUICK DIAGNOSTIC TOOLS ROW
          Row(
            children: [
              // Test OBD Adapter Button
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const Key('troubleshoot_test_obd_button'),
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
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.speed_rounded, color: Color(0xFF00E676), size: 24),
                          SizedBox(height: 8),
                          Text(
                            'Run OBD Test',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'ATZ, ATE0, 0100 verification',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // View System Logs Button
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const Key('troubleshoot_view_logs_button'),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      showLogViewerSheet(context);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.blueAccent.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.terminal_rounded, color: Colors.blueAccent, size: 24),
                          SizedBox(height: 8),
                          Text(
                            'View App Logs',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Blackbox live terminal',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 2. OBD-II CONNECTION CHECKLIST
          _buildChecklistCard(
            title: 'OBD-II (ELM327) Connection Checklist',
            icon: Icons.directions_car_rounded,
            accentColor: colorScheme.primary,
            steps: const [
              'Ensure vehicle ignition is in the ON position or the engine is running (OBD port Pin 16 power).',
              'Check that the power LED on your ELM327 adapter is lit.',
              'Chinese headunit pairing: Open the system Bluetooth app (com.tw.bt) on the headunit and pair with PIN 1234 or 0000.',
              'For Suzuki Swift M15A: Ensure the protocol is set to "Suzuki Swift M15A (ATSP5 KWP)" in the OBD tab.',
              'If the connection hangs, run "Run OBD Test" above to check ELM327 firmware responses.',
            ],
          ),

          const SizedBox(height: 14),

          // 3. ANDROID AUTO & SYNC CHECKLIST
          _buildChecklistCard(
            title: 'Phone Companion & Android Auto Sync Checklist',
            icon: Icons.sync_rounded,
            accentColor: const Color(0xFF00E676),
            steps: const [
              'Ensure Android Auto (ZLink / TLINK5) is connected and operating on the car screen.',
              'When Android Auto connects, your phone automatically links to the headunit\'s 5GHz Wi-Fi network.',
              'Open the OBDrive Companion app on your phone.',
              'Verify the target Headunit IP in Phone Sync is 192.168.43.1 (default Android Auto gateway).',
              'Tap "SYNC NOW" to pull trips, GPS route polylines, and parked car location from the headunit.',
            ],
          ),

          const SizedBox(height: 14),

          // 4. POWER LIFECYCLE INFO
          _buildChecklistCard(
            title: 'Automatic Ignition Lifecycle',
            icon: Icons.power_settings_new_rounded,
            accentColor: Colors.amber,
            steps: const [
              'Ignition ON (ACC_ON): OBDrive waits 2.5s for starter motor voltage stabilization, then automatically connects to your paired adapter.',
              'Ignition OFF (ACC_OFF): The app automatically finalizes the active trip, persists GPS timeseries to disk, captures parked car GPS coordinates, and cleanly closes the Bluetooth channel.',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required List<String> steps,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF13171F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final text = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$idx',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
