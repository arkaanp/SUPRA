import 'dart:math';

/// Geographic coordinate used by route polylines, map markers, and location selection.
class LatLng {
  final double latitude;
  final double longitude;

  const LatLng({required this.latitude, required this.longitude});

  factory LatLng.fromJson(Map<String, dynamic> json) => LatLng(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };

  /// Returns true if coordinates are inside the Greater Jakarta service envelope.
  bool get isInGreaterJakarta =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -6.9 &&
      latitude <= -5.8 &&
      longitude >= 106.3 &&
      longitude <= 107.3;

  /// Approximate distance in kilometers between two coordinates.
  double distanceTo(LatLng other) {
    const double degToRad = pi / 180.0;
    final double midLatRad = ((latitude + other.latitude) / 2.0) * degToRad;
    final double dx = (other.longitude - longitude) * degToRad * cos(midLatRad);
    final double dy = (other.latitude - latitude) * degToRad;
    return sqrt(dx * dx + dy * dy) * 6371.0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          runtimeType == other.runtimeType &&
          (latitude - other.latitude).abs() < 1e-6 &&
          (longitude - other.longitude).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(
        (latitude * 100000).round(),
        (longitude * 100000).round(),
      );

  @override
  String toString() =>
      'LatLng(${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})';
}

/// A named landmark or reference point within Greater Jakarta.
class NamedLocation {
  final String name;
  final String area;
  final LatLng point;
  final String? adm4;

  const NamedLocation({
    required this.name,
    required this.area,
    required this.point,
    this.adm4,
  });

  @override
  String toString() => '$name ($area)';
}

/// Key reference landmarks across the Greater Jakarta (Jabodetabek) service area.
const List<NamedLocation> greaterJakartaLandmarks = [
  NamedLocation(
    name: 'Monas (Central Jakarta)',
    area: 'Central Jakarta',
    point: LatLng(latitude: -6.1754, longitude: 106.8272),
    adm4: '31.71.01.1001',
  ),
  NamedLocation(
    name: 'Bundaran HI',
    area: 'Central Jakarta',
    point: LatLng(latitude: -6.1950, longitude: 106.8230),
    adm4: '31.71.03.1001',
  ),
  NamedLocation(
    name: 'Sudirman CBD (SCBD)',
    area: 'South Jakarta',
    point: LatLng(latitude: -6.2250, longitude: 106.8080),
    adm4: '31.74.02.1002',
  ),
  NamedLocation(
    name: 'Gelora Bung Karno (GBK)',
    area: 'Central Jakarta',
    point: LatLng(latitude: -6.2185, longitude: 106.8025),
  ),
  NamedLocation(
    name: 'Kemang',
    area: 'South Jakarta',
    point: LatLng(latitude: -6.2600, longitude: 106.8150),
    adm4: '31.74.04.1003',
  ),
  NamedLocation(
    name: 'Tanjung Priok Port',
    area: 'North Jakarta',
    point: LatLng(latitude: -6.1070, longitude: 106.8840),
  ),
  NamedLocation(
    name: 'Kelapa Gading',
    area: 'North Jakarta',
    point: LatLng(latitude: -6.1580, longitude: 106.9050),
  ),
  NamedLocation(
    name: 'Soekarno-Hatta Airport (CGK)',
    area: 'Tangerang',
    point: LatLng(latitude: -6.1275, longitude: 106.6537),
  ),
  NamedLocation(
    name: 'BSD City',
    area: 'South Tangerang',
    point: LatLng(latitude: -6.3020, longitude: 106.6520),
  ),
  NamedLocation(
    name: 'Universitas Indonesia (Depok)',
    area: 'Depok',
    point: LatLng(latitude: -6.3650, longitude: 106.8280),
  ),
  NamedLocation(
    name: 'Bogor Botanical Gardens',
    area: 'Bogor',
    point: LatLng(latitude: -6.5980, longitude: 106.7970),
    adm4: '32.71.01.1001',
  ),
  NamedLocation(
    name: 'Bekasi City Center',
    area: 'Bekasi',
    point: LatLng(latitude: -6.2383, longitude: 106.9756),
  ),
];

/// Finds the nearest landmark to the given coordinate.
NamedLocation? findNearestLandmark(LatLng point, {double maxDistanceKm = 20.0}) {
  NamedLocation? closest;
  double minDistance = maxDistanceKm;

  for (final landmark in greaterJakartaLandmarks) {
    final distance = point.distanceTo(landmark.point);
    if (distance < minDistance) {
      minDistance = distance;
      closest = landmark;
    }
  }

  return closest;
}
