import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:redrive/models/vehicle_profile.dart';

/// Immutable state containing the user's vehicles and current active selection.
class GarageState {
  final List<VehicleProfile> profiles;
  final String activeProfileId;

  const GarageState({
    required this.profiles,
    required this.activeProfileId,
  });

  /// The currently active vehicle profile.
  /// Falls back to the first available profile, or a seeded Suzuki Swift profile if empty.
  VehicleProfile get activeProfile {
    if (profiles.isEmpty) {
      return VehicleProfile.defaultSuzukiSwiftM15A();
    }
    return profiles.firstWhere(
      (p) => p.id == activeProfileId,
      orElse: () => profiles.first,
    );
  }

  /// Default state seeded with the benchmark Suzuki Swift profile.
  static GarageState defaultState() {
    final defaultProfile = VehicleProfile.defaultSuzukiSwiftM15A();
    return GarageState(
      profiles: [defaultProfile],
      activeProfileId: defaultProfile.id,
    );
  }

  GarageState copyWith({
    List<VehicleProfile>? profiles,
    String? activeProfileId,
  }) {
    return GarageState(
      profiles: profiles ?? this.profiles,
      activeProfileId: activeProfileId ?? this.activeProfileId,
    );
  }

  Map<String, dynamic> toJson() => {
        'profiles': profiles.map((p) => p.toJson()).toList(),
        'activeProfileId': activeProfileId,
      };

