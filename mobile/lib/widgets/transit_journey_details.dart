import 'package:flutter/material.dart';

import 'source_info_button.dart';

import '../models/transit_journey.dart';

class TransitJourneyDetails extends StatelessWidget {
  const TransitJourneyDetails({super.key, required this.journey});
  final TransitJourney journey;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(),
      Text(
        journey.fareIdr == null
            ? 'Tarif tidak tersedia'
            : 'Perkiraan tarif · Rp ${journey.fareIdr!.toStringAsFixed(0)}',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
      const SizedBox(height: 6),
      for (final leg in journey.legs)
        if (leg.mode != 'WALK' || leg.distanceKm > 0.02)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  leg.mode == 'WALK'
                      ? Icons.directions_walk
                      : leg.mode == 'BUS' || leg.mode == 'TJ'
                      ? Icons.directions_bus
                      : Icons.train,
                  size: 18,
                  color: Colors.teal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        leg.mode == 'WALK'
                            ? 'Jalan kaki sekitar ${(leg.distanceKm * 1000).round()} m'
                            : leg.line,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${leg.from} → ${leg.to}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        '${TransitLeg.wib(leg.departure)} → ${TransitLeg.wib(leg.arrival)} · ${leg.estimated ? 'Perkiraan' : 'Jadwal'}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blueGrey,
                        ),
                      ),
                      if (leg.geometryKind.startsWith('schematic'))
                        Text(
                          leg.mode == 'WALK'
                              ? 'Jalur penghubung pejalan kaki; bukan navigasi jalan'
                              : 'Urutan stasiun; bukan jalur rel sebenarnya',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.blueGrey,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      SourceInfoButton(
        title: 'Sumber transportasi umum',
        details: journey.attribution,
      ),
    ],
  );
}
