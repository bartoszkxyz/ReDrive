import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:obdrive/models/trip.dart';

/// Manages persistence of recorded trips to local storage with atomic writes,
/// backup mirroring, crash corruption recovery, and active trip checkpointing.
class TripHistoryService {
  final Directory? customDirectory;
  final File? customFile;

  TripHistoryService({this.customDirectory, this.customFile});

  Future<void> _lock = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<File> get _file async {
    if (customFile != null) return customFile!;
    if (customDirectory != null) {
      if (!await customDirectory!.exists()) {
        await customDirectory!.create(recursive: true);
      }
      return File('${customDirectory!.path}/trips_history.json');
    }
    try {
      final docDir = await getApplicationDocumentsDirectory();
      return File('${docDir.path}/trips_history.json');
    } catch (_) {
      final home = Platform.environment['HOME'] ?? '.';
      final dataDir =
          Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share/obdrive';
      final dir = Directory(dataDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}/trips_history.json');
    }
  }

  Future<File> get _bakFile async {
    final file = await _file;
    return File('${file.path}.bak');
  }

  Future<File> get _checkpointFile async {
    final file = await _file;
    return File('${file.parent.path}/active_trip_checkpoint.json');
  }

  /// Atomically writes [content] to [targetFile] using a temporary file and POSIX rename.
  static Future<void> _atomicWrite(File targetFile, String content) async {
    if (!await targetFile.parent.exists()) {
      await targetFile.parent.create(recursive: true);
    }
    final tempFile = File('${targetFile.path}.tmp');
    try {
      // 1. Write content and flush OS buffers to physical media
      await tempFile.writeAsString(content, flush: true);

      // 2. Atomic rename (POSIX replace)
      try {
        await tempFile.rename(targetFile.path);
      } catch (_) {
        // Fallback for filesystems requiring destination deletion before replace
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

  /// Parses a list of [Trip] items from a JSON string, skipping individual malformed items.
  static List<Trip> _parseTripsFromJson(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! List) return [];
    final validTrips = <Trip>[];
    for (final item in decoded) {
      try {
        if (item is Map<String, dynamic>) {
          validTrips.add(Trip.fromJson(item));
        } else if (item is Map) {
          validTrips.add(Trip.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (itemErr) {
        developer.log('Skipping malformed trip item: $itemErr', name: 'TripHistory');
      }
    }
    return validTrips;
  }

  /// Salvages complete uncorrupted { ... } trip objects from partially damaged JSON text.
  static List<Trip> _salvageTripsFromDamagedContent(String content) {
    final salvaged = <Trip>[];
    int depth = 0;
    int start = -1;

    for (int i = 0; i < content.length; i++) {
      final char = content[i];
      if (char == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0 && start != -1) {
          final candidateJson = content.substring(start, i + 1);
          try {
            final decoded = jsonDecode(candidateJson);
            if (decoded is Map<String, dynamic>) {
              salvaged.add(Trip.fromJson(decoded));
            } else if (decoded is Map) {
              salvaged.add(Trip.fromJson(Map<String, dynamic>.from(decoded)));
            }
          } catch (_) {
            // Not a valid Trip object; ignore
          }
          start = -1;
        }
      }
    }
    return salvaged;
  }

  /// Handles corrupted primary history file by preserving a timestamped backup
  /// and attempting recovery from the mirror backup or salvage parser.
  Future<List<Trip>> _handleCorruptedHistory(File file, String corruptContent) async {
    // 1. Create a timestamped backup of the corrupt file
    try {
      final corruptBackup =
          File('${file.path}.corrupt_${DateTime.now().millisecondsSinceEpoch}');
      await corruptBackup.writeAsString(corruptContent, flush: true);
      developer.log(
        'Corrupted history backed up to ${corruptBackup.path}',
        name: 'TripHistory',
      );
    } catch (e) {
      developer.log('Failed to backup corrupt file: $e', name: 'TripHistory');
    }

    // 2. Attempt recovery from the .bak mirror file
    try {
      final bakFile = await _bakFile;
      if (await bakFile.exists()) {
        try {
          final bakBytes = await bakFile.readAsBytes();
          if (bakBytes.isNotEmpty) {
            final bakContent = utf8.decode(bakBytes);
            final decoded = jsonDecode(bakContent);
            if (decoded is List) {
              final bakTrips = _parseTripsFromJson(bakContent);
              if (bakTrips.isNotEmpty) {
                bakTrips.sort((a, b) => b.startTime.compareTo(a.startTime));
                // Restore primary file from mirror backup
                await _atomicWrite(file, bakContent);
                developer.log(
                  'Recovered ${bakTrips.length} trips from backup mirror file',
                  name: 'TripHistory',
                );
                return bakTrips;
              } else {
                // Mirror backup is valid but contains 0 trips (e.g. '[]')
                await _atomicWrite(file, '[]');
                developer.log(
                  'Restored primary file to empty [] from valid empty backup mirror',
                  name: 'TripHistory',
                );
                return [];
              }
            }
          }
        } on FormatException catch (fe) {
          developer.log('Backup mirror file contains malformed UTF-8 or JSON: $fe', name: 'TripHistory');
        }
      }
    } catch (e) {
      developer.log('Failed to recover from .bak mirror: $e', name: 'TripHistory');
    }

    // 3. Fallback: salvage any intact individual trip objects
    final salvaged = _salvageTripsFromDamagedContent(corruptContent);
    if (salvaged.isNotEmpty) {
      salvaged.sort((a, b) => b.startTime.compareTo(a.startTime));
      try {
        final jsonStr = jsonEncode(salvaged.map((t) => t.toJson()).toList());
        await _atomicWrite(file, jsonStr);
        developer.log(
          'Salvaged ${salvaged.length} trips from corrupt payload',
          name: 'TripHistory',
        );
      } catch (_) {}
      return salvaged;
    }

    // 4. Fallback when all recovery mechanisms fail: safely reset primary file to '[]'
    // so subsequent boots do not enter an infinite corruption backup loop.
    try {
      await _atomicWrite(file, '[]');
      developer.log(
        'Primary history reset to empty [] after unrecoverable corruption',
        name: 'TripHistory',
      );
    } catch (e) {
      developer.log('Failed to reset primary file to []: $e', name: 'TripHistory');
    }

    return [];
  }

  /// Handles non-UTF8 corrupted raw bytes in primary history file by preserving a
  /// timestamped binary backup, restoring valid trips from .bak mirror, or salvaging
  /// intact trips via lossy UTF-8 decoding.
  Future<List<Trip>> _handleCorruptedRawBytes(File file, List<int> bytes) async {
    // 1. Create a timestamped binary backup of the corrupt raw bytes
    if (bytes.isNotEmpty) {
      try {
        final corruptBackup =
            File('${file.path}.corrupt_${DateTime.now().millisecondsSinceEpoch}');
        await corruptBackup.writeAsBytes(bytes, flush: true);
        developer.log(
          'Corrupted raw bytes backed up to ${corruptBackup.path}',
          name: 'TripHistory',
        );
      } catch (e) {
        developer.log('Failed to backup corrupt raw bytes: $e', name: 'TripHistory');
      }
    }

    // 2. Attempt recovery from the .bak mirror file
    try {
      final bakFile = await _bakFile;
      if (await bakFile.exists()) {
        try {
          final bakBytes = await bakFile.readAsBytes();
          if (bakBytes.isNotEmpty) {
            final bakContent = utf8.decode(bakBytes);
            final decoded = jsonDecode(bakContent);
            if (decoded is List) {
              final bakTrips = _parseTripsFromJson(bakContent);
              if (bakTrips.isNotEmpty) {
                bakTrips.sort((a, b) => b.startTime.compareTo(a.startTime));
                // Restore primary file from mirror backup
                await _atomicWrite(file, bakContent);
                developer.log(
                  'Recovered ${bakTrips.length} trips from backup mirror file after non-UTF8 corruption',
                  name: 'TripHistory',
                );
                return bakTrips;
              } else {
                // Mirror backup is valid but contains 0 trips (e.g. '[]')
                await _atomicWrite(file, '[]');
                developer.log(
                  'Restored primary file to empty [] from valid empty backup mirror after non-UTF8 corruption',
                  name: 'TripHistory',
                );
                return [];
              }
            }
          }
        } on FormatException catch (fe) {
          developer.log('Backup mirror file contains malformed UTF-8 or JSON: $fe', name: 'TripHistory');
        }
      }
    } catch (e) {
      developer.log('Failed to recover from .bak mirror: $e', name: 'TripHistory');
    }

    // 3. Fallback: attempt lossy decoding and salvage any intact trip objects
    if (bytes.isNotEmpty) {
      try {
        final lossyContent = utf8.decode(bytes, allowMalformed: true);
        final salvaged = _salvageTripsFromDamagedContent(lossyContent);
        if (salvaged.isNotEmpty) {
          salvaged.sort((a, b) => b.startTime.compareTo(a.startTime));
          try {
            final jsonStr = jsonEncode(salvaged.map((t) => t.toJson()).toList());
            await _atomicWrite(file, jsonStr);
            developer.log(
              'Salvaged ${salvaged.length} trips from lossy UTF-8 decode',
              name: 'TripHistory',
            );
          } catch (_) {}
          return salvaged;
        }
      } catch (_) {}
    }

    // 4. Fallback when all recovery mechanisms fail: safely reset primary file to '[]'
    // so subsequent boots do not enter an infinite corruption backup loop.
    try {
      await _atomicWrite(file, '[]');
      developer.log(
        'Primary history reset to empty [] after unrecoverable non-UTF8 corruption',
        name: 'TripHistory',
      );
    } catch (e) {
      developer.log('Failed to reset primary file to []: $e', name: 'TripHistory');
    }

    return [];
  }

  /// Internal loader called within synchronized contexts.
  Future<List<Trip>> _loadTripsInternal() async {
    try {
      final file = await _file;
      if (!await file.exists()) {
        // Check if mirror backup exists
        final bakFile = await _bakFile;
        if (await bakFile.exists()) {
          try {
            final bakBytes = await bakFile.readAsBytes();
            if (bakBytes.isNotEmpty) {
              final bakContent = utf8.decode(bakBytes);
              final recovered = _parseTripsFromJson(bakContent);
              if (recovered.isNotEmpty) {
                await _atomicWrite(file, bakContent);
                recovered.sort((a, b) => b.startTime.compareTo(a.startTime));
                return recovered;
              }
            }
          } catch (e) {
            developer.log('Failed to recover from .bak mirror when primary missing: $e', name: 'TripHistory');
          }
        }
        return [];
      }

      final List<int> bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (e) {
        developer.log('Failed to read file bytes: $e', name: 'TripHistory');
        return await _handleCorruptedRawBytes(file, const []);
      }

      if (bytes.isEmpty) return [];

      final String content;
      try {
        content = utf8.decode(bytes);
      } on FormatException catch (fe) {
        developer.log('Non-UTF8 bytes in trip history: $fe', name: 'TripHistory');
        return await _handleCorruptedRawBytes(file, bytes);
      }

      if (content.trim().isEmpty) return [];

      try {
        final trips = _parseTripsFromJson(content);
        trips.sort((a, b) => b.startTime.compareTo(a.startTime));
        return trips;
      } on FormatException catch (fe) {
        developer.log('Corrupted JSON in trip history: $fe', name: 'TripHistory');
        return await _handleCorruptedHistory(file, content);
      } catch (e) {
        developer.log('Error parsing trip history: $e', name: 'TripHistory');
        return await _handleCorruptedHistory(file, content);
      }
    } catch (e) {
      developer.log('Failed to load trips history: $e', name: 'TripHistory');
      return [];
    }
  }

  /// Loads all saved trips from disk.
  Future<List<Trip>> loadTrips() async {
    return _synchronized(() => _loadTripsInternal());
  }

  /// Saves a newly completed trip atomically and mirrors to backup.
  Future<void> saveTrip(Trip trip) async {
    return _synchronized(() async {
      try {
        final trips = await _loadTripsInternal();
        trips.removeWhere((t) => t.id == trip.id);
        trips.insert(0, trip);

        final file = await _file;
        final jsonString = jsonEncode(trips.map((t) => t.toJson()).toList());
        await _atomicWrite(file, jsonString);

        // Mirror to backup
        try {
          final bakFile = await _bakFile;
          await _atomicWrite(bakFile, jsonString);
        } catch (e) {
          developer.log('Failed to mirror to .bak: $e', name: 'TripHistory');
        }

        developer.log('Trip ${trip.id} saved successfully', name: 'TripHistory');
      } catch (e) {
        developer.log('Failed to save trip: $e', name: 'TripHistory');
      }
    });
  }

  /// Deletes a specific trip by its ID across primary and mirror files.
  Future<void> deleteTrip(String id) async {
    return _synchronized(() async {
      try {
        final trips = await _loadTripsInternal();
        trips.removeWhere((t) => t.id == id);

        final file = await _file;
        final jsonString = jsonEncode(trips.map((t) => t.toJson()).toList());
        await _atomicWrite(file, jsonString);

        try {
          final bakFile = await _bakFile;
          await _atomicWrite(bakFile, jsonString);
        } catch (_) {}
      } catch (e) {
        developer.log('Failed to delete trip: $e', name: 'TripHistory');
      }
    });
  }

  /// Clears all past trips across primary and mirror storage.
  Future<void> clearAll() async {
    return _synchronized(() async {
      try {
        final file = await _file;
        await _atomicWrite(file, '[]');

        try {
          final bakFile = await _bakFile;
          await _atomicWrite(bakFile, '[]');
        } catch (_) {}
      } catch (e) {
        developer.log('Failed to clear trips: $e', name: 'TripHistory');
      }
    });
  }

  // ── Active In-Flight Trip Checkpoint Persistence ─────────────────────────

  /// Saves in-flight trip checkpoint state atomically to disk.
  Future<void> saveActiveCheckpoint(Map<String, dynamic> checkpointData) async {
    return _synchronized(() async {
      try {
        final file = await _checkpointFile;
        final jsonStr = jsonEncode(checkpointData);
        await _atomicWrite(file, jsonStr);
      } catch (e) {
        developer.log('Failed to save active checkpoint: $e', name: 'TripHistory');
      }
    });
  }

  /// Loads active in-flight trip checkpoint state from disk if one exists.
  Future<Map<String, dynamic>?> loadActiveCheckpoint() async {
    return _synchronized(() async {
      File? file;
      try {
        file = await _checkpointFile;
        if (!await file.exists()) return null;
        final content = await file.readAsString();
        if (content.trim().isEmpty) {
          try {
            await file.delete();
          } catch (_) {}
          return null;
        }
        final data = jsonDecode(content);
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
        try {
          await file.delete();
        } catch (_) {}
        return null;
      } catch (e) {
        developer.log('Failed to load active checkpoint: $e', name: 'TripHistory');
        try {
          if (file != null && await file.exists()) {
            await file.delete();
            developer.log('Purged corrupted active checkpoint file', name: 'TripHistory');
          }
        } catch (_) {}
        return null;
      }
    });
  }

  /// Clears active trip checkpoint after a trip is cleanly finished or discarded.
  Future<void> clearActiveCheckpoint() async {
    return _synchronized(() async {
      try {
        final file = await _checkpointFile;
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        developer.log('Failed to clear active checkpoint: $e', name: 'TripHistory');
      }
    });
  }
}
