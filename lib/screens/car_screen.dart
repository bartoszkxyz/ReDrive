import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/providers/garage_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/services/garage/garage_service.dart';

/// Main screen displaying vehicle garage profiles, active vehicle specifications,
/// maintenance checklists, and vehicle configuration editing.
class CarScreen extends StatefulWidget {
  const CarScreen({super.key});

  @override
  State<CarScreen> createState() => _CarScreenState();
}

/// Backward compatibility alias for CarScreen.
typedef GarageScreen = CarScreen;

class _CarScreenState extends State<CarScreen> {
  // Graceful fallback state for standalone testing or contexts without GarageProvider
  GarageState _localState = GarageState.defaultState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    GarageProvider? garageProvider;
    try {
      garageProvider = context.watch<GarageProvider>();
    } catch (_) {
      garageProvider = null;
    }

    TripProvider? tripProvider;
    try {
      tripProvider = context.watch<TripProvider>();
    } catch (_) {
      tripProvider = null;
    }

    final profiles = garageProvider?.profiles ?? _localState.profiles;
    final activeProfile =
        garageProvider?.activeProfile ?? _localState.activeProfile;
    final totalDistance = tripProvider?.totalDistance ?? 0.0;
    final activeEffectiveOdo =
        activeProfile.effectiveOdometerKm(totalDistance);

