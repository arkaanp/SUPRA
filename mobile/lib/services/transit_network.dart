import 'dart:math';

import '../models/location.dart';

enum TransitSystem {
  mrt('MRT Jakarta', '🚆'),
  krl('KRL Commuter Line', '🚃'),
  lrt('LRT Jabodebek', '🚊');

  final String displayName;
  final String icon;
  const TransitSystem(this.displayName, this.icon);
}

class TransitStation {
  final String id;
  final String name;
  final TransitSystem system;
  final String line;
  final LatLng point;
  final int sequenceIndex;

  const TransitStation({
    required this.id,
    required this.name,
    required this.system,
    required this.line,
    required this.point,
    required this.sequenceIndex,
  });
}

class TransitRouteResult {
  final TransitStation departureStation;
  final TransitStation arrivalStation;
  final List<TransitStation> intermediateStations;
  final List<LatLng> transitWaypoints;
  final List<String> turnSteps;
  final double walkToStationKm;
  final double railDistanceKm;
  final double walkFromStationKm;
  final Duration estimatedDuration;

  double get totalDistanceKm =>
      walkToStationKm + railDistanceKm + walkFromStationKm;

  const TransitRouteResult({
    required this.departureStation,
    required this.arrivalStation,
    required this.intermediateStations,
    required this.transitWaypoints,
    required this.turnSteps,
    required this.walkToStationKm,
    required this.railDistanceKm,
    required this.walkFromStationKm,
    required this.estimatedDuration,
  });
}

