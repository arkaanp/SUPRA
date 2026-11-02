import 'location.dart';
import 'route.dart';

/// Planned trip (ERD entity TRIP).
class Trip {
  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    name: json['name'] as String,
    startLocation: json['start_location'] as String,
    destination: json['destination'] as String,
    plannedDeparture: DateTime.parse(json['planned_departure'] as String)
        .toLocal(),
  );
  final String id;
  final String userId;
  final String name;
  final String startLocation;
  final String destination;
  final DateTime plannedDeparture;
  final List<Route> routes;
  final List<LatLng> polyline;

  const Trip({
    required this.id,
    required this.userId,
    required this.name,
    required this.startLocation,
    required this.destination,
    required this.plannedDeparture,
    this.routes = const [],
    this.polyline = const [],
  });

  Route? get primaryRoute => routes.isNotEmpty ? routes.first : null;

  String get shortDeparture =>
      '${plannedDeparture.hour.toString().padLeft(2, '0')}:${plannedDeparture.minute.toString().padLeft(2, '0')}';
}
