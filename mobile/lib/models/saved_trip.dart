import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'location.dart';
import 'trip.dart';

enum TripHistorySort {
  recent,
  frequency,
}

/// Commute pattern analysis results from the user's saved trip history.
/// Ready for integration with the Alerts tab for proactive commute notifications.
class CommuteAnalysis {
  final int totalTrips;
  final int uniqueRoutes;
  final SavedTrip? topCommute;
  final List<SavedTrip> frequentRoutes;

  const CommuteAnalysis({
    required this.totalTrips,
    required this.uniqueRoutes,
    required this.topCommute,
    required this.frequentRoutes,
  });

  bool get hasEstablishedPatterns => frequentRoutes.isNotEmpty;
}

/// A saved or historical commute trip recorded in SUPRA.
/// Tracks start, destination, coordinates, timestamps, and usage frequency.
/// Used for route navigation, historical replay, and Commute Pattern Detection in Alerts.
class SavedTrip {
  final String id;
  final String? name;
  final String start;
  final String destination;
  final LatLng startPoint;
  final LatLng destPoint;
  final DateTime lastUsed;
  final int frequency;

  const SavedTrip({
    required this.id,
    this.name,
    required this.start,
    required this.destination,
    required this.startPoint,
    required this.destPoint,
    required this.lastUsed,
    this.frequency = 1,
  });

  SavedTrip copyWith({
    String? id,
    String? name,
    String? start,
    String? destination,
    LatLng? startPoint,
    LatLng? destPoint,
    DateTime? lastUsed,
    int? frequency,
  }) {
    return SavedTrip(
      id: id ?? this.id,
      name: name ?? this.name,
      start: start ?? this.start,
      destination: destination ?? this.destination,
      startPoint: startPoint ?? this.startPoint,
      destPoint: destPoint ?? this.destPoint,
      lastUsed: lastUsed ?? this.lastUsed,
      frequency: frequency ?? this.frequency,
    );
  }

  String get displayTitle =>
      (name != null && name!.isNotEmpty) ? name! : destination;

  String get routeLabel => '$start → $destination';

  /// Converts this saved trip into a standard [Trip] model for interoperability.
  Trip toTrip() => Trip(
        id: id,
        userId: 'local_user',
        name: displayTitle,
        startLocation: start,
        destination: destination,
        plannedDeparture: lastUsed,
      );

  String get timeAgo {
    final diff = DateTime.now().difference(lastUsed);
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${(diff.inDays / 7).floor()}w ago';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        'start': start,
        'destination': destination,
        'start_lat': startPoint.latitude,
        'start_lng': startPoint.longitude,
        'dest_lat': destPoint.latitude,
        'dest_lng': destPoint.longitude,
        'last_used': lastUsed.toIso8601String(),
        'frequency': frequency,
      };

  factory SavedTrip.fromJson(Map<String, dynamic> json) => SavedTrip(
        id: json['id'] as String? ?? 'trip_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String?,
        start: json['start'] as String? ?? '',
        destination: json['destination'] as String? ?? '',
        startPoint: LatLng(
          latitude: (json['start_lat'] as num?)?.toDouble() ?? -6.2,
          longitude: (json['start_lng'] as num?)?.toDouble() ?? 106.8,
        ),
        destPoint: LatLng(
          latitude: (json['dest_lat'] as num?)?.toDouble() ?? -6.2,
          longitude: (json['dest_lng'] as num?)?.toDouble() ?? 106.8,
        ),
        lastUsed: json['last_used'] != null
            ? (DateTime.tryParse(json['last_used'] as String) ?? DateTime.now())
            : DateTime.now(),
        frequency: (json['frequency'] as num?)?.toInt() ?? 1,
      );
}

/// Central store for saved trips and commute history.
/// Notifies listeners when trips are added, updated, frequency-reduced, or deleted.
class TripHistoryStore extends ChangeNotifier {
  static final TripHistoryStore instance = TripHistoryStore._internal();
  static const String _storageKey = 'supra_saved_trips_v1';

  TripHistoryStore._internal() {
    _initDefaultTrips();
    _loadFromStorage();
  }

  final List<SavedTrip> _trips = [];

