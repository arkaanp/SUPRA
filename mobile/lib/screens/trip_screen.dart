import 'package:flutter/material.dart';

import '../models/location.dart';
import '../models/route_option.dart';
import '../services/geocoding_service.dart';
import '../services/routing_service.dart';
import '../services/supra_api_service.dart';
import '../services/transit_network.dart';
import '../theme/app_theme.dart';
import '../widgets/interactive_location_map.dart';
import '../widgets/route_planner_view.dart';

class NearbySnapOption {
  final String name;
  final LatLng point;
  final double distanceKm;
  const NearbySnapOption({
    required this.name,
    required this.point,
    required this.distanceKm,
  });
}

class TripScreen extends StatefulWidget {
  const TripScreen({super.key});
  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final _start = TextEditingController();
  final _destination = TextEditingController();
  final GeocodingService _geocoder = GeocodingService();
  final RoutingService _routingService = RoutingService();

  DateTime? _departure;
  bool _busy = false;

  // Single Map state
  static const LatLng _defaultCurrentLocation = LatLng(
    latitude: -6.1754,
    longitude: 106.8272,
  ); // Monas / Central Jakarta (Current GPS Anchor)
  LatLng _startCoord = _defaultCurrentLocation;
  LatLng? _destCoord;

  // Picking mode state ("When the user picks the map, only then the user can tap the location")
  bool _isPickingOnMap = false;
  bool _isPickingStart = false;
  LatLng? _tempTappedPoint;
  String _tempTappedName = 'Tap on map to place pin';
  List<NearbySnapOption> _nearestSnapOptions = [];

  // Search state
  List<GeocodedPlace> _searchResults = [];

  // Routes state
  List<RouteOption> _calculatedRoutes = [];
  RouteOption? _selectedRoute;
  bool _loadingRoutes = false;

  // Destination History sorted by frequency
  static final Map<String, int> _historyFrequencies = {
    'Monas (Central Jakarta)': 5,
    'Sudirman CBD (SCBD)': 4,
    'Bundaran HI': 4,
    'Gelora Bung Karno (GBK)': 3,
    'Grand Indonesia (Thamrin)': 3,
    'Halte Transjakarta Blok M': 2,
    'Stasiun KRL Manggarai': 2,
    'Kemang': 1,
  };

  @override
  void initState() {
    super.initState();
    _start.text = 'Monas (Central Jakarta)';
    _updateSnapOptions(_defaultCurrentLocation);
  }

  @override
  void dispose() {
    _start.dispose();
    _destination.dispose();
    super.dispose();
  }

  void _updateSnapOptions(LatLng tap) {
    final candidates = <NearbySnapOption>[];
    for (final lm in greaterJakartaLandmarks) {
      candidates.add(
        NearbySnapOption(
          name: lm.name.split(' (').first,
          point: lm.point,
          distanceKm: tap.distanceTo(lm.point),
        ),
      );
    }
    for (final s in TransitNetwork.stations) {
      candidates.add(
        NearbySnapOption(
          name: s.name
              .replaceAll('Halte Transjakarta ', '')
              .replaceAll('Stasiun KRL ', '')
              .replaceAll('Stasiun MRT ', '')
              .split(' (')
              .first,
          point: s.point,
          distanceKm: tap.distanceTo(s.point),
        ),
      );
    }
    candidates.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    final unique = <NearbySnapOption>[];
    for (final c in candidates) {
      if (!unique.any(
        (u) => u.name == c.name || u.point.distanceTo(c.point) < 0.12,
      )) {
        unique.add(c);
      }
      if (unique.length >= 5) break;
    }
    setState(() {
      _nearestSnapOptions = unique;
      if (unique.isNotEmpty) {
        final closest = unique.first;
        final distMeters = (closest.distanceKm * 1000).round();
        _tempTappedName = distMeters < 30
            ? closest.name
            : '${closest.name} (~$distMeters m away)';
      }
    });
  }

  void _startPickingMode({required bool forStart}) {
    final initial = forStart ? _startCoord : (_destCoord ?? _startCoord);
    setState(() {
      _isPickingOnMap = true;
      _isPickingStart = forStart;
      _tempTappedPoint = initial;
      _updateSnapOptions(initial);
    });
  }

  void _confirmPickedLocation() {
    if (_tempTappedPoint == null) return;
    final resolved = _tempTappedName.split(' (~').first;
    setState(() {
      if (_isPickingStart) {
        _startCoord = _tempTappedPoint!;
        _start.text = resolved;
      } else {
        _destCoord = _tempTappedPoint!;
        _destination.text = resolved;
        _historyFrequencies[resolved] =
            (_historyFrequencies[resolved] ?? 0) + 1;
      }
      _isPickingOnMap = false;
    });

    if (_destCoord != null) {
      _fetchRoutes();
    }
  }