  factory GarageState.fromJson(Map<String, dynamic> json) {
    final parsedProfiles = <VehicleProfile>[];
    final rawProfiles = json['profiles'];
    if (rawProfiles is Iterable) {
      for (final item in rawProfiles) {
        if (item is Map<String, dynamic>) {
          parsedProfiles.add(VehicleProfile.fromJson(item));
        } else if (item is Map) {
          parsedProfiles
              .add(VehicleProfile.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final activeId = (json['activeProfileId'] ?? '').toString();
    return GarageState(
      profiles: parsedProfiles,
      activeProfileId: activeId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GarageState &&
          runtimeType == other.runtimeType &&
          activeProfileId == other.activeProfileId &&
          listEquals(profiles, other.profiles);

  @override
  int get hashCode => Object.hash(
        activeProfileId,
        Object.hashAll(profiles),
      );

  @override
  String toString() =>
      'GarageState(activeId: $activeProfileId, profilesCount: ${profiles.length})';
}

/// Service managing vehicle profiles and maintenance records persistence.
/// Provides atomic file writes, crash corruption recovery, and async serialized operations.
class GarageService {
  final Directory? customDirectory;
  final File? customFile;
  final bool inMemory;

  GarageState? _memoryState;

  GarageService({
    this.customDirectory,
    this.customFile,
    this.inMemory = false,
  });

  Future<void>? _lock;

  Future<T> _synchronized<T>(Future<T> Function() action) async {
    while (_lock != null) {
      try {
        await _lock;
      } catch (_) {}
    }
    final completer = Completer<void>();
    _lock = completer.future;
    try {
      return await action();
    } finally {
      _lock = null;
      completer.complete();
    }
  }

  Future<File> get _file async {
    if (customFile != null) return customFile!;
    if (customDirectory != null) {
      if (!await customDirectory!.exists()) {
        await customDirectory!.create(recursive: true);
      }
      return File('${customDirectory!.path}/garage_profiles.json');
    }
    try {
      final docDir = await getApplicationDocumentsDirectory();
      return File('${docDir.path}/garage_profiles.json');
    } catch (_) {
      final home = Platform.environment['HOME'] ?? '.';
      final dataDir =
          Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share/redrive';
      final dir = Directory(dataDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}/garage_profiles.json');
    }
  }

  static Future<void> _atomicWrite(File targetFile, String content) async {
    if (!await targetFile.parent.exists()) {
      await targetFile.parent.create(recursive: true);
    }
    final tempFile = File('${targetFile.path}.tmp');
    try {
      await tempFile.writeAsString(content, flush: true);
      try {
        await tempFile.rename(targetFile.path);
      } catch (_) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.rename(targetFile.path);
      }
    } catch (e) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<GarageState> _backupCorruptAndReset(
      File file, String corruptContent) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final corruptBackup = File('${file.path}.corrupt.$ts.bak');
    try {
      if (await file.exists()) {
        await file.copy(corruptBackup.path);
      } else {
        await corruptBackup.writeAsString(corruptContent, flush: true);
      }
      developer.log(
        'Corrupted garage file backed up to ${corruptBackup.path}',
        name: 'GarageService',
      );
    } catch (e) {
      developer.log('Failed to backup corrupt garage file: $e',
          name: 'GarageService');
    }

    final defaultSeed = GarageState.defaultState();
    await _atomicWrite(file, jsonEncode(defaultSeed.toJson()));
    return defaultSeed;
  }

  Future<GarageState> _loadGarageInternal() async {
    if (inMemory) {
      _memoryState ??= GarageState.defaultState();
      return _memoryState!;
    }
    final file = await _file;
    if (!await file.exists()) {
      final defaultSeed = GarageState.defaultState();
      await _atomicWrite(file, jsonEncode(defaultSeed.toJson()));
      return defaultSeed;
    }

    String content = '';
    try {
      content = await file.readAsString();
      if (content.trim().isEmpty) {
        final defaultSeed = GarageState.defaultState();
        await _atomicWrite(file, jsonEncode(defaultSeed.toJson()));
        return defaultSeed;
      }

      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return await _backupCorruptAndReset(file, content);
      }

      final state =
          GarageState.fromJson(Map<String, dynamic>.from(decoded));

      if (state.profiles.isEmpty) {
        final defaultSeed = GarageState.defaultState();
        await _atomicWrite(file, jsonEncode(defaultSeed.toJson()));
        return defaultSeed;
      }

      final validActiveId =
          state.profiles.any((p) => p.id == state.activeProfileId)
              ? state.activeProfileId
              : state.profiles.first.id;

      return state.copyWith(activeProfileId: validActiveId);
    } on FormatException {
      return await _backupCorruptAndReset(file, content);
    } catch (e) {
      developer.log('Unexpected error reading garage file: $e',
          name: 'GarageService');
      return await _backupCorruptAndReset(file, content);
    }
  }

  Future<GarageState> _saveGarageInternal({
    required List<VehicleProfile> profiles,
    required String activeProfileId,
  }) async {
    List<VehicleProfile> finalProfiles = List.unmodifiable(profiles);
    String finalActiveId = activeProfileId;

    if (finalProfiles.isEmpty) {
      final defaultProfile = VehicleProfile.defaultSuzukiSwiftM15A();
      finalProfiles = [defaultProfile];
      finalActiveId = defaultProfile.id;
    } else if (!finalProfiles.any((p) => p.id == finalActiveId)) {
      finalActiveId = finalProfiles.first.id;
    }

    final state = GarageState(
      profiles: finalProfiles,
      activeProfileId: finalActiveId,
    );

    if (inMemory) {
      _memoryState = state;
      return state;
    }

    final file = await _file;
    final jsonString = jsonEncode(state.toJson());
    await _atomicWrite(file, jsonString);
    return state;
  }

  /// Loads current garage state from local disk.
  /// Seeds default state if file does not exist, is empty, or corrupted.
  Future<GarageState> loadGarage() => _synchronized(_loadGarageInternal);

  /// Saves complete garage profiles and active profile identifier atomically.
  Future<GarageState> saveGarage({
    required List<VehicleProfile> profiles,
    required String activeProfileId,
  }) =>
      _synchronized(() => _saveGarageInternal(
            profiles: profiles,
            activeProfileId: activeProfileId,
          ));

  /// Inserts a new profile or updates an existing one with matching ID.
  /// When [setAsActive] is true, sets this profile as the active profile.
  Future<GarageState> upsertProfile(
    VehicleProfile profile, {
    bool setAsActive = false,
  }) =>
      _synchronized(() async {
        final currentState = await _loadGarageInternal();
        final updatedProfiles =
            List<VehicleProfile>.from(currentState.profiles);
        final index = updatedProfiles.indexWhere((p) => p.id == profile.id);
        if (index >= 0) {
          updatedProfiles[index] = profile;
        } else {
          updatedProfiles.add(profile);
        }

        final nextActiveId = setAsActive
            ? profile.id
            : (updatedProfiles.any((p) => p.id == currentState.activeProfileId)
                ? currentState.activeProfileId
                : profile.id);

        return _saveGarageInternal(
          profiles: updatedProfiles,
          activeProfileId: nextActiveId,
        );
      });

  /// Deletes profile by [profileId].
  /// Never leaves profiles empty; re-seeds default Suzuki Swift profile if last vehicle is deleted.
  Future<GarageState> deleteProfile(String profileId) =>
      _synchronized(() async {
        final currentState = await _loadGarageInternal();
        final updatedProfiles =
            currentState.profiles.where((p) => p.id != profileId).toList();

        if (updatedProfiles.isEmpty) {
          final defaultProfile = VehicleProfile.defaultSuzukiSwiftM15A();
          return _saveGarageInternal(
            profiles: [defaultProfile],
            activeProfileId: defaultProfile.id,
          );
        }

        final nextActiveId =
            updatedProfiles.any((p) => p.id == currentState.activeProfileId)
                ? currentState.activeProfileId
                : updatedProfiles.first.id;

        return _saveGarageInternal(
          profiles: updatedProfiles,
          activeProfileId: nextActiveId,
        );
      });

  /// Switches active profile to [profileId].
  /// Throws [ArgumentError] if [profileId] does not exist.
  Future<GarageState> setActiveProfile(String profileId) =>
      _synchronized(() async {
        final currentState = await _loadGarageInternal();
        final exists = currentState.profiles.any((p) => p.id == profileId);
        if (!exists) {
          throw ArgumentError(
              'Profile with id "$profileId" not found in garage');
        }
        return _saveGarageInternal(
          profiles: currentState.profiles,
          activeProfileId: profileId,
        );
      });

  /// Records a completed maintenance service event for [maintenanceItemId]
  /// on profile [profileId] at odometer [atOdometerKm].
  Future<GarageState> markMaintenanceServiced({
    required String profileId,
    required String maintenanceItemId,
    required double atOdometerKm,
    DateTime? atDate,
  }) =>
      _synchronized(() async {
        final currentState = await _loadGarageInternal();
        final profileIndex =
            currentState.profiles.indexWhere((p) => p.id == profileId);
        if (profileIndex < 0) {
          throw ArgumentError(
              'Profile with id "$profileId" not found in garage');
        }

        final profile = currentState.profiles[profileIndex];
        final itemIndex = profile.maintenanceItems
            .indexWhere((item) => item.id == maintenanceItemId);
        if (itemIndex < 0) {
          throw ArgumentError(
              'MaintenanceItem with id "$maintenanceItemId" not found in profile "$profileId"');
        }

        final updatedItems =
            List<MaintenanceItem>.from(profile.maintenanceItems);
        updatedItems[itemIndex] = updatedItems[itemIndex].markServiced(
          atOdometerKm: atOdometerKm,
          atDate: atDate,
        );

        final updatedProfile =
            profile.copyWith(maintenanceItems: updatedItems);
        final updatedProfiles =
            List<VehicleProfile>.from(currentState.profiles);
        updatedProfiles[profileIndex] = updatedProfile;

        return _saveGarageInternal(
          profiles: updatedProfiles,
          activeProfileId: currentState.activeProfileId,
        );
      });
}
