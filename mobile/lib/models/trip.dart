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
    startPoint: json['start_latitude'] == null
        ? null
        : LatLng(
            latitude: (json['start_latitude'] as num).toDouble(),
            longitude: (json['start_longitude'] as num).toDouble(),
          ),
    destPoint: json['destination_latitude'] == null
        ? null
        : LatLng(
            latitude: (json['destination_latitude'] as num).toDouble(),
            longitude: (json['destination_longitude'] as num).toDouble(),
          ),
    confirmedAt: DateTime.tryParse(json['confirmed_at'] as String? ?? ''),
    transportMode: json['transport_mode'] as String? ?? 'car',
    activeUntil: DateTime.tryParse(json['active_until'] as String? ?? ''),
  );
  final String id;
  final String userId;
  final String name;
  final String startLocation;
  final String destination;
  final DateTime plannedDeparture;
  final LatLng? startPoint;
  final LatLng? destPoint;
  final DateTime? confirmedAt;
  final String transportMode;
  final DateTime? activeUntil;
  final List<Route> routes;
  final List<LatLng> polyline;

  const Trip({
    required this.id,
    required this.userId,
    required this.name,
    required this.startLocation,
    required this.destination,
    required this.plannedDeparture,
    this.startPoint,
    this.destPoint,
    this.confirmedAt,
    this.transportMode = 'car',
    this.activeUntil,
    this.routes = const [],
    this.polyline = const [],
  });

  Route? get primaryRoute => routes.isNotEmpty ? routes.first : null;

  String get shortDeparture =>
      '${plannedDeparture.hour.toString().padLeft(2, '0')}:${plannedDeparture.minute.toString().padLeft(2, '0')}';
}