    AppLocalizations? l;
    try {
      l = Localizations.of<AppLocalizations>(context, AppLocalizations);
    } catch (_) {
      l = null;
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, l, garageProvider),
              const SizedBox(height: 20),
              _buildVehicleList(
                context,
                profiles: profiles,
                activeProfileId: activeProfile.id,
                totalDistance: totalDistance,
                garageProvider: garageProvider,
              ),
              const SizedBox(height: 28),
              _buildMaintenanceSection(
                context,
                activeProfile: activeProfile,
                effectiveOdo: activeEffectiveOdo,
                garageProvider: garageProvider,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations? l,
    GarageProvider? garageProvider,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleText = l?.garageTitle ?? 'Garage';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titleText,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'VEHICLE PROFILES & MAINTENANCE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          key: const Key('garage_add_vehicle_button'),
          onPressed: () => _openVehicleEditorModal(context, garageProvider: garageProvider),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('+ Add Vehicle'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleList(
    BuildContext context, {
    required List<VehicleProfile> profiles,
    required String activeProfileId,
    required double totalDistance,
    required GarageProvider? garageProvider,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final profile in profiles) ...[
          _VehicleCard(
            key: Key('vehicle_card_${profile.id}'),
            profile: profile,
            isActive: profile.id == activeProfileId,
            effectiveOdo: profile.effectiveOdometerKm(totalDistance),
            canDelete: profiles.length > 1,
            onSelect: () => _selectActiveProfile(profile.id, garageProvider),
            onEdit: () => _openVehicleEditorModal(
              context,
              existingProfile: profile,
              garageProvider: garageProvider,
            ),
            onDelete: () => _deleteProfile(profile.id, garageProvider),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildMaintenanceSection(
    BuildContext context, {
    required VehicleProfile activeProfile,
    required double effectiveOdo,
    required GarageProvider? garageProvider,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = activeProfile.maintenanceItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.build_circle_outlined, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'MAINTENANCE TRACKER',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Center(
              child: Text(
                'No maintenance items scheduled for this vehicle.',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          )
        else
          for (final item in items) ...[
            _MaintenanceCard(
              item: item,
              effectiveOdo: effectiveOdo,
              onServiceDone: () => _markMaintenanceDone(
                maintenanceItemId: item.id,
                atOdometerKm: effectiveOdo,
                garageProvider: garageProvider,
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  void _selectActiveProfile(String profileId, GarageProvider? garageProvider) {
    if (garageProvider != null) {
      garageProvider.selectActiveProfile(profileId);
    } else {
      setState(() {
        _localState = _localState.copyWith(activeProfileId: profileId);
      });
    }
  }

  void _deleteProfile(String profileId, GarageProvider? garageProvider) {
    if (garageProvider != null) {
      garageProvider.deleteProfile(profileId);
    } else {
      final remaining =
          _localState.profiles.where((p) => p.id != profileId).toList();
      if (remaining.isNotEmpty) {
        final newActiveId =
            remaining.any((p) => p.id == _localState.activeProfileId)
                ? _localState.activeProfileId
                : remaining.first.id;
        setState(() {
          _localState = GarageState(
            profiles: remaining,
            activeProfileId: newActiveId,
          );
        });
      }
    }
  }

  void _markMaintenanceDone({
    required String maintenanceItemId,
    required double atOdometerKm,
    required GarageProvider? garageProvider,
  }) {
    if (garageProvider != null) {
      garageProvider.markMaintenanceServiced(
        maintenanceItemId: maintenanceItemId,
        atOdometerKm: atOdometerKm,
      );
    } else {
      final active = _localState.activeProfile;
      final updatedItems = active.maintenanceItems.map((item) {
        if (item.id == maintenanceItemId) {
          return item.markServiced(
            atOdometerKm: atOdometerKm,
            atDate: DateTime.now(),
          );
        }
        return item;
      }).toList();
      final updatedProfile =
          active.copyWith(maintenanceItems: updatedItems);
      final updatedProfiles = _localState.profiles
          .map((p) => p.id == updatedProfile.id ? updatedProfile : p)
          .toList();
      setState(() {
        _localState = _localState.copyWith(profiles: updatedProfiles);
      });
    }
  }

  void _openVehicleEditorModal(
    BuildContext context, {
    VehicleProfile? existingProfile,
    GarageProvider? garageProvider,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return _VehicleEditorModal(
          existingProfile: existingProfile,
          garageProvider: garageProvider,
          onSave: (savedProfile) async {
            if (garageProvider != null) {
              await garageProvider.saveProfile(
                savedProfile,
                setAsActive: true,
              );
            } else {
              final profiles =
                  List<VehicleProfile>.from(_localState.profiles);
              final idx =
                  profiles.indexWhere((p) => p.id == savedProfile.id);
              if (idx >= 0) {
                profiles[idx] = savedProfile;
              } else {
                profiles.add(savedProfile);
              }
              setState(() {
                _localState = GarageState(
                  profiles: profiles,
                  activeProfileId: savedProfile.id,
                );
              });
            }
          },
        );
      },
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final VehicleProfile profile;
  final bool isActive;
  final double effectiveOdo;
  final bool canDelete;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VehicleCard({
    super.key,
    required this.profile,
    required this.isActive,
    required this.effectiveOdo,
    required this.canDelete,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final String displayName;
    if (profile.year != null && !profile.name.endsWith('• ${profile.year}')) {
      displayName = '${profile.name} • ${profile.year}';
    } else {
      displayName = profile.name;
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: isActive ? null : onSelect,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Actions Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayName,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (isActive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: colorScheme.primary,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (profile.vin != null && profile.vin!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              'VIN: ${profile.vin}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      key: Key('edit_vehicle_${profile.id}'),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit Vehicle',
                      onPressed: onEdit,
                    ),
                    if (canDelete)
                      IconButton(
                        key: Key('delete_vehicle_${profile.id}'),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        tooltip: 'Delete Vehicle',
                        onPressed: onDelete,
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // Core Specs Badges
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildSpecBadge(
                      context,
                      'ENGINE',
                      '${profile.displacementLiters.toStringAsFixed(1)}L',
                    ),
                    _buildSpecBadge(
                      context,
                      'FUEL',
                      profile.fuelType.label,
                    ),
                    _buildSpecBadge(
                      context,
                      'TANK',
                      '${profile.fuelTankCapacityLiters.toStringAsFixed(0)}L',
                    ),
                    _buildSpecBadge(
                      context,
                      'POWER',
                      '${profile.maxHorsepower} HP',
                    ),
                    _buildSpecBadge(
                      context,
                      'REDLINE',
                      '${profile.redlineRpm} RPM',
                    ),
                    _buildSpecBadge(
                      context,
                      'OVERHEAT',
                      '${profile.coolantOverheatTempC}°C',
                    ),
                    _buildSpecBadge(
                      context,
                      'ODOMETER',
                      '${effectiveOdo.toStringAsFixed(0)} km',
                    ),
                  ],
                ),

                if (!isActive) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      key: Key('select_vehicle_${profile.id}'),
                      onPressed: onSelect,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        side: BorderSide(color: colorScheme.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                      ),
                      child: const Text('Select'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecBadge(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceCard extends StatelessWidget {
  final MaintenanceItem item;
  final double effectiveOdo;
  final VoidCallback onServiceDone;

  const _MaintenanceCard({
    required this.item,
    required this.effectiveOdo,
    required this.onServiceDone,
  });

  String _formatInterval(double km) {
    final str = km.toStringAsFixed(0);
    final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return str.replaceAll(reg, ',');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final isOverdue = item.isOverdue(effectiveOdo);
    final isDueSoon = item.isDueSoon(effectiveOdo);
    final statusText = isOverdue
        ? 'OVERDUE'
        : (isDueSoon ? 'DUE SOON' : 'OK');
    final statusColor = isOverdue
        ? Colors.redAccent
        : (isDueSoon ? Colors.orangeAccent : colorScheme.primary);

    final remaining = item.remainingKm(effectiveOdo);
    final progress = item.progress(effectiveOdo).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Every ${_formatInterval(item.intervalKm)} km',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor, width: 1),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${remaining.toStringAsFixed(0)} km remaining',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              ElevatedButton.icon(
                key: Key('service_done_${item.id}'),
                onPressed: onServiceDone,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Service Done'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.onSurface,
                  side: BorderSide(color: colorScheme.outlineVariant),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
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

class _VehicleEditorModal extends StatefulWidget {
  final VehicleProfile? existingProfile;
  final GarageProvider? garageProvider;
  final Future<void> Function(VehicleProfile profile) onSave;

  const _VehicleEditorModal({
    this.existingProfile,
    this.garageProvider,
    required this.onSave,
  });

  @override
  State<_VehicleEditorModal> createState() => _VehicleEditorModalState();
}

class _VehicleEditorModalState extends State<_VehicleEditorModal> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _vinController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _displacementController = TextEditingController();
  final TextEditingController _tankController = TextEditingController();
  final TextEditingController _odometerController = TextEditingController();
  final TextEditingController _idleThrottleController = TextEditingController();
  final TextEditingController _redlineController = TextEditingController();
  final TextEditingController _shiftRpmController = TextEditingController();
  final TextEditingController _overheatController = TextEditingController();
  final TextEditingController _hpController = TextEditingController();
  final TextEditingController _curbWeightController = TextEditingController();

  FuelType _fuelType = FuelType.gasoline;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProfile;
    if (p != null) {
      _nameController.text = p.name;
      _vinController.text = p.vin ?? '';
      _yearController.text = p.year != null ? p.year.toString() : '';
      _displacementController.text = p.displacementLiters.toString();
      _fuelType = p.fuelType;
      _tankController.text = p.fuelTankCapacityLiters.toString();
      _odometerController.text = p.baseOdometerKm.toString();
      _idleThrottleController.text = p.idleThrottleBaselinePercent.toString();
      _redlineController.text = p.redlineRpm.toString();
      _shiftRpmController.text = p.optimalShiftRpm.toString();
      _overheatController.text = p.coolantOverheatTempC.toString();
      _hpController.text = p.maxHorsepower.toString();
      _curbWeightController.text =
          p.curbWeightKg != null ? p.curbWeightKg.toString() : '';
      _urlController.text = p.sourceAutoDataUrl ?? '';
    } else {
      _displacementController.text = '1.5';
      _tankController.text = '45';
      _odometerController.text = '0';
      _idleThrottleController.text = '13.0';
      _redlineController.text = '6500';
      _shiftRpmController.text = '3200';
      _overheatController.text = '102';
      _hpController.text = '102';
      _curbWeightController.text = '1015';
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _vinController.dispose();
    _yearController.dispose();
    _displacementController.dispose();
    _tankController.dispose();
    _odometerController.dispose();
    _idleThrottleController.dispose();
    _redlineController.dispose();
    _shiftRpmController.dispose();
    _overheatController.dispose();
    _hpController.dispose();
    _curbWeightController.dispose();
    super.dispose();
  }

  Future<void> _handleAutoFill() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) return;

    GarageProvider? provider = widget.garageProvider;
    if (provider == null) {
      try {
        provider = context.read<GarageProvider>();
      } catch (_) {}
    }

    if (provider == null) return;

    final specs = await provider.parseAutoDataUrl(rawUrl);
    if (!mounted) return;

    if (specs != null) {
      final autoName = (specs.title != null && specs.title!.isNotEmpty)
          ? specs.title!
          : ('${specs.brand ?? ''} ${specs.model ?? ''} ${specs.engineModification ?? ''}'
              .trim());
      if (autoName.isNotEmpty) {
        _nameController.text = autoName;
      }
      if (specs.year != null) {
        _yearController.text = specs.year.toString();
      }
      if (specs.displacementLiters != null) {
        _displacementController.text = specs.displacementLiters.toString();
      }
      if (specs.fuelTypeKey != null) {
        setState(() {
          _fuelType = FuelType.fromString(specs.fuelTypeKey);
        });
      }
      if (specs.fuelTankCapacityLiters != null) {
        _tankController.text = specs.fuelTankCapacityLiters.toString();
      }
      if (specs.maxHorsepower != null) {
        _hpController.text = specs.maxHorsepower.toString();
      }
      if (specs.redlineRpm != null) {
        _redlineController.text = specs.redlineRpm.toString();
      }
      if (specs.curbWeightKg != null) {
        _curbWeightController.text = specs.curbWeightKg.toString();
      }
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final existing = widget.existingProfile;

      final nameInput = _nameController.text.trim();
      final name = nameInput.isNotEmpty
          ? nameInput
          : (existing?.name ?? 'My Vehicle');

      final vinInput = _vinController.text.trim();
      final vin = vinInput.isNotEmpty ? vinInput : null;

      final year = int.tryParse(_yearController.text.trim()) ?? existing?.year;
      final displacement =
          double.tryParse(_displacementController.text.trim()) ??
              (existing?.displacementLiters ?? 1.5);
      final tank = double.tryParse(_tankController.text.trim()) ??
          (existing?.fuelTankCapacityLiters ?? 45.0);
      final odo = double.tryParse(_odometerController.text.trim()) ??
          (existing?.baseOdometerKm ?? 0.0);
      final idleThrottle =
          double.tryParse(_idleThrottleController.text.trim()) ??
              (existing?.idleThrottleBaselinePercent ?? 13.0);
      final redline = int.tryParse(_redlineController.text.trim()) ??
          (existing?.redlineRpm ?? 6500);
      final shiftRpm = int.tryParse(_shiftRpmController.text.trim()) ??
          (existing?.optimalShiftRpm ?? 3200);
      final overheat = int.tryParse(_overheatController.text.trim()) ??
          (existing?.coolantOverheatTempC ?? 102);
      final hp = int.tryParse(_hpController.text.trim()) ??
          (existing?.maxHorsepower ?? 102);
      final curbWeight = int.tryParse(_curbWeightController.text.trim()) ??
          existing?.curbWeightKg;
      final urlInput = _urlController.text.trim();
      final sourceUrl =
          urlInput.isNotEmpty ? urlInput : existing?.sourceAutoDataUrl;

      final id = existing?.id ?? 'veh_${DateTime.now().millisecondsSinceEpoch}';
      final maintenanceItems = existing != null
          ? existing.maintenanceItems
          : VehicleProfile.defaultMaintenanceItems(baseOdometerKm: odo);

      final newProfile = VehicleProfile(
        id: id,
        name: name,
        vin: vin,
        year: year,
        displacementLiters: displacement,
        fuelType: _fuelType,
        fuelTankCapacityLiters: tank,
        idleThrottleBaselinePercent: idleThrottle,
        redlineRpm: redline,
        optimalShiftRpm: shiftRpm,
        coolantOverheatTempC: overheat,
        maxHorsepower: hp,
        curbWeightKg: curbWeight,
        baseOdometerKm: odo,
        sourceAutoDataUrl: sourceUrl,
        maintenanceItems: maintenanceItems,
      );

      await widget.onSave(newProfile);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    GarageProvider? provider = widget.garageProvider;
    if (provider == null) {
      try {
        provider = context.watch<GarageProvider>();
      } catch (_) {}
    }

    final isParsing = provider?.isParsingUrl ?? false;
    final parseError = provider?.urlParseError;
    final isEditing = widget.existingProfile != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 20,
        left: 20,
        right: 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'Edit Vehicle Profile' : 'Add New Vehicle',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Auto-Data URL Paste Bar
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AUTO-DATA.NET SPEC IMPORT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('autodata_url_input'),
                            controller: _urlController,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Paste https://www.auto-data.net/en/... URL',
                              hintStyle: TextStyle(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                                fontSize: 13,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: colorScheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const Key('autodata_fetch_button'),
                          onPressed: isParsing ? null : _handleAutoFill,
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: isParsing
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : const Text('Auto-Fill'),
                        ),
                      ],
                    ),
                    if (parseError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        parseError,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Manual Vehicle Details Form
              Text(
                'VEHICLE SPECIFICATIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              _buildInputField(
                label: 'Vehicle Name',
                key: const Key('vehicle_name_input'),
                controller: _nameController,
                hint: 'e.g. Suzuki Swift 3 (M15A 1.5L)',
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'Year',
                      key: const Key('vehicle_year_input'),
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      hint: '2007',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildInputField(
                      label: 'VIN (Optional)',
                      key: const Key('vehicle_vin_input'),
                      controller: _vinController,
                      hint: '17 characters',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'Displacement (Liters)',
                      key: const Key('vehicle_displacement_input'),
                      controller: _displacementController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      hint: '1.5',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fuel Type',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        InputDecorator(
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainer,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<FuelType>(
                              key: const Key('vehicle_fuel_type_dropdown'),
                              value: _fuelType,
                              isDense: true,
                              isExpanded: true,
                              dropdownColor: colorScheme.surfaceContainer,
                              items: FuelType.values.map((f) {
                                return DropdownMenuItem(
                                  value: f,
                                  child: Text(
                                    f.label,
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 14,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _fuelType = val);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'Fuel Tank Capacity (L)',
                      key: const Key('vehicle_tank_input'),
                      controller: _tankController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      hint: '45',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildInputField(
                      label: 'Base Odometer (km)',
                      key: const Key('vehicle_odometer_input'),
                      controller: _odometerController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      hint: '150000',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'Idle Throttle Baseline (%)',
                      key: const Key('vehicle_idle_throttle_input'),
                      controller: _idleThrottleController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      hint: '13.0',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildInputField(
                      label: 'Redline RPM',
                      key: const Key('vehicle_redline_input'),
                      controller: _redlineController,
                      keyboardType: TextInputType.number,
                      hint: '6500',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'Optimal Shift RPM',
                      key: const Key('vehicle_shift_rpm_input'),
                      controller: _shiftRpmController,
                      keyboardType: TextInputType.number,
                      hint: '3200',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildInputField(
                      label: 'Coolant Overheat (°C)',
                      key: const Key('vehicle_overheat_input'),
                      controller: _overheatController,
                      keyboardType: TextInputType.number,
                      hint: '102',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'Horsepower (HP)',
                      key: const Key('vehicle_hp_input'),
                      controller: _hpController,
                      keyboardType: TextInputType.number,
                      hint: '102',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildInputField(
                      label: 'Curb Weight (kg)',
                      key: const Key('vehicle_weight_input'),
                      controller: _curbWeightController,
                      keyboardType: TextInputType.number,
                      hint: '1015',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Save Action Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  key: const Key('save_vehicle_button'),
                  onPressed: _isSaving ? null : _handleSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          isEditing ? 'Save Changes' : 'Save Vehicle',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required Key key,
    required TextEditingController controller,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: key,
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.3),
              fontSize: 14,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainer,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
          ),
        ),
      ],
    );
  }
}
