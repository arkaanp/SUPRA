import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/current_conditions.dart';
import '../models/location.dart';
import '../services/conditions_repository.dart';
import 'interactive_location_map.dart';

/// Explicit lookups only: do not poll paid providers on every rebuild/tab change.
class CurrentConditionsPanel extends StatefulWidget {
  const CurrentConditionsPanel({super.key, this.load});
  final Future<CurrentConditions> Function(
    double latitude,
    double longitude,
    String? adm4,
  )?
  load;
  @override
  State<CurrentConditionsPanel> createState() => _CurrentConditionsPanelState();
}

class _CurrentConditionsPanelState extends State<CurrentConditionsPanel> {
  final _lat = TextEditingController(text: '-6.2');
  final _lon = TextEditingController(text: '106.82');
  final _adm4 = TextEditingController();
  CurrentConditions? _result;
  bool _loading = false;
  String? _error;
  bool _showInlineMap = false;
  late final ConditionsRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = widget.load == null
        ? ConditionsRepository.instance
        : ConditionsRepository(
            load: (point) => widget.load!(
              point.latitude,
              point.longitude,
              _adm4.text.trim().isEmpty ? null : _adm4.text.trim(),
            ),
          );
  }

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    _adm4.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final curLat = double.tryParse(_lat.text.trim()) ?? -6.2;
    final curLon = double.tryParse(_lon.text.trim()) ?? 106.82;
    final initial = LatLng(latitude: curLat, longitude: curLon);

    final picked = await showLocationPickerSheet(
      context: context,
      initialLocation: initial.isInGreaterJakarta
          ? initial
          : const LatLng(latitude: -6.2, longitude: 106.82),
      title: 'Select location in Greater Jakarta',
    );

    if (picked != null && mounted) {
      setState(() {
        _lat.text = picked.latitude.toStringAsFixed(4);
        _lon.text = picked.longitude.toStringAsFixed(4);
        // A nearby landmark does not establish the selected village boundary.
        _adm4.clear();
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _lookup() async {
    final lat = double.tryParse(_lat.text.trim());
    final lon = double.tryParse(_lon.text.trim());
    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat < -6.9 ||
        lat > -5.8 ||
        lon < 106.3 ||
        lon > 107.3) {
      setState(
        () => _error = 'Enter coordinates in Greater Jakarta (latitude -6.9 to -5.8, longitude 106.3 to 107.3).',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.at(
        LatLng(latitude: lat, longitude: lon),
        adm4: _adm4.text.trim().isEmpty ? null : _adm4.text.trim(),
        refresh: true,
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url))) {
        throw StateError('Could not open source link.');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Source: $url')));
      }
    }
  }

  String _wib(DateTime time) =>
      '${time.toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 16).replaceAll('T', ' ')} WIB';

  Widget _signal(
    String title,
    ConditionSignal signal,
    List<String> details,
    String attributionUrl,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(
            '${signal.source} · ${signal.status}${signal.kind == null ? '' : ' · ${signal.kind!.replaceAll('_', ' ')}'}',
          ),
          if (signal.status == 'stale')
            const Text(
              'STALE — do not treat this reading as current.',
              style: TextStyle(color: Colors.deepOrange),
            ),
          if (signal.validAt != null)
            Text('Valid/observed: ${_wib(signal.validAt!)}'),
          if (signal.receivedAt != null)
            Text('Fetched: ${_wib(signal.receivedAt!)}'),
          for (final detail in details) Text(detail),
          Text(
            signal.message == 'not_configured'
                ? 'Provider key is not configured on the backend.'
                : signal.message,
          ),
          TextButton(
            onPressed: () => _open(attributionUrl),
            child: const Text('Source / attribution'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final weather = result?.weather.data;
    final air = result?.airQuality.data;
    final traffic = result?.traffic.data;

    final curLat = double.tryParse(_lat.text.trim());
    final curLon = double.tryParse(_lon.text.trim());
    final currentLoc =
        (curLat != null &&
            curLon != null &&
            curLat.isFinite &&
            curLon.isFinite &&
            curLat >= -6.9 &&
            curLat <= -5.8 &&
            curLon >= 106.3 &&
            curLon <= 107.3)
        ? LatLng(latitude: curLat, longitude: curLon)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Location conditions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Latest available provider data, not Supra ML predictions or route-wide conditions. Air quality is a nearby station PM2.5 reading, not a computed AQI.',
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      _lat.text = '-6.2';
                      _lon.text = '106.82';
                      _adm4.clear();
                      _result = null;
                      _error = null;
                    }),
              child: const Text('Jakarta'),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      _lat.text = '-6.6';
                      _lon.text = '106.8';
                      _adm4.clear();
                      _result = null;
                      _error = null;
                    }),
              child: const Text('Bogor'),
            ),
            TextButton.icon(
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Pick on map'),
              onPressed: _loading ? null : _pickOnMap,
            ),
            IconButton(
              icon: Icon(
                _showInlineMap ? Icons.layers_clear : Icons.layers_outlined,
                size: 20,
              ),
              tooltip: _showInlineMap ? 'Hide map' : 'Show map',
              onPressed: () => setState(() => _showInlineMap = !_showInlineMap),
            ),
          ],
        ),
        if (_showInlineMap) ...[
          InteractiveLocationMap(
            height: 220,
            selectedLocation: currentLoc,
            isInteractive: !_loading,
            onLocationChanged: (location) {
              setState(() {
                _lat.text = location.latitude.toStringAsFixed(4);
                _lon.text = location.longitude.toStringAsFixed(4);
                _adm4.clear();
                _result = null;
                _error = null;
              });
            },
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _lat,
          onChanged: (_) => setState(() {
            _result = null;
            _adm4.clear();
          }),
          enabled: !_loading,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(
            labelText: 'Latitude',
            suffixIcon: IconButton(
              icon: const Icon(Icons.pin_drop_outlined),
              tooltip: 'Select on map',
              onPressed: _loading ? null : _pickOnMap,
            ),
          ),
        ),
        TextField(
          controller: _lon,
          onChanged: (_) => setState(() {
            _result = null;
            _adm4.clear();
          }),
          enabled: !_loading,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(
            labelText: 'Longitude',
            suffixIcon: IconButton(
              icon: const Icon(Icons.pin_drop_outlined),
              tooltip: 'Select on map',
              onPressed: _loading ? null : _pickOnMap,
            ),
          ),
        ),
        TextField(
          controller: _adm4,
          onChanged: (_) => setState(() => _result = null),
          enabled: !_loading,
          decoration: const InputDecoration(
            labelText: 'BMKG village adm4 (optional)',
            hintText: '31.71.03.1001',
            helperText: 'Use the matching village code for a weather fallback.',
          ),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _lookup,
          child: Text(_loading ? 'Loading conditions…' : 'Load conditions'),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (result != null) ...[
          Text(
            'Requested: ${result.latitude}, ${result.longitude}\nRetrieved: ${_wib(result.retrievedAt)}',
          ),
          _signal(
            'Weather',
            result.weather,
            [
              if (weather?['temperature_c'] != null)
                'Temperature: ${weather!['temperature_c']} °C',
              if (weather?['humidity_percent'] != null)
                'Humidity: ${weather!['humidity_percent']}%',
              if (weather?['description'] != null) '${weather!['description']}',
              if (weather?['wind_speed_kmh'] != null)
                'Wind: ${weather!['wind_speed_kmh']} km/h',
              if (weather?['precipitation_mm'] != null)
                'Precipitation: ${weather!['precipitation_mm']} mm (provider interval: ${weather['interval_seconds']} seconds)',
            ],
            result.weather.source == 'bmkg'
                ? 'https://www.bmkg.go.id/'
                : 'https://open-meteo.com/',
          ),
          _signal('Air quality (PM2.5)', result.airQuality, [
            if (air?['pm25_ug_m3'] != null)
              'PM2.5: ${air!['pm25_ug_m3']} µg/m³',
            if (air?['station_name'] != null)
              'Station: ${air!['station_name']}',
            if (air?['distance_km'] is num)
              'Station distance: ${(air!['distance_km'] as num).toStringAsFixed(1)} km',
            if (air?['provider']?['name'] != null)
              'Provider: ${air!['provider']['name']}',
            if (air?['owner']?['name'] != null)
              'Owner: ${air!['owner']['name']}',
            if (air?['licenses'] is List) ...[
              for (final license in air!['licenses'] as List)
                'License: ${license['name'] ?? 'See source terms'}${license['attribution']?['name'] == null ? '' : ' · ${license['attribution']['name']}'}',
            ],
          ], 'https://openaq.org/'),
          _signal('Traffic — nearest road fragment', result.traffic, [
            if (traffic?['speed_kmh'] != null)
              'Speed: ${traffic!['speed_kmh']} km/h (free flow ${traffic['free_flow_speed_kmh']} km/h)',
            if (traffic?['travel_time_seconds'] != null)
              'Fragment travel time: ${traffic!['travel_time_seconds']} seconds',
            if (traffic?['confidence'] != null)
              'Provider confidence: ${traffic!['confidence']}',
            if (traffic?['road_closed'] == true) 'ROAD CLOSED',
          ], 'https://www.tomtom.com/'),
        ],
      ],
    );
  }
}