/// Official rapid transit network for Greater Jakarta covering MRT Jakarta North-South Line,
/// KRL Commuter Line (Bogor, Cikarang/Loop, Serpong), and LRT Jabodebek.
abstract final class TransitNetwork {
  static const List<TransitStation> stations = [
    // --- 1. MRT Jakarta North-South Line (Lin Utara-Selatan) ---
    TransitStation(
      id: 'mrt_lebak_bulus',
      name: 'Stasiun MRT Lebak Bulus Grab',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2894, longitude: 106.7745),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'mrt_fatmawati',
      name: 'Stasiun MRT Fatmawati',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2926, longitude: 106.7937),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'mrt_cipete',
      name: 'Stasiun MRT Cipete Raya',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2778, longitude: 106.7972),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'mrt_haji_nawi',
      name: 'Stasiun MRT Haji Nawi',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2662, longitude: 106.7976),
      sequenceIndex: 3,
    ),
    TransitStation(
      id: 'mrt_blok_a',
      name: 'Stasiun MRT Blok A',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2554, longitude: 106.7974),
      sequenceIndex: 4,
    ),
    TransitStation(
      id: 'mrt_blok_m',
      name: 'Stasiun MRT Blok M BCA',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2445, longitude: 106.7981),
      sequenceIndex: 5,
    ),
    TransitStation(
      id: 'mrt_asean',
      name: 'Stasiun MRT ASEAN',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2388, longitude: 106.7987),
      sequenceIndex: 6,
    ),
    TransitStation(
      id: 'mrt_senayan',
      name: 'Stasiun MRT Senayan Mastercard',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2259, longitude: 106.8021),
      sequenceIndex: 7,
    ),
    TransitStation(
      id: 'mrt_istora',
      name: 'Stasiun MRT Istora Mandiri',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2209, longitude: 106.8073),
      sequenceIndex: 8,
    ),
    TransitStation(
      id: 'mrt_benhil',
      name: 'Stasiun MRT Bendungan Hilir',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2155, longitude: 106.8177),
      sequenceIndex: 9,
    ),
    TransitStation(
      id: 'mrt_setiabudi',
      name: 'Stasiun MRT Setiabudi Astra',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2088, longitude: 106.8206),
      sequenceIndex: 10,
    ),
    TransitStation(
      id: 'mrt_dukuh_atas',
      name: 'Stasiun MRT Dukuh Atas BNI (Interchange)',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.2008, longitude: 106.8228),
      sequenceIndex: 11,
    ),
    TransitStation(
      id: 'mrt_bundaran_hi',
      name: 'Stasiun MRT Bundaran HI Bank DKI',
      system: TransitSystem.mrt,
      line: 'MRT North-South Line',
      point: LatLng(latitude: -6.1931, longitude: 106.8230),
      sequenceIndex: 12,
    ),

    // --- 2. KRL Commuter Line Central & South Axis ---
    TransitStation(
      id: 'krl_jakarta_kota',
      name: 'Stasiun KRL Jakarta Kota',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1376, longitude: 106.8146),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'krl_juanda',
      name: 'Stasiun KRL Juanda (Monas Utara)',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1668, longitude: 106.8282),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'krl_gondangdia',
      name: 'Stasiun KRL Gondangdia (Monas Selatan)',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1863, longitude: 106.8329),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'krl_cikini',
      name: 'Stasiun KRL Cikini',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.1983, longitude: 106.8427),
      sequenceIndex: 3,
    ),
    TransitStation(
      id: 'krl_manggarai',
      name: 'Stasiun KRL Manggarai Central',
      system: TransitSystem.krl,
      line: 'KRL Central Interchange',
      point: LatLng(latitude: -6.2099, longitude: 106.8499),
      sequenceIndex: 4,
    ),
    TransitStation(
      id: 'krl_sudirman',
      name: 'Stasiun KRL Sudirman (Dukuh Atas)',
      system: TransitSystem.krl,
      line: 'KRL Cikarang Loop Line',
      point: LatLng(latitude: -6.2023, longitude: 106.8236),
      sequenceIndex: 5,
    ),
    TransitStation(
      id: 'krl_tanah_abang',
      name: 'Stasiun KRL Tanah Abang',
      system: TransitSystem.krl,
      line: 'KRL Serpong-Rangkasbitung Line',
      point: LatLng(latitude: -6.1857, longitude: 106.8110),
      sequenceIndex: 6,
    ),
    TransitStation(
      id: 'krl_palmerah',
      name: 'Stasiun KRL Palmerah (DPR/MPR)',
      system: TransitSystem.krl,
      line: 'KRL Serpong-Rangkasbitung Line',
      point: LatLng(latitude: -6.2070, longitude: 106.7970),
      sequenceIndex: 7,
    ),
    TransitStation(
      id: 'krl_kebayoran',
      name: 'Stasiun KRL Kebayoran (Gandaria)',
      system: TransitSystem.krl,
      line: 'KRL Serpong-Rangkasbitung Line',
      point: LatLng(latitude: -6.2372, longitude: 106.7828),
      sequenceIndex: 8,
    ),
    TransitStation(
      id: 'krl_tebet',
      name: 'Stasiun KRL Tebet',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.2263, longitude: 106.8582),
      sequenceIndex: 9,
    ),
    TransitStation(
      id: 'krl_cawang',
      name: 'Stasiun KRL Cawang',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.2425, longitude: 106.8587),
      sequenceIndex: 10,
    ),
    TransitStation(
      id: 'krl_pasar_minggu',
      name: 'Stasiun KRL Pasar Minggu',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.2842, longitude: 106.8443),
      sequenceIndex: 11,
    ),
    TransitStation(
      id: 'krl_ui',
      name: 'Stasiun KRL Universitas Indonesia',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.3607, longitude: 106.8317),
      sequenceIndex: 12,
    ),
    TransitStation(
      id: 'krl_depok_baru',
      name: 'Stasiun KRL Depok Baru',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.3917, longitude: 106.8193),
      sequenceIndex: 13,
    ),
    TransitStation(
      id: 'krl_bogor',
      name: 'Stasiun KRL Bogor',
      system: TransitSystem.krl,
      line: 'KRL Bogor-Kota Line',
      point: LatLng(latitude: -6.5944, longitude: 106.7904),
      sequenceIndex: 14,
    ),

    // --- 3. LRT Jabodebek Corridor ---
    TransitStation(
      id: 'lrt_dukuh_atas',
      name: 'Stasiun LRT Dukuh Atas',
      system: TransitSystem.lrt,
      line: 'LRT Jabodebek',
      point: LatLng(latitude: -6.2025, longitude: 106.8210),
      sequenceIndex: 0,
    ),
    TransitStation(
      id: 'lrt_rasuna_said',
      name: 'Stasiun LRT Rasuna Said (Kuningan)',
      system: TransitSystem.lrt,
      line: 'LRT Jabodebek',
      point: LatLng(latitude: -6.2185, longitude: 106.8320),
      sequenceIndex: 1,
    ),
    TransitStation(
      id: 'lrt_pancoran',
      name: 'Stasiun LRT Pancoran',
      system: TransitSystem.lrt,
      line: 'LRT Jabodebek',
      point: LatLng(latitude: -6.2435, longitude: 106.8435),
      sequenceIndex: 2,
    ),
    TransitStation(
      id: 'lrt_halim',
      name: 'Stasiun LRT Halim (Whoosh KCIC)',
      system: TransitSystem.lrt,
      line: 'LRT Jabodebek',
      point: LatLng(latitude: -6.2500, longitude: 106.8830),
      sequenceIndex: 3,
    ),
  ];

  /// Finds the closest rapid transit station to any given coordinates in Greater Jakarta.
  static TransitStation findNearestStation(
    LatLng location, {
    TransitSystem? preferredSystem,
  }) {
    TransitStation? best;
    double minDistance = double.infinity;

    for (final s in stations) {
      if (preferredSystem != null && s.system != preferredSystem) continue;
      final dist = location.distanceTo(s.point);
      if (dist < minDistance) {
        minDistance = dist;
        best = s;
      }
    }
    return best ?? stations.first;
  }

  /// Calculates a multi-modal public transit itinerary connecting origin to destination:
  /// First-mile road walk/feeder -> Station Platform -> Dedicated Rail Corridor -> Arrival Station -> Last-mile road walk.
  static TransitRouteResult buildTransitRoute({
    required LatLng origin,
    required LatLng destination,
    String? originName,
    String? destinationName,
  }) {
    final depStation = findNearestStation(origin);
    TransitStation arrStation = findNearestStation(destination);

    // If both resolve to the exact same station, pick an alternative
    if (depStation.id == arrStation.id) {
      final candidates = List<TransitStation>.of(stations)
        ..sort(
          (a, b) => destination
              .distanceTo(a.point)
              .compareTo(destination.distanceTo(b.point)),
        );
      arrStation = candidates.firstWhere(
        (s) => s.id != depStation.id,
        orElse: () => stations.last,
      );
    }

    final walkToStationKm = origin.distanceTo(depStation.point);
    final walkFromStationKm = arrStation.point.distanceTo(destination);

    // Build intermediate station sequence along the rail corridor
    final intermediate = <TransitStation>[];
    final waypoints = <LatLng>[];

    // First leg: First-mile path from Origin to Departure Station
    waypoints.addAll(_interpolateCorridor(origin, depStation.point, 6));

    // Middle leg: Rail alignment through physical transit stations
    if (depStation.system == arrStation.system &&
        depStation.line == arrStation.line) {
      // Same line: collect all intermediate stations in sequence
      final sameLine = stations
          .where((s) => s.line == depStation.line)
          .toList();
      final depIdx = sameLine.indexWhere((s) => s.id == depStation.id);
      final arrIdx = sameLine.indexWhere((s) => s.id == arrStation.id);

      final step = depIdx < arrIdx ? 1 : -1;
      for (int i = depIdx; i != arrIdx + step; i += step) {
        if (i >= 0 && i < sameLine.length) {
          final s = sameLine[i];
          waypoints.add(s.point);
          if (s.id != depStation.id && s.id != arrStation.id) {
            intermediate.add(s);
          }
        }
      }
    } else {
      // Cross-line transfer: Route through central interchange (Dukuh Atas / Manggarai)
      final interchange = depStation.system == TransitSystem.mrt
          ? stations.firstWhere((s) => s.id == 'mrt_dukuh_atas')
          : stations.firstWhere((s) => s.id == 'krl_manggarai');

      waypoints.add(depStation.point);
      if (depStation.id != interchange.id && arrStation.id != interchange.id) {
        intermediate.add(interchange);
        waypoints.add(interchange.point);
      }
      waypoints.add(arrStation.point);
    }

    // Last leg: Egress path from Arrival Station to Destination
    waypoints.addAll(_interpolateCorridor(arrStation.point, destination, 6));

    // Calculate real rail distance
    double railKm = 0.0;
    for (int i = 0; i < waypoints.length - 1; i++) {
      railKm += waypoints[i].distanceTo(waypoints[i + 1]);
    }
    railKm = max(1.0, railKm - walkToStationKm - walkFromStationKm);

    // Durations: walking ~4.5 km/h, train ~36 km/h + 5 min station dwell buffer
    final walkMins = ((walkToStationKm + walkFromStationKm) / 4.5 * 60).round();
    final trainMins = max(6, (railKm / 36.0 * 60).round() + 5);
    final totalDuration = Duration(minutes: walkMins + trainMins);

    final steps = <String>[
      'Walk ${walkToStationKm < 1.0 ? "${(walkToStationKm * 1000).round()} m" : "${walkToStationKm.toStringAsFixed(1)} km"} to ${depStation.name}',
      'Board ${depStation.system.displayName} (${depStation.line}) at Platform',
    ];

    if (intermediate.isNotEmpty) {
      final stopNames = intermediate
          .map((s) => s.name.split(' (').first.replaceAll('Stasiun ', ''))
          .join(', ');
      steps.add('Ride via $stopNames');
    } else {
      steps.add('Direct express ride to destination station');
    }

    steps.add('Alight at ${arrStation.name}');
    steps.add(
      'Walk ${walkFromStationKm < 1.0 ? "${(walkFromStationKm * 1000).round()} m" : "${walkFromStationKm.toStringAsFixed(1)} km"} to ${destinationName ?? "Final Destination"}',
    );

    return TransitRouteResult(
      departureStation: depStation,
      arrivalStation: arrStation,
      intermediateStations: intermediate,
      transitWaypoints: waypoints,
      turnSteps: steps,
      walkToStationKm: walkToStationKm,
      railDistanceKm: railKm,
      walkFromStationKm: walkFromStationKm,
      estimatedDuration: totalDuration,
    );
  }

  static List<LatLng> _interpolateCorridor(
    LatLng start,
    LatLng end,
    int steps,
  ) {
    final pts = <LatLng>[];
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      // Slight road-grid bend mirroring urban street network
      final wobbleLat = sin(t * pi) * 0.0008;
      final wobbleLon = cos(t * pi) * 0.0006;
      pts.add(
        LatLng(
          latitude: double.parse(
            (start.latitude + (end.latitude - start.latitude) * t + wobbleLat)
                .toStringAsFixed(5),
          ),
          longitude: double.parse(
            (start.longitude +
                    (end.longitude - start.longitude) * t +
                    wobbleLon)
                .toStringAsFixed(5),
          ),
        ),
      );
    }
    return pts;
  }
}
