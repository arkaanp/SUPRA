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
  int get hashCode =>
      Object.hash((latitude * 100000).round(), (longitude * 100000).round());

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

/// Key reference landmarks and points of interest across Greater Jakarta (Jabodetabek).
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
    name: 'Grand Indonesia Mall',
    area: 'Central Jakarta',
    point: LatLng(latitude: -6.1953, longitude: 106.8208),
  ),
  NamedLocation(
    name: 'Plaza Indonesia',
    area: 'Central Jakarta',
    point: LatLng(latitude: -6.1934, longitude: 106.8228),
  ),
  NamedLocation(
    name: 'McDonald\'s Sarinah Thamrin',
    area: 'Central Jakarta',
    point: LatLng(latitude: -6.1878, longitude: 106.8241),
  ),
  NamedLocation(
    name: 'McDonald\'s Hayam Wuruk',
    area: 'Central Jakarta',
    point: LatLng(latitude: -6.1610, longitude: 106.8198),
  ),
  NamedLocation(
    name: 'Stasiun Gambir',
    area: 'Central Jakarta',
    point: LatLng(latitude: -6.1767, longitude: 106.8306),
  ),
  NamedLocation(
    name: 'Stasiun Pasar Senen',
    area: 'Central Jakarta',
    point: LatLng(latitude: -6.1747, longitude: 106.8443),
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
    name: 'Senayan City',
    area: 'South Jakarta',
    point: LatLng(latitude: -6.2272, longitude: 106.7972),
  ),
  NamedLocation(
    name: 'Kemang',
    area: 'South Jakarta',
    point: LatLng(latitude: -6.2600, longitude: 106.8150),
    adm4: '31.74.04.1003',
  ),
  NamedLocation(
    name: 'McDonald\'s Kemang',
    area: 'South Jakarta',
    point: LatLng(latitude: -6.2750, longitude: 106.8180),
  ),
  NamedLocation(
    name: 'McDonald\'s TB Simatupang',
    area: 'South Jakarta',
    point: LatLng(latitude: -6.2995, longitude: 106.8235),
  ),
  NamedLocation(
    name: 'Pondok Indah Mall (PIM)',
    area: 'South Jakarta',
    point: LatLng(latitude: -6.2657, longitude: 106.7838),
  ),
  NamedLocation(
    name: 'Kota Kasablanka (Kokas)',
    area: 'South Jakarta',
    point: LatLng(latitude: -6.2238, longitude: 106.8427),
  ),
  NamedLocation(
    name: 'Stasiun Manggarai',
    area: 'South Jakarta',
    point: LatLng(latitude: -6.2099, longitude: 106.8502),
  ),
  NamedLocation(
    name: 'Central Park Mall',
    area: 'West Jakarta',
    point: LatLng(latitude: -6.1774, longitude: 106.7907),
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
    name: 'Mall Kelapa Gading (MKG)',
    area: 'North Jakarta',
    point: LatLng(latitude: -6.1578, longitude: 106.9083),
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
    name: 'McDonald\'s BSD Sunburst',
    area: 'South Tangerang',
    point: LatLng(latitude: -6.2978, longitude: 106.6685),
  ),
  NamedLocation(
    name: 'McDonald\'s Bintaro Sektor 9',
    area: 'South Tangerang',
    point: LatLng(latitude: -6.2842, longitude: 106.7118),
  ),
  NamedLocation(
    name: 'Universitas Indonesia (Depok)',
    area: 'Depok',
    point: LatLng(latitude: -6.3650, longitude: 106.8280),
  ),
  NamedLocation(
    name: 'McDonald\'s Margonda',
    area: 'Depok',
    point: LatLng(latitude: -6.3712, longitude: 106.8324),
  ),
  NamedLocation(
    name: 'Cibinong City Mall (CCM)',
    area: 'Cibinong, Bogor',
    point: LatLng(latitude: -6.4836, longitude: 106.8406),
  ),
  NamedLocation(
    name: 'McDonald\'s Cibinong City Mall',
    area: 'Cibinong, Bogor',
    point: LatLng(latitude: -6.4840, longitude: 106.8410),
  ),
  NamedLocation(
    name: 'Stasiun Cibinong',
    area: 'Cibinong, Bogor',
    point: LatLng(latitude: -6.4833, longitude: 106.8533),
  ),
  NamedLocation(
    name: 'Stadion Pakansari Cibinong',
    area: 'Cibinong, Bogor',
    point: LatLng(latitude: -6.4912, longitude: 106.8344),
  ),
  NamedLocation(
    name: 'RSUD Cibinong',
    area: 'Cibinong, Bogor',
    point: LatLng(latitude: -6.4815, longitude: 106.8378),
  ),
  NamedLocation(
    name: 'Bogor Botanical Gardens',
    area: 'Bogor',
    point: LatLng(latitude: -6.5980, longitude: 106.7970),
    adm4: '32.71.01.1001',
  ),
  NamedLocation(
    name: 'McDonald\'s Lodaya Pajajaran Bogor',
    area: 'Bogor',
    point: LatLng(latitude: -6.5912, longitude: 106.8055),
  ),
  NamedLocation(
    name: 'Botani Square Mall Bogor',
    area: 'Bogor',
    point: LatLng(latitude: -6.6015, longitude: 106.8060),
  ),
  NamedLocation(
    name: 'Stasiun Bogor',
    area: 'Bogor',
    point: LatLng(latitude: -6.5956, longitude: 106.7904),
  ),
  NamedLocation(
    name: 'Bekasi City Center',
    area: 'Bekasi',
    point: LatLng(latitude: -6.2383, longitude: 106.9756),
  ),
  NamedLocation(
    name: 'McDonald\'s Grand Galaxy',
    area: 'Bekasi',
    point: LatLng(latitude: -6.2642, longitude: 106.9721),
  ),
  NamedLocation(
    name: 'Stasiun Bekasi',
    area: 'Bekasi',
    point: LatLng(latitude: -6.2361, longitude: 106.9997),
  ),
];

/// Finds the nearest landmark to the given coordinate.
NamedLocation? findNearestLandmark(
  LatLng point, {
  double maxDistanceKm = 20.0,
}) {
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
