import 'location.dart';

class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.label,
    required this.kind,
    required this.point,
  });
  final String id, label, kind;
  final LatLng point;
  factory SavedPlace.fromJson(Map<String, dynamic> j) => SavedPlace(
    id: j['id'] as String,
    label: j['label'] as String,
    kind: j['kind'] as String,
    point: LatLng(
      latitude: (j['latitude'] as num).toDouble(),
      longitude: (j['longitude'] as num).toDouble(),
    ),
  );
}

class RoutineTrip {
  const RoutineTrip({
    required this.id,
    required this.label,
    required this.originId,
    required this.destinationId,
    required this.mode,
    required this.weekdays,
    required this.departureMinute,
    required this.timezone,
    required this.leadMinutes,
    required this.enabled,
    required this.alertsEnabled,
    required this.newsEnabled,
  });
  final String id, label, originId, destinationId, mode, timezone;
  final List<int> weekdays;
  final int departureMinute, leadMinutes;
  final bool enabled, alertsEnabled, newsEnabled;
  factory RoutineTrip.fromJson(Map<String, dynamic> j) => RoutineTrip(
    id: j['id'] as String,
    label: j['label'] as String,
    originId: j['origin_id'] as String,
    destinationId: j['destination_id'] as String,
    mode: j['mode'] as String,
    weekdays: (j['weekdays'] as List).cast<int>(),
    departureMinute: j['departure_minute'] as int,
    timezone: j['timezone'] as String,
    leadMinutes: j['lead_minutes'] as int,
    enabled: j['enabled'] as bool,
    alertsEnabled: j['alerts_enabled'] as bool,
    newsEnabled: j['news_enabled'] as bool,
  );
  String get departureLabel =>
      '${(departureMinute ~/ 60).toString().padLeft(2, '0')}:${(departureMinute % 60).toString().padLeft(2, '0')}';
}
