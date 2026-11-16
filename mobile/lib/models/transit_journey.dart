/// Provider schedules/GTFS estimates, independent of environmental indicators.
class TransitLeg {
  const TransitLeg({
    required this.mode,
    required this.line,
    required this.from,
    required this.to,
    required this.departure,
    required this.arrival,
    required this.distanceKm,
    required this.geometryKind,
    required this.estimated,
  });
  final String mode, line, from, to, geometryKind;
  final DateTime departure, arrival;
  final double distanceKm;
  final bool estimated;
  factory TransitLeg.fromJson(Map<String, dynamic> j) {
    final dep = DateTime.parse(j['departure_at'] as String),
        arr = DateTime.parse(j['arrival_at'] as String);
    final km = (j['distance_km'] as num).toDouble();
    if (arr.isBefore(dep) || !km.isFinite || km < 0) {
      throw const FormatException('Invalid transit leg');
    }
    return TransitLeg(
      mode: j['mode'] as String,
      line: j['line'] as String,
      from: j['from'] as String,
      to: j['to'] as String,
      departure: dep,
      arrival: arr,
      distanceKm: km,
      geometryKind: j['geometry_kind'] as String,
      estimated: j['estimated'] as bool,
    );
  }
  static String wib(DateTime t) {
    final local = t.toUtc().add(const Duration(hours: 7));
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} WIB';
  }
}

class TransitJourney {
  const TransitJourney({
    required this.source,
    required this.attribution,
    required this.legs,
    this.fareIdr,
  });
  final String source, attribution;
  final List<TransitLeg> legs;
  final double? fareIdr;
  String get displayName {
    final operators = <String>{};
    for (final leg in legs.where((l) => l.mode != 'WALK')) {
      operators.add(switch (leg.mode) {
        'BUS' || 'TJ' => 'Transjakarta',
        'KCI' => 'KRL Commuter Line',
        'MRTJ' => 'MRT Jakarta',
        'LRTJ' => 'LRT Jakarta',
        'LRTJABODEBEK' => 'LRT Jabodebek',
        _ => leg.mode,
      });
    }
    return operators.join(' + ');
  }

  String get boardingSummary {
    final rides = legs.where((l) => l.mode != 'WALK');
    return '${rides.first.from} → ${rides.last.to}';
  }

  factory TransitJourney.fromJson(Map<String, dynamic> j) {
    final legs = (j['legs'] as List)
        .map((l) => TransitLeg.fromJson(l as Map<String, dynamic>))
        .toList();
    if (!legs.any((l) => l.mode != 'WALK')) {
      throw const FormatException('Transit journey has no ride');
    }
    for (var i = 1; i < legs.length; i++) {
      if (legs[i].departure.isBefore(legs[i - 1].arrival)) {
        throw const FormatException('Transit transfer departs before arrival');
      }
    }
    final fare = (j['fare_idr'] as num?)?.toDouble();
    if (fare != null && (!fare.isFinite || fare < 0)) {
      throw const FormatException('Invalid fare');
    }
    return TransitJourney(
      source: j['source'] as String,
      attribution: j['attribution'] as String,
      legs: legs,
      fareIdr: fare,
    );
  }
}
