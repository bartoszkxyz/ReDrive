import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:redrive/models/trip.dart';

import 'package:path_provider/path_provider.dart';

/// Manages persistence of recorded trips to local storage.
class TripHistoryService {
  static Future<File> get _file async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      return File('${docDir.path}/trips_history.json');
    } catch (_) {
      final home = Platform.environment['HOME'] ?? '.';
      final dataDir =
          Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share/redrive';
      final dir = Directory(dataDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}/trips_history.json');
    }
  }

  /// Loads all saved trips from disk.
  Future<List<Trip>> loadTrips() async {
    try {
      final file = await _file;
      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final list = jsonDecode(content) as List<dynamic>;
      final trips = list
          .map((item) => Trip.fromJson(item as Map<String, dynamic>))
          .toList();

      // Sort by newest first
      trips.sort((a, b) => b.startTime.compareTo(a.startTime));
      return trips;
    } catch (e) {
      developer.log('Failed to load trips history: $e', name: 'TripHistory');
      return [];
    }
  }

  /// Saves a newly completed trip.
  Future<void> saveTrip(Trip trip) async {
    try {
      final trips = await loadTrips();
      trips.removeWhere((t) => t.id == trip.id);
      trips.insert(0, trip);

      final file = await _file;
      final jsonString = jsonEncode(trips.map((t) => t.toJson()).toList());
      await file.writeAsString(jsonString);
      developer.log('Trip ${trip.id} saved successfully', name: 'TripHistory');
    } catch (e) {
      developer.log('Failed to save trip: $e', name: 'TripHistory');
    }
  }

  /// Deletes a specific trip by its ID.
  Future<void> deleteTrip(String id) async {
    try {
      final trips = await loadTrips();
      trips.removeWhere((t) => t.id == id);

      final file = await _file;
      final jsonString = jsonEncode(trips.map((t) => t.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      developer.log('Failed to delete trip: $e', name: 'TripHistory');
    }
  }

  /// Clears all past trips.
  Future<void> clearAll() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        await file.writeAsString('[]');
      }
    } catch (e) {
      developer.log('Failed to clear trips: $e', name: 'TripHistory');
    }
  }
}
