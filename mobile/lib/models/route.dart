import 'location.dart';
import 'prediction.dart';

/// A route within a trip (ERD entity ROUTE).
class Route {
  final String id;
  final String tripId;
  final List<LatLng> waypoints;
  final double totalDistanceKm;
  final List<Prediction> predictions;

  const Route({
    required this.id,
    required this.tripId,
    required this.waypoints,
    required this.totalDistanceKm,
    this.predictions = const [],
  });
}
