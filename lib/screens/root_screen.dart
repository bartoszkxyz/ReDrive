import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/screens/car_screen.dart';
import 'package:redrive/screens/connection_screen.dart';
import 'package:redrive/widget/bottom_bar/custom_bottom_bar.dart';
import 'package:redrive/widget/common/reconnection_banner.dart';
import 'package:redrive/screens/dashboard_screen.dart';
import 'package:redrive/core/app_flavor.dart';
import 'package:redrive/screens/headunit_launcher_screen.dart';
import 'package:redrive/screens/settings_screen.dart';
import 'home_screen.dart';
import 'dart:async';

import 'package:redrive/screens/trips_screen.dart';
import 'package:redrive/screens/diagnostics_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _currentIndex = 0;
  StreamSubscription<Object>? _errorsSubscription;

  late final List<Widget> _screens = [
    if (AppConfig.isHeadunit)
      HeadunitLauncherScreen(
        onOpenDashboard: () => setState(() => _currentIndex = 1),
        onOpenTrips: () => setState(() => _currentIndex = 4),
        onOpenSettings: () => showSettingsSheet(context),
      )
    else
      const HomeScreen(),
    const DashboardScreen(),
    const ConnectionScreen(),
    const CarScreen(),
    const TripsScreen(),
    const DiagnosticsScreen(),
  ];

  @override
  void initState() {
    super.initState();

    _errorsSubscription = context.read<ObdProvider>().errors.listen((_) {
      if (!mounted) return;

      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.connectionLost)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final stage = context.select<ObdProvider, ObdRecoveryStage>(
      (p) => p.recoveryStage,
    );
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _screens),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: switch (stage) {
                    ObdRecoveryStage.none => const SizedBox.shrink(),
                    ObdRecoveryStage.session => ReconnectionBanner(
                      message: l.bannerRestoring,
                    ),
                    ObdRecoveryStage.transport => ReconnectionBanner(
                      message: l.bannerReconnecting,
                    ),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: (AppConfig.isHeadunit && _currentIndex == 0)
          ? null
          : CustomBottomBar(
              currentIndex: _currentIndex,
              onItemSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
            ),
    );
  }

  @override
  void dispose() {
    _errorsSubscription?.cancel();
    super.dispose();
  }
}
