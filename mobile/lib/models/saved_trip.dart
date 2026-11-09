import 'package:flutter/foundation.dart';

import 'location.dart';
import 'trip.dart';

enum TripHistorySort { recent, frequency }

class CommuteAnalysis {
  final int totalTrips;
  final int uniqueRoutes;
  final SavedTrip? topCommute;
  final List<SavedTrip> frequentRoutes;
  const CommuteAnalysis({
    required this.totalTrips,
    required this.uniqueRoutes,
    this.topCommute,
    required this.frequentRoutes,
  });
  bool get hasEstablishedPatterns => frequentRoutes.isNotEmpty;
}

/// A projection of confirmed backend events, not a second source of trip data.
class SavedTrip {
  final String id;
  final String? name;
  final String start;
  final String destination;
  final LatLng startPoint;
  final LatLng destPoint;
  final DateTime lastUsed;
  final int frequency;
  final List<String> eventIds;
  final String mode;

  const SavedTrip({
    required this.id,
    this.name,
    required this.start,
    required this.destination,
    required this.startPoint,
    required this.destPoint,
    required this.lastUsed,
    this.frequency = 1,
    this.eventIds = const [],
    this.mode = 'car',
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
    List<String>? eventIds,
    String? mode,
  }) => SavedTrip(
    id: id ?? this.id,
    name: name ?? this.name,
    start: start ?? this.start,
    destination: destination ?? this.destination,
    startPoint: startPoint ?? this.startPoint,
    destPoint: destPoint ?? this.destPoint,
    lastUsed: lastUsed ?? this.lastUsed,
    frequency: frequency ?? this.frequency,
    eventIds: eventIds ?? this.eventIds,
    mode: mode ?? this.mode,
  );

  String get displayTitle => name?.isNotEmpty == true ? name! : destination;
  String get routeLabel => '$start → $destination';
  Trip toTrip() => Trip(
    id: id,
    userId: '',
    name: displayTitle,
    startLocation: start,
    destination: destination,
    plannedDeparture: lastUsed,
    startPoint: startPoint,
    destPoint: destPoint,
    confirmedAt: lastUsed,
    transportMode: mode,
  );

  String get timeAgo {
    final diff = DateTime.now().difference(lastUsed);
    if (diff.isNegative) return 'Time unavailable';
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  }
}

/// Account-scoped, in-memory projection. Persistence belongs to Axum/Postgres.
/// The ambiguous legacy device-global cache is deliberately not imported.
class TripHistoryStore extends ChangeNotifier {
  static final instance = TripHistoryStore._();
  TripHistoryStore._();
  String? _userId;
  final List<SavedTrip> _trips = [];
  List<SavedTrip> get trips => List.unmodifiable(_trips);
  int get totalTripCount => _trips.fold(0, (n, trip) => n + trip.frequency);
  List<SavedTrip> get frequentCommutes =>
      _trips.where((t) => t.frequency >= 3).toList();
  CommuteAnalysis get commuteAnalysis => CommuteAnalysis(
    totalTrips: totalTripCount,
    uniqueRoutes: _trips.length,
    topCommute: _trips.isEmpty
        ? null
        : getSortedTrips(TripHistorySort.frequency).first,
    frequentRoutes: frequentCommutes,
  );

  void bindUser(String? userId) {
    if (_userId == userId) return;
    _userId = userId;
    _trips.clear();
    notifyListeners();
  }

  List<SavedTrip> getSortedTrips(TripHistorySort sort) {
    final result = List<SavedTrip>.of(_trips);
    result.sort((a, b) {
      if (sort == TripHistorySort.frequency) {
        final frequency = b.frequency.compareTo(a.frequency);
        if (frequency != 0) return frequency;
      }
      return b.lastUsed.compareTo(a.lastUsed);
    });
    return result;
  }

  void syncWithServiceTrips(List<Trip> events) {
    final grouped = <String, SavedTrip>{};
    final seen = <String>{};
    final ordered = List<Trip>.of(events)
      ..sort(
        (a, b) => (b.confirmedAt ?? b.plannedDeparture).compareTo(
          a.confirmedAt ?? a.plannedDeparture,
        ),
      );
    for (final event in ordered) {
      if (event.userId != _userId ||
          event.confirmedAt == null ||
          event.startPoint == null ||
          event.destPoint == null ||
          !seen.add(event.id)) {
        continue;
      }
      final start = event.startPoint!;
      final dest = event.destPoint!;
      // Coordinate keys keep same-name places apart and aggregate renamed places.
      final key =
          '${start.latitude.toStringAsFixed(5)},${start.longitude.toStringAsFixed(5)}:'
          '${dest.latitude.toStringAsFixed(5)},${dest.longitude.toStringAsFixed(5)}:${event.transportMode}';
      final previous = grouped[key];
      grouped[key] = previous == null
          ? SavedTrip(
              id: event.id,
              name: event.name,
              start: event.startLocation,
              destination: event.destination,
              startPoint: start,
              destPoint: dest,
              lastUsed: event.confirmedAt!,
              mode: event.transportMode,
              eventIds: [event.id],
            )
          : previous.copyWith(
              frequency: previous.frequency + 1,
              eventIds: [...previous.eventIds, event.id],
            );
    }
    _trips
      ..clear()
      ..addAll(grouped.values);
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting([
    List<SavedTrip>? customTrips,
    bool clearStorage = true,
  ]) {
    _userId = null;
    _trips
      ..clear()
      ..addAll(customTrips ?? []);
    notifyListeners();
  }
}
