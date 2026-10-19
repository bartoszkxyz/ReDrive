import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/services/garage/auto_data_spec_parser.dart';
import 'package:redrive/services/garage/garage_service.dart';
import 'package:redrive/services/logging/log_service.dart';

/// Provider managing multi-vehicle profiles, active profile selection,
/// `auto-data.net` URL specification parsing, maintenance tracking,
/// and live synchronization with [ObdProvider] and [TripProvider].
class GarageProvider extends ChangeNotifier {
  final GarageService _garageService;
  final AutoDataSpecParser _specParser;

  GarageState _state = GarageState.defaultState();
  GarageState get state => _state;

  List<VehicleProfile> get profiles => _state.profiles;
  VehicleProfile get activeProfile => _state.activeProfile;
  String get activeProfileId => _state.activeProfileId;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _isParsingUrl = false;
  bool get isParsingUrl => _isParsingUrl;

  String? _urlParseError;
  String? get urlParseError => _urlParseError;

  ObdProvider? _boundObd;
  TripProvider? _boundTrip;

  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initialized => _initCompleter.future;

  GarageProvider({
    GarageService? garageService,
    AutoDataSpecParser? specParser,
  })  : _garageService = garageService ?? GarageService(),
        _specParser = specParser ?? AutoDataSpecParser() {
    _init();
  }

  Future<void> _init() async {
    try {
      _state = await _garageService.loadGarage();
      _propagateActiveProfile();
    } catch (e) {
      LogService.e('Failed to initialize GarageProvider: $e', tag: 'Garage');
    } finally {
      _isLoading = false;
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      notifyListeners();
    }
  }

  /// Binds [ObdProvider] and [TripProvider] so changes to the active [VehicleProfile]
  /// automatically update fuel calculations, tank capacity, and anomaly thresholds.
  void bindProviders({
    ObdProvider? obdProvider,
    TripProvider? tripProvider,
  }) {
    _boundObd = obdProvider ?? _boundObd;
    _boundTrip = tripProvider ?? _boundTrip;
    _propagateActiveProfile();
  }

  void _propagateActiveProfile() {
    final active = _state.activeProfile;
    _boundObd?.applyVehicleProfile(active);
    _boundTrip?.applyVehicleProfile(active);
  }

  /// Selects a vehicle profile by [profileId] as the active profile.
  Future<void> selectActiveProfile(String profileId) async {
    _state = await _garageService.setActiveProfile(profileId);
    _propagateActiveProfile();
    notifyListeners();
  }

  /// Adds or updates a [VehicleProfile] and persists it.
  Future<void> saveProfile(
    VehicleProfile profile, {
    bool setAsActive = false,
  }) async {
    _state = await _garageService.upsertProfile(
      profile,
      setAsActive: setAsActive,
    );
    _propagateActiveProfile();
    notifyListeners();
  }

  /// Replaces the full garage state (e.g., when synced from Phone/Headunit).
  Future<void> replaceGarageState(GarageState newState) async {
    _state = await _garageService.saveGarage(
      profiles: newState.profiles,
      activeProfileId: newState.activeProfileId,
    );
    _propagateActiveProfile();
    notifyListeners();
  }

  /// Deletes a vehicle profile by [profileId].
  Future<void> deleteProfile(String profileId) async {
    _state = await _garageService.deleteProfile(profileId);
    _propagateActiveProfile();
    notifyListeners();
  }

  /// Marks a [MaintenanceItem] as serviced at [atOdometerKm].
  Future<void> markMaintenanceServiced({
    required String maintenanceItemId,
    required double atOdometerKm,
    DateTime? atDate,
    String? profileId,
  }) async {
    final targetProfileId = profileId ?? _state.activeProfileId;
    _state = await _garageService.markMaintenanceServiced(
      profileId: targetProfileId,
      maintenanceItemId: maintenanceItemId,
      atOdometerKm: atOdometerKm,
      atDate: atDate,
    );
    _propagateActiveProfile();
    notifyListeners();
  }

  /// Refuels the virtual tank of the active (or specified) profile to full capacity.
  Future<void> refuelFull({String? profileId, DateTime? atDate}) async {
    final targetId = profileId ?? _state.activeProfileId;
    final targetProfile = _state.profiles.firstWhere(
      (p) => p.id == targetId,
      orElse: () => _state.activeProfile,
    );
    final updated = targetProfile.refuelFull(atDate: atDate);
    await saveProfile(updated);
  }

  /// Adds [liters] of fuel to the virtual tank of the active (or specified) profile.
  Future<void> refuelAmount(
    double liters, {
    String? profileId,
    DateTime? atDate,
  }) async {
    final targetId = profileId ?? _state.activeProfileId;
    final targetProfile = _state.profiles.firstWhere(
      (p) => p.id == targetId,
      orElse: () => _state.activeProfile,
    );
    final updated = targetProfile.refuelAmount(liters, atDate: atDate);
    await saveProfile(updated);
  }

  /// Deducts [litersBurned] from the virtual tank of the active (or specified) profile.
  Future<void> deductFuel(double litersBurned, {String? profileId}) async {
    if (litersBurned <= 0) return;
    final targetId = profileId ?? _state.activeProfileId;
    final targetProfile = _state.profiles.firstWhere(
      (p) => p.id == targetId,
      orElse: () => _state.activeProfile,
    );
    if (targetProfile.fuelLevelSource != FuelLevelSource.virtualTank) return;
    final updated = targetProfile.deductFuel(litersBurned);
    await saveProfile(updated);
  }

  /// Updates the [FuelLevelSource] for the active (or specified) profile.
  Future<void> setFuelLevelSource(
    FuelLevelSource source, {
    String? profileId,
  }) async {
    final targetId = profileId ?? _state.activeProfileId;
    final targetProfile = _state.profiles.firstWhere(
      (p) => p.id == targetId,
      orElse: () => _state.activeProfile,
    );
    final updated = targetProfile.copyWith(fuelLevelSource: source);
    await saveProfile(updated);
  }

  /// Clears any previous URL parse error message.
  void clearUrlParseError() {
    if (_urlParseError != null) {
      _urlParseError = null;
      notifyListeners();
    }
  }

  /// Fetches and parses an `auto-data.net` vehicle specification URL.
  Future<AutoDataVehicleSpecs?> parseAutoDataUrl(
    String rawUrl, {
    Future<String> Function(Uri uri)? httpFetcher,
  }) async {
    _isParsingUrl = true;
    _urlParseError = null;
    notifyListeners();

    try {
      final specs = await _specParser.fetchAndParseUrl(
        rawUrl,
        httpFetcher: httpFetcher,
      );
      if (!specs.hasAnyParsedSpec) {
        _urlParseError = 'No specifications found on that page.';
        return null;
      }
      return specs;
    } on FormatException catch (e) {
      _urlParseError = e.message;
      return null;
    } catch (e) {
      _urlParseError = 'Failed to fetch specs: $e';
      return null;
    } finally {
      _isParsingUrl = false;
      notifyListeners();
    }
  }
}
