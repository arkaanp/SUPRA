import 'package:flutter/material.dart';

import '../models/location.dart';
import '../models/trip.dart';
import '../services/supra_api_service.dart';
import '../widgets/interactive_location_map.dart';
import 'map_screen.dart';

class TripScreen extends StatefulWidget {
  const TripScreen({super.key});
  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final _start = TextEditingController();
  final _destination = TextEditingController();
  DateTime? _departure;
  bool _busy = false;
  LatLng? _startCoord;
  LatLng? _destCoord;
  bool _showRouteMap = false;

  @override
  void dispose() {
    _start.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _pickDeparture() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (!mounted || time == null) return;
    setState(
      () => _departure = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _pickLocationOnMap({required bool isStart}) async {
    final current = isStart ? _startCoord : _destCoord;
    final fallback = isStart
        ? const LatLng(latitude: -6.2600, longitude: 106.8150) // Kemang
        : const LatLng(latitude: -6.2250, longitude: 106.8080); // Sudirman

    final picked = await showLocationPickerSheet(
      context: context,
      initialLocation: current ?? fallback,
      title: isStart
          ? 'Select start location on map'
          : 'Select destination on map',
    );

    if (picked != null && mounted) {
      final landmark = findNearestLandmark(picked);
      final label = landmark != null
          ? '${landmark.name} (${picked.latitude.toStringAsFixed(4)}, ${picked.longitude.toStringAsFixed(4)})'
          : 'Point (${picked.latitude.toStringAsFixed(4)}, ${picked.longitude.toStringAsFixed(4)})';

      setState(() {
        if (isStart) {
          _startCoord = picked;
          _start.text = label;
        } else {
          _destCoord = picked;
          _destination.text = label;
        }
        _showRouteMap = true;
      });
    }
  }

  LatLng _resolveCoord(String text, LatLng fallback) {
    // Attempt coordinate extraction: -6.xxx, 106.xxx
    final regExp = RegExp(r'(-?\d+\.\d+)[,\s]+(10\d+\.\d+)');
    final match = regExp.firstMatch(text);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lon = double.tryParse(match.group(2)!);
      if (lat != null && lon != null) {
        return LatLng(latitude: lat, longitude: lon);
      }
    }
    // Landmark name matching
    final lower = text.toLowerCase();
    for (final lm in greaterJakartaLandmarks) {
      final lmName = lm.name.toLowerCase();
      final base = lmName.split(' (').first;
      if (lower.contains(base)) {
        return lm.point;
      }
    }
    return fallback;
  }

  void _viewTripOnMap(Trip trip) {
    final sPoint = _resolveCoord(
      trip.startLocation,
      const LatLng(latitude: -6.2600, longitude: 106.8150),
    );
    final dPoint = _resolveCoord(
      trip.destination,
      const LatLng(latitude: -6.2250, longitude: 106.8080),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapScreen(
          start: sPoint,
          destination: dPoint,
          startName: trip.startLocation,
          destinationName: trip.destination,
        ),
      ),
    );
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Plan a trip', style: Theme.of(context).textTheme.headlineSmall),
      const Text(
        'Trips are saved to your account. Select endpoints manually or through the interactive Greater Jakarta map.',
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add_location_alt_outlined, size: 16),
            label: const Text('Pick on map'),
            onPressed: _busy ? null : () => _pickLocationOnMap(isStart: true),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _showRouteMap ? Icons.layers_clear : Icons.layers_outlined,
            ),
            tooltip: _showRouteMap ? 'Hide map' : 'Show map',
            onPressed: () => setState(() => _showRouteMap = !_showRouteMap),
          ),
        ],
      ),
      if (_showRouteMap) ...[
        const SizedBox(height: 8),
        InteractiveLocationMap(
          height: 200,
          selectedLocation: _startCoord,
          secondaryLocation: _destCoord,
          selectedLabel: 'S',
          secondaryLabel: 'D',
          onLocationChanged: (loc) {
            setState(() {
              if (_startCoord == null || _destCoord != null) {
                _startCoord = loc;
                _destCoord = null;
                final lm = findNearestLandmark(loc);
                _start.text = lm != null
                    ? '${lm.name} (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})'
                    : 'Point (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
              } else {
                _destCoord = loc;
                final lm = findNearestLandmark(loc);
                _destination.text = lm != null
                    ? '${lm.name} (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})'
                    : 'Point (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
              }
            });
          },
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 8),
      TextField(
        controller: _start,
        maxLength: 100,
        decoration: InputDecoration(
          labelText: 'Start location',
          suffixIcon: IconButton(
            icon: const Icon(Icons.pin_drop_outlined),
            tooltip: 'Select on map',
            onPressed: _busy ? null : () => _pickLocationOnMap(isStart: true),
          ),
        ),
      ),
      TextField(
        controller: _destination,
        maxLength: 100,
        decoration: InputDecoration(
          labelText: 'Destination',
          suffixIcon: IconButton(
            icon: const Icon(Icons.pin_drop_outlined),
            tooltip: 'Select on map',
            onPressed: _busy ? null : () => _pickLocationOnMap(isStart: false),
          ),
        ),
      ),
      TextButton(
        onPressed: _busy ? null : _pickDeparture,
        child: Text(
          _departure == null
              ? 'Departure: now (change)'
              : 'Departure: $_departure',
        ),
      ),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.alt_route, size: 18),
              label: const Text('Find best route'),
              onPressed: _busy
                  ? null
                  : () {
                      if (_start.text.trim().isEmpty ||
                          _destination.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter start and destination first.'),
                          ),
                        );
                        return;
                      }
                      final sPoint =
                          _startCoord ??
                          _resolveCoord(
                            _start.text.trim(),
                            const LatLng(
                              latitude: -6.2600,
                              longitude: 106.8150,
                            ),
                          );
                      final dPoint =
                          _destCoord ??
                          _resolveCoord(
                            _destination.text.trim(),
                            const LatLng(
                              latitude: -6.2250,
                              longitude: 106.8080,
                            ),
                          );
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MapScreen(
                            start: sPoint,
                            destination: dPoint,
                            startName: _start.text.trim(),
                            destinationName: _destination.text.trim(),
                          ),
                        ),
                      );
                    },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _perform(() async {
                      if (_start.text.trim().isEmpty ||
                          _destination.text.trim().isEmpty) {
                        throw StateError('Enter start and destination.');
                      }
                      await SupraService.instance.createTrip(
                        start: _start.text.trim(),
                        destination: _destination.text.trim(),
                        departure: _departure ?? DateTime.now(),
                      );
                      _start.clear();
                      _destination.clear();
                      setState(() {
                        _startCoord = null;
                        _destCoord = null;
                      });
                    }),
              child: Text(_busy ? 'Saving…' : 'Save trip'),
            ),
          ),
        ],
      ),
      const Divider(),
      for (final trip in SupraService.instance.trips)
        ListTile(
          title: Text(trip.name),
          subtitle: Text('${trip.plannedDeparture}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.map_outlined),
                tooltip: 'View route on map',
                onPressed: () => _viewTripOnMap(trip),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete trip',
                onPressed: _busy
                    ? null
                    : () => _perform(
                        () => SupraService.instance.deleteTrip(trip.id),
                      ),
              ),
            ],
          ),
        ),
    ],
  );
}
