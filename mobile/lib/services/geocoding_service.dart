import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/map_config.dart';
import '../models/location.dart';

/// Represents a geographic place found via geocoding search.
class GeocodedPlace {
  final String name;
  final String displayName;
  final LatLng point;
  final String? type;

  const GeocodedPlace({
    required this.name,
    required this.displayName,
    required this.point,
    this.type,
  });

  factory GeocodedPlace.fromJson(Map<String, dynamic> json) {
    final lat = double.tryParse('${json['lat']}') ?? 0.0;
    final lon = double.tryParse('${json['lon']}') ?? 0.0;
    final name = (json['name'] as String?)?.trim().isNotEmpty == true
        ? json['name'] as String
        : (json['display_name'] as String?)?.split(',').first.trim() ??
              'Location';

    return GeocodedPlace(
      name: name,
      displayName: (json['display_name'] as String?) ?? name,
      point: LatLng(latitude: lat, longitude: lon),
      type: json['type'] as String?,
    );
  }
}

/// Service providing reverse geocoding (coordinates -> real street/district name)
/// and place search for Greater Jakarta using OpenStreetMap Nominatim with caching and offline fallback.
class GeocodingService {
  final http.Client? client;
  final bool useNetwork;

  static final Map<String, String> _reverseCache = {};

  GeocodingService({this.client, bool? useNetwork})
    : useNetwork =
          useNetwork ?? (client != null || !MapConfig.isTestEnvironment);

  /// Resolves exact coordinates to a human-readable street / neighborhood address.
  Future<String> reverseGeocode(LatLng location) async {
    final cacheKey =
        '${location.latitude.toStringAsFixed(3)},${location.longitude.toStringAsFixed(3)}';
    if (_reverseCache.containsKey(cacheKey)) {
      return _reverseCache[cacheKey]!;
    }

    if (!useNetwork) {
      return _offlineFallback(location);
    }

    final httpClient = client ?? http.Client();
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?'
      'lat=${location.latitude}&lon=${location.longitude}&format=jsonv2',
    );

    try {
      final response = await httpClient
          .get(
            url,
            headers: {'User-Agent': 'SUPRA-Jakarta-Transit/1.0 (Mobile App)'},
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;

        final road = address?['road'] as String?;
        final suburb =
            (address?['suburb'] ??
                    address?['village'] ??
                    address?['neighbourhood'])
                as String?;
        final cityDistrict = address?['city_district'] as String?;

        final parts = <String>[];
        if (road != null && road.trim().isNotEmpty) parts.add(road.trim());
        if (suburb != null &&
            suburb.trim().isNotEmpty &&
            !parts.contains(suburb.trim())) {
          parts.add(suburb.trim());
        }
        if (parts.isEmpty && cityDistrict != null) {
          parts.add(cityDistrict.trim());
        }

        final name = (data['name'] as String?)?.trim();
        String result;
        if (name != null && name.isNotEmpty && !parts.contains(name)) {
          result = parts.isNotEmpty ? '$name, ${parts.first}' : name;
        } else if (parts.isNotEmpty) {
          result = parts.join(', ');
        } else {
          result =
              (data['display_name'] as String?)
                  ?.split(',')
                  .take(2)
                  .join(',')
                  .trim() ??
              _offlineFallback(location);
        }

        _reverseCache[cacheKey] = result;
        return result;
      }
    } catch (_) {
      // Fall through to offline fallback on timeout or error
    } finally {
      if (client == null) httpClient.close();
    }

    final fallback = _offlineFallback(location);
    _reverseCache[cacheKey] = fallback;
    return fallback;
  }

  /// Searches for points of interest, streets, or districts within Greater Jakarta.
  Future<List<GeocodedPlace>> searchPlaces(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    // Local instant match first
    final localMatches = greaterJakartaLandmarks
        .where((lm) => lm.name.toLowerCase().contains(cleanQuery.toLowerCase()))
        .map(
          (lm) => GeocodedPlace(
            name: lm.name.split(' (').first,
            displayName: '${lm.name}, ${lm.area}',
            point: lm.point,
            type: 'landmark',
          ),
        )
        .toList();

    if (!useNetwork) {
      return localMatches;
    }

    final httpClient = client ?? http.Client();
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?'
      'q=${Uri.encodeComponent(cleanQuery)}&format=jsonv2&limit=5&countrycodes=id'
      '&viewbox=106.3,-5.8,107.3,-6.9&bounded=1',
    );

    try {
      final response = await httpClient
          .get(
            url,
            headers: {'User-Agent': 'SUPRA-Jakarta-Transit/1.0 (Mobile App)'},
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List?;
        if (list != null && list.isNotEmpty) {
          final results = list
              .map(
                (item) => GeocodedPlace.fromJson(item as Map<String, dynamic>),
              )
              .where((p) => p.point.isInGreaterJakarta)
              .toList();

          // Merge without duplicate coordinates
          final combined = <GeocodedPlace>[...localMatches];
          for (final res in results) {
            if (!combined.any((c) => c.point.distanceTo(res.point) < 0.2)) {
              combined.add(res);
            }
          }
          return combined;
        }
      }
    } catch (_) {
      // Ignore network failures and return local matches
    } finally {
      if (client == null) httpClient.close();
    }

    return localMatches;
  }

  String _offlineFallback(LatLng location) {
    final lm = findNearestLandmark(location);
    if (lm != null) {
      final dist = location.distanceTo(lm.point);
      final cleanName = lm.name.split(' (').first;
      if (dist < 0.8) {
        return lm.name;
      } else {
        return '$cleanName, ${lm.area} (~${dist.toStringAsFixed(1)} km)';
      }
    }
    return 'Point (${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)})';
  }
}
