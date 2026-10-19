import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:redrive/providers/garage_provider.dart';
import 'package:redrive/providers/sync_provider.dart';
import 'package:redrive/screens/car_screen.dart';
import 'package:redrive/screens/companion/companion_settings_sheet.dart';
import 'package:redrive/screens/companion/companion_status_tab.dart';
import 'package:redrive/screens/diagnostics_screen.dart';
import 'package:redrive/screens/trips_screen.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';
import 'package:redrive/widget/companion/sync_status_pill.dart';
import 'package:redrive/widget/companion/vehicle_link_modal_sheet.dart';

/// Primary container screen for the OBDrive Phone Companion application.
/// Provides a 4-tab workflow: Status, Trips, Garage, and Diagnostics,
/// along with top vehicle switcher and headunit sync status controls.
class PhoneCompanionScreen extends StatefulWidget {
  const PhoneCompanionScreen({super.key});

  @override
  State<PhoneCompanionScreen> createState() => _PhoneCompanionScreenState();
}

class _PhoneCompanionScreenState extends State<PhoneCompanionScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndAutoSync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndAutoSync();
    }
  }

  void _checkAndAutoSync() async {
    if (!mounted) return;
    final syncProvider = context.read<SyncProvider>();
    if (syncProvider.connectionState == SyncConnectionState.disconnected ||
        syncProvider.connectionState == SyncConnectionState.error) {
      final isSubnet = await syncProvider.isAndroidAutoSubnetActive();
      if (isSubnet && mounted) {
        syncProvider.smartSyncWithHeadunit();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final garageProvider = context.watch<GarageProvider>();
    final syncProvider = context.watch<SyncProvider>();

    final activeProfile = garageProvider.activeProfile;
    final profiles = garageProvider.profiles.isNotEmpty
        ? garageProvider.profiles
        : [activeProfile];

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          // Top Header Bar
          SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Active Vehicle Switcher popup menu
                  Flexible(
                    child: PopupMenuButton<String>(
                      key: const Key('vehicle_switcher_button'),
                      tooltip: 'Select Vehicle',
                      onSelected: (profileId) async {
                        await garageProvider.selectActiveProfile(profileId);
                      },
                      itemBuilder: (context) {
                        return profiles.map((p) {
                          final isSelected = p.id == activeProfile.id;
                          return PopupMenuItem<String>(
                            value: p.id,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.directions_car_rounded,
                                  size: 18,
                                  color: isSelected
                                      ? colorScheme.primary
                                      : Colors.white70,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    p.name,
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? colorScheme.primary
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: colorScheme.primary,
                                  ),
                              ],
                            ),
                          );
                        }).toList();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                colorScheme.outlineVariant.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.directions_car_rounded,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                activeProfile.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 18,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Right: Sync status pill & Settings gear button
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SyncStatusPill(
                        key: const Key('companion_sync_pill'),
                        connectionState: syncProvider.connectionState,
                        lastSyncTime: syncProvider.lastSyncTime,
                        onTap: () => VehicleLinkModalSheet.show(context),
                        onDoubleTap: () => syncProvider.smartSyncWithHeadunit(),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        key: const Key('companion_settings_button'),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.settings_rounded, size: 22),
                        color: Colors.white70,
                        tooltip: 'Settings',
                        onPressed: () => CompanionSettingsSheet.show(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Body: 4 Screens Stack
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                CompanionStatusTab(
                  onNavigateTab: (index) =>
                      setState(() => _currentIndex = index),
                ),
                const TripsScreen(),
                const CarScreen(),
                const DiagnosticsScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0F1117),
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: Colors.white54,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car_rounded),
            label: 'Status',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.route_rounded),
            label: 'Trips',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.garage_rounded),
            label: 'Garage',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.health_and_safety_rounded),
            label: 'Diagnostics',
          ),
        ],
      ),
    );
  }
}
