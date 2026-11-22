import '../utils/display_text.dart';

import 'package:flutter/material.dart';

import 'source_info_button.dart';

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
      title: 'Pilih lokasi di Jabodetabek',
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
        () => _error = 'Masukkan koordinat di Jabodetabek (lintang -6,9 hingga -5,8; bujur 106,3 hingga 107,3).',
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
      if (mounted) setState(() => _error = displayError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SourceInfoButton(
                title: 'Sumber ${title.toLowerCase()}',
                details: [signal.sourceDetails, attributionUrl].join('\n'),
                url: attributionUrl,
              ),
            ],
          ),
          Text(
            '${signalStatusLabel(signal.status)}${signal.kind == null ? '' : ' · ${signalKindLabel(signal.kind)}'}',
          ),
          if (signal.status == 'stale')
            const Text(
              'DATA LAMA — data ini bukan kondisi terkini.',
              style: TextStyle(color: Colors.deepOrange),
            ),
          if (signal.validAt != null)
            Text('Berlaku/diamati: ${_wib(signal.validAt!)}'),
          if (signal.receivedAt != null)
            Text('Diambil: ${_wib(signal.receivedAt!)}'),
          for (final detail in details) Text(detail),
          if (signal.status == 'unavailable') Text('$title tidak tersedia'),
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
        Text('Kondisi lokasi', style: Theme.of(context).textTheme.titleLarge),
        const Text(
          'Data terbaru dari penyedia untuk lokasi ini. Kualitas udara berasal dari stasiun terdekat atau perkiraan model CAMS yang ditandai. Data ini berbeda dari prediksi ML SUPRA dan tidak mencakup seluruh rute.',
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
              label: const Text('Pilih di peta'),
              onPressed: _loading ? null : _pickOnMap,
            ),
            IconButton(
              icon: Icon(
                _showInlineMap ? Icons.layers_clear : Icons.layers_outlined,
                size: 20,
              ),
              tooltip: _showInlineMap ? 'Sembunyikan peta' : 'Tampilkan peta',
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
            labelText: 'Lintang',
            suffixIcon: IconButton(
              icon: const Icon(Icons.pin_drop_outlined),
              tooltip: 'Pilih di peta',
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
            labelText: 'Bujur',
            suffixIcon: IconButton(
              icon: const Icon(Icons.pin_drop_outlined),
              tooltip: 'Pilih di peta',
              onPressed: _loading ? null : _pickOnMap,
            ),
          ),
        ),
        TextField(
          controller: _adm4,
          onChanged: (_) => setState(() => _result = null),
          enabled: !_loading,
          decoration: const InputDecoration(
            labelText: 'Kode kelurahan BMKG (opsional)',
            hintText: '31.71.03.1001',
            helperText: 'Gunakan kode kelurahan yang sesuai untuk sumber cuaca cadangan.',
          ),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _lookup,
          child: Text(_loading ? 'Memuat kondisi…' : 'Muat kondisi'),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (result != null) ...[
          Text(
            'Koordinat: ${result.latitude}, ${result.longitude}\nDiperiksa: ${_wib(result.retrievedAt)}',
          ),
          _signal(
            'Cuaca',
            result.weather,
            [
              if (weather?['temperature_c'] != null)
                'Suhu: ${weather!['temperature_c']} °C',
              if (weather?['humidity_percent'] != null)
                'Kelembapan: ${weather!['humidity_percent']}%',
              if (weather?['description'] != null) '${weather!['description']}',
              if (weather?['wind_speed_kmh'] != null)
                'Angin: ${weather!['wind_speed_kmh']} km/h',
              if (weather?['precipitation_mm'] != null)
                'Curah hujan: ${weather!['precipitation_mm']} mm'
                    '${weather['interval_seconds'] == null ? '' : ' (interval penyedia: ${weather['interval_seconds']} detik)'}',
            ],
            switch (result.weather.source) {
              'bmkg' => 'https://www.bmkg.go.id/',
              'met_norway' => 'https://api.met.no/',
              _ => 'https://open-meteo.com/',
            },
          ),
          _signal(
            'Kualitas udara',
            result.airQuality,
            [
              if (air?['aqi'] != null) 'AQI AS (penyedia): ${air!['aqi']}',
              if (air?['resolution_km'] != null)
                'Resolusi model: sekitar ${air!['resolution_km']} km',
              if (air?['pm25_ug_m3'] != null)
                'PM2.5: ${air!['pm25_ug_m3']} µg/m³',
            ],
            result.airQuality.source == 'open_meteo_cams'
                ? 'https://open-meteo.com/en/docs/air-quality-api'
                : 'https://openaq.org/',
          ),
          _signal('Lalu lintas — ruas jalan terdekat', result.traffic, [
            if (traffic?['speed_kmh'] != null)
              'Kecepatan: ${traffic!['speed_kmh']} km/h (saat lancar ${traffic['free_flow_speed_kmh']} km/h)',
            if (traffic?['travel_time_seconds'] != null)
              'Waktu tempuh ruas: ${traffic!['travel_time_seconds']} detik',
            if (traffic?['confidence'] != null)
              'Tingkat keyakinan penyedia: ${traffic!['confidence']}',
            if (traffic?['road_closed'] == true) 'JALAN DITUTUP',
          ], 'https://www.tomtom.com/'),
        ],
      ],
    );
  }
}