  List<SavedTrip> get trips => List.unmodifiable(_trips);

  int get totalTripCount => _trips.fold(0, (sum, t) => sum + t.frequency);

  /// Loads persisted trips from local device storage across app sessions.
  Future<void> loadFromStorage() async {
    await _loadFromStorage();
  }

  /// Persists current trips and counters to local device storage.
  Future<void> persistToStorage() async {
    await _persistToStorage();
  }

  /// Loads persisted trips from local device storage across app sessions.
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final loaded = decoded
            .map((item) => SavedTrip.fromJson(item as Map<String, dynamic>))
            .toList();
        if (loaded.isNotEmpty) {
          _trips.clear();
          _trips.addAll(loaded);
          notifyListeners();
        }
      }
    } catch (_) {
      // Gracefully retain initial default trips if storage is unavailable
    }
  }

  /// Persists current trips and counters to local device storage.
  Future<void> _persistToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = jsonEncode(_trips.map((t) => t.toJson()).toList());
      await prefs.setString(_storageKey, serialized);
    } catch (_) {
      // Silently ignore storage persistence errors
    }
  }

  /// Commute pattern: Routes traveled 3 or more times, representing established daily commute habits
  List<SavedTrip> get frequentCommutes =>
      _trips.where((t) => t.frequency >= 3).toList();

  /// Comprehensive commute analysis for Alerts and Notifications
  CommuteAnalysis get commuteAnalysis => CommuteAnalysis(
        totalTrips: totalTripCount,
        uniqueRoutes: _trips.length,
        topCommute: _trips.isNotEmpty
            ? (List<SavedTrip>.from(_trips)
                  ..sort((a, b) => b.frequency.compareTo(a.frequency)))
                .first
            : null,
        frequentRoutes: frequentCommutes,
      );

  /// Gets trips sorted according to criteria
  List<SavedTrip> getSortedTrips(TripHistorySort sort) {
    final list = List<SavedTrip>.from(_trips);
    if (sort == TripHistorySort.recent) {
      list.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    } else {
      list.sort((a, b) {
        final cmp = b.frequency.compareTo(a.frequency);
        if (cmp != 0) return cmp;
        return b.lastUsed.compareTo(a.lastUsed);
      });
    }
    return list;
  }

  /// Merges backend / service trips into the synchronized store if not already present.
  void syncWithServiceTrips(List<Trip> serviceTrips) {
    bool changed = false;
    for (final st in serviceTrips) {
      if (!_trips.any((t) =>
          t.id == st.id ||
          (t.destination == st.destination && t.start == st.startLocation))) {
        _trips.insert(
          0,
          SavedTrip(
            id: st.id,
            name: st.name,
            start: st.startLocation,
            destination: st.destination,
            startPoint: const LatLng(latitude: -6.2297, longitude: 106.8295),
            destPoint: const LatLng(latitude: -6.1925, longitude: 106.8230),
            lastUsed: st.plannedDeparture,
            frequency: 1,
          ),
        );
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _persistToStorage();
    }
  }

  void _initDefaultTrips() {
    final now = DateTime.now();
    _trips.clear();
    _trips.addAll([
      SavedTrip(
        id: 'trip_gi',
        start: 'Monas (Central Jakarta)',
        destination: 'Grand Indonesia Mall',
        startPoint: const LatLng(latitude: -6.1754, longitude: 106.8272),
        destPoint: const LatLng(latitude: -6.1950, longitude: 106.8200),
        lastUsed: now.subtract(const Duration(minutes: 25)),
        frequency: 5,
      ),
      SavedTrip(
        id: 'trip_ccm',
        start: 'Monas (Central Jakarta)',
        destination: 'Cibinong City Mall (CCM)',
        startPoint: const LatLng(latitude: -6.1754, longitude: 106.8272),
        destPoint: const LatLng(latitude: -6.4820, longitude: 106.8450),
        lastUsed: now.subtract(const Duration(hours: 2)),
        frequency: 4,
      ),
      SavedTrip(
        id: 'trip_bhi',
        start: 'Sudirman CBD (SCBD)',
        destination: 'Bundaran HI',
        startPoint: const LatLng(latitude: -6.2250, longitude: 106.8080),
        destPoint: const LatLng(latitude: -6.1925, longitude: 106.8230),
        lastUsed: now.subtract(const Duration(hours: 5)),
        frequency: 4,
      ),
      SavedTrip(
        id: 'trip_gbk',
        start: 'Monas (Central Jakarta)',
        destination: 'Gelora Bung Karno (GBK)',
        startPoint: const LatLng(latitude: -6.1754, longitude: 106.8272),
        destPoint: const LatLng(latitude: -6.2186, longitude: 106.8026),
        lastUsed: now.subtract(const Duration(days: 1)),
        frequency: 3,
      ),
      SavedTrip(
        id: 'trip_gambir',
        start: 'McDonald\'s Sarinah Thamrin',
        destination: 'Stasiun Gambir',
        startPoint: const LatLng(latitude: -6.1878, longitude: 106.8242),
        destPoint: const LatLng(latitude: -6.1767, longitude: 106.8306),
        lastUsed: now.subtract(const Duration(days: 2)),
        frequency: 2,
      ),
      SavedTrip(
        id: 'trip_scbd',
        start: 'Kemang',
        destination: 'Sudirman CBD (SCBD)',
        startPoint: const LatLng(latitude: -6.2625, longitude: 106.8158),
        destPoint: const LatLng(latitude: -6.2250, longitude: 106.8080),
        lastUsed: now.subtract(const Duration(days: 3)),
        frequency: 2,
      ),
    ]);
  }

  /// Saves or updates a trip in history. If the route already exists, increments frequency.
  SavedTrip saveTrip({
    required String start,
    required String destination,
    required LatLng startPoint,
    required LatLng destPoint,
  }) {
    final existingIndex = _trips.indexWhere(
      (t) => t.start == start && t.destination == destination,
    );
    if (existingIndex >= 0) {
      final existing = _trips[existingIndex];
      final updated = existing.copyWith(
        frequency: existing.frequency + 1,
        lastUsed: DateTime.now(),
        startPoint: startPoint,
        destPoint: destPoint,
      );
      _trips[existingIndex] = updated;
      notifyListeners();
      _persistToStorage();
      return updated;
    } else {
      final newTrip = SavedTrip(
        id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
        start: start,
        destination: destination,
        startPoint: startPoint,
        destPoint: destPoint,
        lastUsed: DateTime.now(),
        frequency: 1,
      );
      _trips.insert(0, newTrip);
      notifyListeners();
      _persistToStorage();
      return newTrip;
    }
  }

  /// Directly inserts or re-adds a trip (e.g. for undo operation).
  void insertTrip(SavedTrip trip, [int index = 0]) {
    if (index >= 0 && index <= _trips.length) {
      _trips.insert(index, trip);
    } else {
      _trips.add(trip);
    }
    notifyListeners();
    _persistToStorage();
  }

  /// Reduces frequency of a trip by 1. If frequency drops to 0 or below, removes it.
  /// Returns the updated SavedTrip, or null if removed completely.
  SavedTrip? reduceFrequency(String tripId) {
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index < 0) return null;
    final trip = _trips[index];
    if (trip.frequency > 1) {
      final updated = trip.copyWith(frequency: trip.frequency - 1);
      _trips[index] = updated;
      notifyListeners();
      _persistToStorage();
      return updated; // Still exists with reduced frequency
    } else {
      _trips.removeAt(index);
      notifyListeners();
      _persistToStorage();
      return null; // Removed completely
    }
  }

  /// Completely deletes a trip from history regardless of frequency.
  SavedTrip? deleteTrip(String tripId) {
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index < 0) return null;
    final removed = _trips.removeAt(index);
    notifyListeners();
    _persistToStorage();
    return removed;
  }

  @visibleForTesting
  void resetForTesting([List<SavedTrip>? customTrips, bool clearStorage = true]) {
    _trips.clear();
    if (customTrips != null) {
      _trips.addAll(customTrips);
    } else {
      _initDefaultTrips();
    }
    if (clearStorage) {
      SharedPreferences.getInstance()
          .then((p) => p.remove(_storageKey))
          .catchError((_) => false);
    }
    notifyListeners();
  }
}

