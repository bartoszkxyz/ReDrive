import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/custom_dashboard_theme.dart';
import '../../core/theme/theme_engine.dart';
import '../../services/headunit/native_app_launcher_service.dart';

/// Tactile Automotive Dock providing instant one-tap access to primary TS18 headunit applications:
/// TLINK5 (CarPlay/Android Auto), Radio, DSP/EQ, HD DVR, and the full App Drawer.
class TactileLauncherDock extends StatelessWidget {
  final NativeAppLauncherService launcherService;

  TactileLauncherDock({
    super.key,
    NativeAppLauncherService? launcherService,
  }) : launcherService = launcherService ?? NativeAppLauncherService();

  void _openAppDrawer(BuildContext context, CustomThemeColors colors) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AppDrawerSheet(
        launcherService: launcherService,
        colors: colors,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeEngine = context.watch<ThemeEngine?>();
    final colors = themeEngine?.colors ?? const CustomThemeColors();

    return Container(
      key: const Key('tactile_launcher_dock'),
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: colors.textMuted.withValues(alpha: 0.15),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. TLINK5 (CarPlay / Android Auto)
          Expanded(
            child: _TactileDockButton(
              key: const Key('dock_launch_tlink'),
              icon: Icons.phone_android_rounded,
              label: 'TLINK5',
              subLabel: 'CarPlay & Auto',
              accentColor: colors.primaryAccent,
              onTap: () {
                HapticFeedback.lightImpact();
                launcherService.launchTlink();
              },
            ),
          ),
          const SizedBox(width: 8),

          // 2. RADIO
          Expanded(
            child: _TactileDockButton(
              key: const Key('dock_launch_radio'),
              icon: Icons.radio_rounded,
              label: 'RADIO',
              subLabel: 'FM / AM Tuner',
              accentColor: colors.secondaryAccent,
              onTap: () {
                HapticFeedback.lightImpact();
                launcherService.launchRadio();
              },
            ),
          ),
          const SizedBox(width: 8),

          // 3. DSP / EQ
          Expanded(
            child: _TactileDockButton(
              key: const Key('dock_launch_dsp'),
              icon: Icons.equalizer_rounded,
              label: 'DSP / EQ',
              subLabel: 'Audio Tuning',
              accentColor: colors.primaryAccent,
              onTap: () {
                HapticFeedback.lightImpact();
                launcherService.launchDsp();
              },
            ),
          ),
          const SizedBox(width: 8),

          // 4. HD DVR
          Expanded(
            child: _TactileDockButton(
              key: const Key('dock_launch_dvr'),
              icon: Icons.videocam_rounded,
              label: 'HD DVR',
              subLabel: 'Dashcam Live',
              accentColor: const Color(0xFF00E676),
              onTap: () {
                HapticFeedback.lightImpact();
                launcherService.launchDvr();
              },
            ),
          ),
          const SizedBox(width: 8),

          // 5. ALL APPS
          Expanded(
            child: _TactileDockButton(
              key: const Key('dock_launch_app_drawer'),
              icon: Icons.apps_rounded,
              label: 'ALL APPS',
              subLabel: 'App Drawer',
              accentColor: colors.textMain,
              onTap: () => _openAppDrawer(context, colors),
            ),
          ),
        ],
      ),
    );
  }
}

class _TactileDockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subLabel;
  final Color accentColor;
  final VoidCallback onTap;

  const _TactileDockButton({
    super.key,
    required this.icon,
    required this.label,
    required this.subLabel,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: accentColor.withValues(alpha: 0.2),
        highlightColor: accentColor.withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.25),
              width: 1.2,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accentColor.withValues(alpha: 0.12),
                Colors.black.withValues(alpha: 0.25),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 26,
                color: accentColor,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  subLabel,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppDrawerSheet extends StatefulWidget {
  final NativeAppLauncherService launcherService;
  final CustomThemeColors colors;

  const _AppDrawerSheet({
    required this.launcherService,
    required this.colors,
  });

  @override
  State<_AppDrawerSheet> createState() => _AppDrawerSheetState();
}

class _AppDrawerSheetState extends State<_AppDrawerSheet> {
  late Future<List<DiscoveredAppInfo>> _appsFuture;

  @override
  void initState() {
    super.initState();
    _appsFuture = widget.launcherService.getInstalledApps();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      key: const Key('app_drawer_sheet'),
      height: screenHeight * 0.85,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: colors.primaryAccent.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Drag Handle & Header
          Center(
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.apps_rounded,
                    color: colors.primaryAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'INSTALLED APPLICATIONS',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: colors.textMain,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                color: colors.textMuted,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 20, thickness: 1),
          // Apps Grid
          Expanded(
            child: FutureBuilder<List<DiscoveredAppInfo>>(
              future: _appsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final apps = snapshot.data ?? [];
                if (apps.isEmpty) {
                  return Center(
                    child: Text(
                      'No applications discovered',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: colors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  );
                }

                return GridView.builder(
                  key: const Key('app_drawer_grid'),
                  itemCount: apps.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.75,
                  ),
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    return InkWell(
                      key: Key('app_item_${app.packageName}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        widget.launcherService.launchApp(
                          app.packageName,
                          activityName: app.activityName,
                        );
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        decoration: BoxDecoration(
                          color: colors.background.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.textMuted.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.primaryAccent.withValues(alpha: 0.15),
                                border: Border.all(
                                  color: colors.primaryAccent.withValues(alpha: 0.4),
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  app.label.isNotEmpty
                                      ? app.label[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: colors.primaryAccent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Center(
                                child: Text(
                                  app.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textMain,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