  void _selectDestination(String name, LatLng point) {
    setState(() {
      _destCoord = point;
      _destination.text = name;
      _historyFrequencies[name] = (_historyFrequencies[name] ?? 0) + 1;
      _searchResults = [];
    });
    _fetchRoutes();
  }

  Future<void> _fetchRoutes() async {
    if (_destCoord == null) return;
    setState(() {
      _loadingRoutes = true;
    });

    try {
      final routes = await _routingService.calculateRoutes(
        start: _startCoord,
        destination: _destCoord!,
        startName: _start.text,
        destinationName: _destination.text,
      );
      if (mounted) {
        setState(() {
          _calculatedRoutes = routes;
          _selectedRoute = routes.firstWhere(
            (r) => r.isRecommended,
            orElse: () => routes.first,
          );
          _loadingRoutes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRoutes = false);
    }
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
  Widget build(BuildContext context) {
    // Sort destination history by frequency descending
    final sortedHistory = _historyFrequencies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===================================================================
          // 1. ONE MAP (Top of the screen)
          // ===================================================================
          if (_isPickingOnMap) ...[
            // Picking Mode Header Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: SupraTheme.brand.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: SupraTheme.brand.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, size: 18, color: SupraTheme.brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isPickingStart
                          ? 'Select start location on map'
                          : 'Select destination on map',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: SupraTheme.brand,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _isPickingOnMap = false),
                    tooltip: 'Cancel',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Interactive Map: Only in picking mode can the user tap the location
            InteractiveLocationMap(
              height: 250,
              selectedLocation: _tempTappedPoint,
              selectedLabel: _isPickingStart ? 'S' : 'D',
              isInteractive: true,
              showFooter: false,
              onLocationChanged: (tapCoord) {
                setState(() => _tempTappedPoint = tapCoord);
                _updateSnapOptions(tapCoord);
              },
            ),
            const SizedBox(height: 8),

            // Nearest Location Readout to the Tap
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SupraTheme.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place, color: SupraTheme.brand, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selected: $_tempTappedName',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_tempTappedPoint != null)
                          Text(
                            'Lat: ${_tempTappedPoint!.latitude.toStringAsFixed(4)}, Lon: ${_tempTappedPoint!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: SupraTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Nearest location options below to show the nearest location names
            // in case the user tap is not accurate
            const Text(
              'Nearest location options (tap to snap if tap was inaccurate):',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: SupraTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _nearestSnapOptions.length,
                separatorBuilder: (context, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final opt = _nearestSnapOptions[i];
                  final isCurrent = _tempTappedPoint == opt.point;
                  return ChoiceChip(
                    label: Text(
                      opt.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isCurrent ? Colors.white : SupraTheme.onSurface,
                      ),
                    ),
                    selected: isCurrent,
                    selectedColor: SupraTheme.brand,
                    backgroundColor: const Color(0xFFF1F5F9),
                    onSelected: (_) {
                      setState(() {
                        _tempTappedPoint = opt.point;
                        _tempTappedName = opt.name;
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            // Confirm Location Button
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Confirm location'),
              onPressed: _confirmPickedLocation,
            ),
            const SizedBox(height: 16),
          ] else ...[
            // Display-only single map ("Here, the map only shows")
            InteractiveLocationMap(
              height: 220,
              selectedLocation: _startCoord,
              secondaryLocation: _destCoord,
              selectedLabel: 'S',
              secondaryLabel: 'D',
              routeWaypoints: _selectedRoute?.waypoints,
              routeColor: _selectedRoute?.mode == TransportMode.publicTransit
                  ? const Color(0xFF2563EB)
                  : (_selectedRoute?.mode == TransportMode.motorcycle
                      ? const Color(0xFFD97706)
                      : const Color(0xFF0F766E)),
              isInteractive: false,
              showFooter: false,
            ),
            const SizedBox(height: 14),
          ],

          // ===================================================================
          // 2. WHERE DO YOU WANT TO GO? (Search Bar & Pick on Map)
          // ===================================================================
          if (!_isPickingOnMap) ...[
            Text(
              'Where do you want to go?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Search a destination, pick on the map, or tap a frequent spot.',
              style: TextStyle(fontSize: 12, color: SupraTheme.textSecondary),
            ),
            const SizedBox(height: 12),

            // Destination Search Bar
            TextField(
              controller: _destination,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: 'Destination',
                hintText: 'Search place, station, or street in Jakarta…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.pin_drop_outlined),
                  tooltip: 'Select on map',
                  onPressed: () => _startPickingMode(forStart: false),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (text) async {
                if (text.trim().length >= 2) {
                  final res = await _geocoder.searchPlaces(text);
                  if (mounted) {
                    setState(() => _searchResults = res);
                  }
                } else {
                  setState(() => _searchResults = []);
                }
              },
            ),

            // Live Autocomplete Suggestions
            if (_searchResults.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: SupraTheme.divider),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  separatorBuilder: (context, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final place = _searchResults[i];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: const Icon(
                        Icons.location_on,
                        size: 18,
                        color: SupraTheme.brand,
                      ),
                      title: Text(
                        place.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      subtitle: Text(
                        place.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: SupraTheme.textSecondary,
                        ),
                      ),
                      onTap: () => _selectDestination(place.name, place.point),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Option to Pick Destination on Map
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined, color: SupraTheme.brand),
                    label: const Text('Pick on map'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _startPickingMode(forStart: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.flag_outlined, color: Color(0xFFEF4444)),
                    label: const Text('Pick dest on map'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _startPickingMode(forStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Start Location Field (Defaulting to user's current location)
            TextField(
              controller: _start,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: 'Start location (defaults to Current Location)',
                prefixIcon: const Icon(Icons.my_location, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.pin_drop_outlined),
                  tooltip: 'Select on map',
                  onPressed: () => _startPickingMode(forStart: true),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) {
                if (_destCoord != null) _fetchRoutes();
              },
            ),
            const SizedBox(height: 6),

            // Quick Departure time
            TextButton.icon(
              icon: const Icon(Icons.access_time, size: 16),
              onPressed: _pickDeparture,
              label: Text(
                _departure == null
                    ? 'Departure: Leave now (change)'
                    : 'Departure: $_departure',
              ),
            ),
            const SizedBox(height: 12),

            // =================================================================
            // 3. ROUTE CHOICES (Embedded directly below the one map!)
            // =================================================================
            if (_loadingRoutes)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_calculatedRoutes.isNotEmpty && _selectedRoute != null) ...[
              RoutePlannerView(
                options: _calculatedRoutes,
                selectedOption: _selectedRoute!,
                onOptionSelected: (newOpt) {
                  setState(() => _selectedRoute = newOpt);
                },
                onConfirmRoute: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Route confirmed: ${_selectedRoute!.title}'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(_busy ? 'Saving…' : 'Save Trip to Account'),
                onPressed: _busy
                    ? null
                    : () {
                        final messenger = ScaffoldMessenger.of(context);
                        _perform(() async {
                          await SupraService.instance.createTrip(
                            start: _start.text,
                            destination: _destination.text,
                            departure: _departure ?? DateTime.now(),
                          );
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Trip saved to account!'),
                              ),
                            );
                          }
                        });
                      },
              ),
              const SizedBox(height: 18),
            ],

            // =================================================================
            // 4. DESTINATION HISTORY SORTED BY FREQUENCY
            // =================================================================
            Row(
              children: const [
                Icon(Icons.history, size: 18, color: SupraTheme.textSecondary),
                SizedBox(width: 6),
                Text(
                  'Frequent & Recent Destinations',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: SupraTheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            for (final entry in sortedHistory)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                elevation: 0,
                color: const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xFFE0F2FE),
                    child: Icon(Icons.place, size: 16, color: SupraTheme.brand),
                  ),
                  title: Text(
                    entry.key.split(' (').first,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    'Visited ${entry.value} time${entry.value > 1 ? "s" : ""}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: SupraTheme.textSecondary,
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                  onTap: () {
                    final matchedLm = greaterJakartaLandmarks.firstWhere(
                      (lm) =>
                          lm.name.toLowerCase().contains(
                                entry.key.toLowerCase().split(' (').first,
                              ),
                      orElse: () => greaterJakartaLandmarks.first,
                    );
                    _selectDestination(entry.key, matchedLm.point);
                  },
                ),
              ),

            // Saved trips section
            if (SupraService.instance.trips.isNotEmpty) ...[
              const Divider(height: 28),
              const Text(
                'Saved Account Trips',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final trip in SupraService.instance.trips)
                ListTile(
                  dense: true,
                  title: Text(trip.name),
                  subtitle: Text('${trip.plannedDeparture}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.alt_route, size: 18),
                        tooltip: 'Load route',
                        onPressed: () {
                          _start.text = trip.startLocation;
                          _destination.text = trip.destination;
                          _fetchRoutes();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
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
          ],
        ],
      ),
    );
  }
}
