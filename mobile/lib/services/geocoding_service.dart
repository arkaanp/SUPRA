import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/map_config.dart';
import '../models/location.dart';
import 'transit_network.dart';

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
    final lat = double.tryParse('${json['lat']}');
    final lon = double.tryParse('${json['lon']}');
    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      throw const FormatException('Invalid place coordinates');
    }
    final display = json['display_name'] as String? ?? '';
    final name = json['name'] as String?;
    return GeocodedPlace(
      name: name?.isNotEmpty == true ? name! : display.split(',').first,
      displayName: display,
      point: LatLng(latitude: lat, longitude: lon),
      type: json['type'] as String?,
    );
  }
}

/// Local autocomplete; explicit remote search. Public Nominatim is not an
/// autocomplete service. Never creates a place when the provider finds none.
class GeocodingService {
  GeocodingService({
    this.client,
    bool? useNetwork,
    this.baseUrl = const String.fromEnvironment(
      'GEOCODING_BASE_URL',
      defaultValue: 'https://nominatim.openstreetmap.org',
    ),
  }) : useNetwork =
           useNetwork ?? (client != null || !MapConfig.isTestEnvironment);
  final http.Client? client;
  final bool useNetwork;
  final String baseUrl;
  static Future<void> _queue = Future.value();
  static final _reverseCache = <String, String>{};
  static final _searchCache = <String, (DateTime, List<GeocodedPlace>)>{};

  Future<http.Response> _get(http.Client client, Uri uri) {
    final request = _queue.then(
      (_) => client
          .get(uri, headers: {'User-Agent': 'SUPRA-Jakarta-Transit/1.0'})
          .timeout(const Duration(seconds: 5)),
    );
    _queue = request
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) => Future<void>.delayed(const Duration(milliseconds: 1100)));
    return request;
  }

  Future<String> reverseGeocode(LatLng location) async {
    final fallback =
        'Point (${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)})';
    if (!useNetwork) return fallback;
    final key = '$baseUrl:${location.latitude},${location.longitude}';
    if (_reverseCache.containsKey(key)) return _reverseCache[key]!;
    final httpClient = client ?? http.Client();
    try {
      final response = await _get(
        httpClient,
        Uri.parse('$baseUrl/reverse').replace(
          queryParameters: {
            'lat': '${location.latitude}',
            'lon': '${location.longitude}',
            'format': 'jsonv2',
          },
        ),
      );
      if (response.statusCode != 200) return fallback;
      final value = jsonDecode(response.body) as Map<String, dynamic>;
      final name = value['display_name'];
      if (name is! String || name.isEmpty) return fallback;
      if (_reverseCache.length >= 128) {
        _reverseCache.remove(_reverseCache.keys.first);
      }
      _reverseCache[key] = name;
      return name;
    } catch (_) {
      return fallback;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  Future<List<GeocodedPlace>> searchPlaces(
    String query, {
    bool remote = true,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final lower = q.toLowerCase();
    final local = <GeocodedPlace>[
      for (final place in greaterJakartaLandmarks)
        if (place.name.toLowerCase().contains(lower) ||
            place.area.toLowerCase().contains(lower))
          GeocodedPlace(
            name: place.name,
            displayName: '${place.name}, ${place.area}',
            point: place.point,
            type: 'landmark',
          ),
      for (final station in TransitNetwork.stations)
        if (station.name.toLowerCase().contains(lower))
          GeocodedPlace(
            name: station.name,
            displayName: '${station.name} (${station.line})',
            point: station.point,
            type: 'transit',
          ),
    ];
    if (useNetwork && remote) {
      final cacheKey = '$baseUrl:$lower';
      final cached = _searchCache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) {
        return cached.$2;
      }
      final httpClient = client ?? http.Client();
      try {
        final response = await _get(
          httpClient,
          Uri.parse('$baseUrl/search').replace(
            queryParameters: {
              'q': q,
              'format': 'jsonv2',
              'limit': '8',
              'countrycodes': 'id',
              'viewbox': '106.3,-5.8,107.3,-6.9',
              'bounded': '1',
            },
          ),
        );
        if (response.statusCode != 200) {
          throw StateError('Location provider unavailable');
        }
        final values = jsonDecode(response.body) as List;
        final network = <GeocodedPlace>[];
        for (final value in values) {
          try {
            final place = GeocodedPlace.fromJson(value as Map<String, dynamic>);
            if (place.point.isInGreaterJakarta) network.add(place);
          } catch (_) {
            /* Reject malformed provider results. */
          }
        }
        // Provider results lead; exact local names remain discoverable.
        local.insertAll(0, network);
        final result = _rank(local, lower);
        if (_searchCache.length >= 32) {
          _searchCache.remove(_searchCache.keys.first);
        }
        _searchCache[cacheKey] = (DateTime.now(), result);
        return result;
      } catch (_) {
        if (local.isEmpty) {
          throw StateError(
            'Location search unavailable. Retry or choose on the map.',
          );
        }
      } finally {
        if (client == null) httpClient.close();
      }
    }
    return _rank(local, lower);
  }

  List<GeocodedPlace> _rank(List<GeocodedPlace> places, String query) {
    int rank(GeocodedPlace p) => p.name.toLowerCase() == query
        ? 0
        : p.name.toLowerCase().startsWith(query)
        ? 1
        : 2;
    places.sort((a, b) => rank(a).compareTo(rank(b)));
    final result = <GeocodedPlace>[];
    for (final p in places) {
      if (!result.any(
        (r) => r.name == p.name && r.point.distanceTo(p.point) < 0.05,
      )) {
        result.add(p);
      }
    }
    return result;
  }
}
