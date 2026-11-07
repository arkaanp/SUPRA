import 'package:flutter/material.dart';

import '../models/location.dart';
import '../models/route_option.dart';
import '../services/geocoding_service.dart';
import '../services/routing_service.dart';
import '../services/supra_api_service.dart';
import '../services/transit_network.dart';
import '../theme/app_theme.dart';
import '../widgets/interactive_location_map.dart';

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

/// Route planning screen designed to show the optimal commute route based on
/// live traffic congestion, weather (rainfall), and air pollution (PM2.5 / AQI).
/// Features:
/// - Persistent top map (at least half screen, always movable/zoomable even when read-only).
/// - Location input sheet with swipeable top grey bar to expand to full screen.
/// - Clicking a name input opens the map view with search automatically focused in typing mode.
/// - Predictive search autocomplete matching specific venues (e.g., McDonald's, Cibinong, malls).
/// - Vertical "Nearest Locations:" list scrolling top to bottom.
/// - Explicit "Show Route" button to confirm both locations before route and modes are rendered.
/// - Car & Motorcycle route options with traffic, weather, PM2.5, and health advisories (wear mask, etc.).
class TripScreen extends StatefulWidget {
  const TripScreen({super.key});

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final _start = TextEditingController();
  final _destination = TextEditingController();
  final _mapSearchController = TextEditingController();
  final _mapSearchFocusNode = FocusNode();

  final GeocodingService _geocoder = GeocodingService();
  final RoutingService _routingService = RoutingService();
  final GlobalKey<InteractiveLocationMapState> _mapKey =
      GlobalKey<InteractiveLocationMapState>();

  bool _busy = false;

  // Single Map state: Current GPS anchor defaults to Monas (Central Jakarta)
  static const LatLng _defaultCurrentLocation = LatLng(
    latitude: -6.1754,
    longitude: 106.8272,
  );
  LatLng _startCoord = _defaultCurrentLocation;
  LatLng? _destCoord;

  // Bottom box full-screen expansion state (triggered only by swiping grey bar up)
  bool _isSheetExpanded = false;

  // Picking mode state ("Pilih Lewat Peta" with live search & teleport)
  bool _isPickingOnMap = false;
  bool _isPickingStart = false;
  LatLng? _tempTappedPoint;
  String _tempTappedName = 'Tap on map or type above to place pin';
  List<NearbySnapOption> _nearestSnapOptions = [];
  List<GeocodedPlace> _mapSearchResults = [];

  // Search state for main screen
  List<GeocodedPlace> _searchResults = [];

  // Routes state evaluated against traffic, weather, and air pollution
  List<RouteOption> _calculatedRoutes = [];
  RouteOption? _selectedRoute;
  bool _loadingRoutes = false;

  // Destination History sorted by frequency
  static final Map<String, int> _historyFrequencies = {
    'Grand Indonesia Mall': 5,
    'Cibinong City Mall (CCM)': 4,
    'Sudirman CBD (SCBD)': 4,
    'Bundaran HI': 4,
    'McDonald\'s Sarinah Thamrin': 3,
    'Gelora Bung Karno (GBK)': 3,
    'Kemang': 2,
    'Stasiun Gambir': 2,
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
    _mapSearchController.dispose();
    _mapSearchFocusNode.dispose();
    super.dispose();
  }

  void _updateSnapOptions(LatLng tap, {String? customName}) {
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
    for (final st in TransitNetwork.stations) {
      final cleanName = st.name
          .replaceAll('Halte Transjakarta ', 'Halte ')
          .replaceAll('Stasiun KRL ', 'Stasiun ')
          .replaceAll('Stasiun MRT ', 'Stasiun ');
      candidates.add(
        NearbySnapOption(
          name: cleanName,
          point: st.point,
          distanceKm: tap.distanceTo(st.point),
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
      if (unique.length >= 8) break;
    }
    setState(() {
      _nearestSnapOptions = unique;
      if (customName != null && customName.isNotEmpty) {
        _tempTappedName = customName;
      } else if (unique.isNotEmpty) {
        final closest = unique.first;
        final distMeters = (closest.distanceKm * 1000).round();
        _tempTappedName = distMeters < 50
            ? closest.name
            : '${closest.name} (~$distMeters m away)';
      }
    });
  }

  Future<void> _onMapTapped(LatLng tapCoord) async {
    setState(() {
      _tempTappedPoint = tapCoord;
      _mapSearchResults = [];
    });
    _updateSnapOptions(tapCoord);

    try {
      final realAddress = await _geocoder.reverseGeocode(tapCoord);
      if (mounted && _tempTappedPoint == tapCoord) {
        setState(() {
          _tempTappedName = realAddress;
          _mapSearchController.text = realAddress;
        });
      }
    } catch (_) {}
  }

  void _startPickingMode({required bool forStart, bool focusSearch = false}) {
    final initial = forStart ? _startCoord : (_destCoord ?? _startCoord);
    final initialName = forStart
        ? _start.text
        : (_destination.text.isNotEmpty ? _destination.text : '');
    setState(() {
      _isPickingOnMap = true;
      _isPickingStart = forStart;
      _tempTappedPoint = initial;
      _mapSearchController.text = initialName;
      _mapSearchResults = [];
      _isSheetExpanded = false;
      _updateSnapOptions(initial, customName: initialName);
    });
    _mapKey.currentState?.animateToLocation(initial);
    if (focusSearch) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _mapSearchFocusNode.requestFocus();
      });
    }
  }

  void _teleportToPoint(LatLng target, String name) {
    setState(() {
      _tempTappedPoint = target;
      _tempTappedName = name;
      _mapSearchResults = [];
      _mapSearchController.text = name;
      _updateSnapOptions(target, customName: name);
    });
    _mapKey.currentState?.animateToLocation(target);
  }

  Future<void> _teleportToTypedPlace(String query) async {
    if (query.trim().isEmpty) return;
    final results = await _geocoder.searchPlaces(query);
    if (results.isNotEmpty) {
      final chosen = results.first;
      _teleportToPoint(chosen.point, chosen.name);
    }
  }

  void _onMapSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _mapSearchResults = []);
      return;
    }
    final results = await _geocoder.searchPlaces(query);
    if (mounted) {
      setState(() => _mapSearchResults = results);
    }
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
      _mapSearchResults = [];
      // Do not auto-calculate route here so user can freely adjust both locations
    });
  }

  void _selectDestination(String name, LatLng point) {
    setState(() {
      _destCoord = point;
      _destination.text = name;
      _historyFrequencies[name] = (_historyFrequencies[name] ?? 0) + 1;
      _searchResults = [];
    });
  }

  /// Calculates and confirms the route between Start and Destination.
  /// Only called when the user explicitly clicks "Show Route".
  Future<void> _fetchRoutes() async {
    if (_destCoord == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a destination first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
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
      // Remove public transportation option for now as requested
      routes.removeWhere((r) => r.mode == TransportMode.publicTransit);

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

  Color _getRouteColor(TransportMode mode) {
    switch (mode) {
      case TransportMode.car:
        return const Color(0xFF2563EB); // Royal Blue
      case TransportMode.motorcycle:
        return const Color(0xFFF59E0B); // Amber / Orange
      case TransportMode.publicTransit:
        return const Color(0xFF0F766E); // Teal
    }
  }

  Future<void> _startNavigation() async {
    if (_destCoord == null || _selectedRoute == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (SupraService.instance.currentUser != null) {
        await SupraService.instance.createTrip(
          start: _start.text,
          destination: _destination.text,
          departure: DateTime.now(),
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Navigation started: ${_selectedRoute!.title} • Est. ${_selectedRoute!.formattedDuration}',
          ),
          backgroundColor: SupraTheme.brand,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Trip error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedHistory = _historyFrequencies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Flex layout: Map occupies at least half of the screen unless the user swipes
    // the grey bar area to expand the bottom box to full screen.
    final int mapFlex;
    final int sheetFlex;
    if (_isSheetExpanded) {
      mapFlex = 0;
      sheetFlex = 100;
    } else {
      mapFlex = 48;
      sheetFlex = 52;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // =================================================================
            // 1. TOP MAP (Always movable/zoomable even when read-only)
            // =================================================================
            if (!_isSheetExpanded)
              Expanded(
                flex: mapFlex,
                child: Stack(
                  children: [
                    InteractiveLocationMap(
                      key: _mapKey,
                      height: double.infinity,
                      borderRadius: BorderRadius.zero,
                      selectedLocation: _isPickingOnMap
                          ? _tempTappedPoint
                          : (_destCoord ?? _startCoord),
                      secondaryLocation: _isPickingOnMap
                          ? null
                          : (_destCoord != null ? _startCoord : null),
                      selectedLabel: _isPickingOnMap
                          ? (_isPickingStart ? 'S' : 'D')
                          : (_destCoord != null ? 'D' : 'S'),
                      secondaryLabel: _isPickingOnMap ? null : 'S',
                      routeWaypoints: _selectedRoute?.waypoints,
                      routeColor: _selectedRoute != null
                          ? _getRouteColor(_selectedRoute!.mode)
                          : null,
                      isInteractive: _isPickingOnMap,
                      showFooter: false,
                      onLocationChanged: (tapCoord) {
                        if (_isPickingOnMap) {
                          _onMapTapped(tapCoord);
                        }
                      },
                    ),

                    // Map-Picking Top Search & Teleport Bar
                    if (_isPickingOnMap)
                      Positioned(
                        top: 10,
                        left: 10,
                        right: 10,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x2E000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      color: SupraTheme.onSurface,
                                      size: 20,
                                    ),
                                    tooltip: 'Back',
                                    onPressed: () =>
                                        setState(() => _isPickingOnMap = false),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: TextField(
                                      controller: _mapSearchController,
                                      focusNode: _mapSearchFocusNode,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: _isPickingStart
                                            ? 'Type start location to teleport...'
                                            : 'Type destination to teleport...',
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                      ),
                                      onChanged: _onMapSearchChanged,
                                      onSubmitted: (val) =>
                                          _teleportToTypedPlace(val),
                                    ),
                                  ),
                                  if (_mapSearchController.text.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: SupraTheme.textSecondary,
                                      ),
                                      onPressed: () {
                                        _mapSearchController.clear();
                                        setState(() => _mapSearchResults = []);
                                      },
                                      visualDensity: VisualDensity.compact,
                                    )
                                  else
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(
                                        Icons.search,
                                        size: 20,
                                        color: SupraTheme.brand,
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // Live Autocomplete Suggestions dropdown on Map
                            if (_mapSearchResults.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                constraints: const BoxConstraints(
                                  maxHeight: 180,
                                ),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  elevation: 6,
                                  shadowColor: const Color(0x33000000),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    itemCount: _mapSearchResults.length,
                                    separatorBuilder: (context, _) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, i) {
                                      final place = _mapSearchResults[i];
                                      return ListTile(
                                        dense: true,
                                        leading: const Icon(
                                          Icons.location_on,
                                          color: SupraTheme.brand,
                                          size: 18,
                                        ),
                                        title: Text(
                                          place.name,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        subtitle: Text(
                                          place.displayName,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: SupraTheme.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () {
                                          _teleportToPoint(
                                            place.point,
                                            place.name,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                    // Floating Re-Center / GPS Target Button (Bottom-Right)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Material(
                        elevation: 3,
                        shape: const CircleBorder(),
                        color: Colors.white,
                        child: IconButton(
                          icon: const Icon(
                            Icons.my_location,
                            color: SupraTheme.brand,
                            size: 20,
                          ),
                          tooltip: 'Center on my location',
                          onPressed: () {
                            _teleportToPoint(
                              _defaultCurrentLocation,
                              'Monas (Central Jakarta)',
                            );
                          },
                        ),
                      ),
                    ),

                    // Environmental Status Header Badge (Traffic, Weather, PM2.5)
                    if (_selectedRoute != null && !_isPickingOnMap)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🌤️', style: TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              Text(
                                'PM2.5: ${_selectedRoute!.pm25UgM3.toStringAsFixed(0)} µg/m³ • ${_selectedRoute!.rainfallMm > 0 ? "${_selectedRoute!.rainfallMm.toStringAsFixed(1)}mm rain" : "No rain"}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: SupraTheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            // =================================================================
            // 2. BOTTOM SHEET (Trip planner & Environmental Route selector)
            // =================================================================
            Expanded(
              flex: sheetFlex,
              child: Material(
                color: Colors.white,
                borderRadius: _isSheetExpanded
                    ? BorderRadius.zero
                    : const BorderRadius.vertical(top: Radius.circular(22)),
                elevation: 6,
                shadowColor: const Color(0x33000000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Grey Area Swipe Handle Bar
                    _buildSwipeableGreyBar(),

                    // Sheet Body
                    Expanded(
                      child: _buildBottomSheetContent(sortedHistory),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the top grey bar handle that only allows expanding to full screen
  /// when explicitly swiped up, or collapsing when swiped down.
  Widget _buildSwipeableGreyBar() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta != null) {
          if (details.primaryDelta! < -8 && !_isSheetExpanded) {
            setState(() => _isSheetExpanded = true);
          } else if (details.primaryDelta! > 8 && _isSheetExpanded) {
            setState(() => _isSheetExpanded = false);
          }
        }
      },
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -100 && !_isSheetExpanded) {
            setState(() => _isSheetExpanded = true);
          } else if (details.primaryVelocity! > 100 && _isSheetExpanded) {
            setState(() => _isSheetExpanded = false);
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            if (_isSheetExpanded) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _isSheetExpanded = false),
                child: const Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: SupraTheme.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheetContent(List<MapEntry<String, int>> sortedHistory) {
    // -------------------------------------------------------------------------
    // Mode A: "Pilih Lewat Peta" / Pick on Map Confirmation Sheet
    // -------------------------------------------------------------------------
    if (_isPickingOnMap) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Text(
              _isPickingStart
                  ? 'Select start location on map'
                  : 'Select destination on map',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: SupraTheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),

            // Resolved address banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                            fontSize: 12,
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

            // Nearest Locations Section Title (Only says "Nearest Locations:")
            const Text(
              'Nearest Locations:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: SupraTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),

            // Vertical list of nearest locations scrolling from top to bottom
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: _nearestSnapOptions.length,
                separatorBuilder: (context, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final opt = _nearestSnapOptions[i];
                  final isCurrent = _tempTappedPoint == opt.point;
                  final distMeters = (opt.distanceKm * 1000).round();
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0,
                    ),
                    leading: Icon(
                      Icons.place,
                      color: isCurrent
                          ? SupraTheme.brand
                          : SupraTheme.textSecondary,
                      size: 18,
                    ),
                    title: Text(
                      opt.name,
                      style: TextStyle(
                        fontWeight:
                            isCurrent ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 13,
                        color: isCurrent
                            ? SupraTheme.brand
                            : SupraTheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      '$distMeters m away',
                      style: const TextStyle(
                        fontSize: 11,
                        color: SupraTheme.textSecondary,
                      ),
                    ),
                    trailing: isCurrent
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: SupraTheme.brand,
                          )
                        : null,
                    onTap: () {
                      _teleportToPoint(opt.point, opt.name);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 4),

            // Confirm Location Button
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text(
                  'Confirm location',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SupraTheme.brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _confirmPickedLocation,
              ),
            ),
          ],
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Mode B: Environmental Route Options (Traffic, Weather, Air Pollution Evaluation)
    // Only rendered when user explicitly clicked "Show Route"
    // -------------------------------------------------------------------------
    if (_calculatedRoutes.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Route Header Bar (Origin ➔ Destination) with Change Button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00AA13),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _start.text,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 10,
                            color: Color(0xFFEE2737),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _destination.text,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit, size: 14),
                  label: const Text('Change', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    setState(() {
                      _calculatedRoutes = [];
                      _selectedRoute = null;
                    });
                  },
                ),
              ],
            ),
            const Divider(height: 12),

            // List of Environmental Route Options (Car & Motorcycle only)
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: _calculatedRoutes.length,
                separatorBuilder: (context, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final opt = _calculatedRoutes[index];
                  final isSelected = opt.mode == _selectedRoute?.mode;
                  return _buildRouteOptionCard(opt, isSelected);
                },
              ),
            ),
            const SizedBox(height: 8),

            // Primary Navigation Action Button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SupraTheme.brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                onPressed: _busy ? null : _startNavigation,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Start Route Navigation • ${_selectedRoute!.formattedDuration}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Mode C: Initial Origin & Destination Search (with Explicit "Show Route" button)
    // -------------------------------------------------------------------------
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          const Text(
            'Where do you want to go?',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: SupraTheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),

          // Two-Row Location Box: Clicking name input opens map in typing mode!
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                // Pick-up Row (Start)
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00AA13), // Green
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(width: 4, height: 4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _start,
                        readOnly: true,
                        onTap: () => _startPickingMode(
                          forStart: true,
                          focusSearch: true,
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                          hintText: 'Pick-up location',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.map_outlined,
                        size: 18,
                        color: SupraTheme.brand,
                      ),
                      tooltip: 'Select on map',
                      onPressed: () => _startPickingMode(
                        forStart: true,
                        focusSearch: false,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),

                // Connector vertical dots
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      children: List.generate(
                        2,
                        (_) => Container(
                          width: 2,
                          height: 2.5,
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                ),

                // Destination Row: Clicking name input opens map in typing mode!
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 14,
                      color: Color(0xFFEE2737), // Red
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _destination,
                        readOnly: true,
                        onTap: () => _startPickingMode(
                          forStart: false,
                          focusSearch: true,
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                          hintText: 'Where to? (e.g. Cibinong City Mall)',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.map_outlined,
                        size: 18,
                        color: SupraTheme.brand,
                      ),
                      tooltip: 'Select on map',
                      onPressed: () => _startPickingMode(
                        forStart: false,
                        focusSearch: false,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Quick Action Row (Home & Work only - Removed redundant Pick on Map)
          Row(
            children: [
              _buildQuickActionChip(
                icon: Icons.home,
                label: 'Home',
                onTap: () => _selectDestination(
                  'Monas (Central Jakarta)',
                  _defaultCurrentLocation,
                ),
              ),
              const SizedBox(width: 8),
              _buildQuickActionChip(
                icon: Icons.work,
                label: 'Work',
                onTap: () => _selectDestination(
                  'Sudirman CBD (SCBD)',
                  const LatLng(latitude: -6.2250, longitude: 106.8080),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Loading indicator for route calculations
          if (_loadingRoutes)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          // Live autocomplete search dropdown results
          else if (_searchResults.isNotEmpty)
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: _searchResults.length,
                separatorBuilder: (context, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final place = _searchResults[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFF1F5F9),
                      child: Icon(
                        Icons.location_on,
                        size: 14,
                        color: SupraTheme.brand,
                      ),
                    ),
                    title: Text(
                      place.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      place.displayName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SupraTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectDestination(place.name, place.point),
                  );
                },
              ),
            )
          // Recent Destinations History
          else ...[
            const Text(
              'Recent destinations',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: SupraTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),

            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: sortedHistory.length,
                separatorBuilder: (context, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final entry = sortedHistory[i];
                  final lm = greaterJakartaLandmarks.firstWhere(
                    (l) => l.name.startsWith(entry.key.split(' (').first),
                    orElse: () => greaterJakartaLandmarks.first,
                  );
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFF1F5F9),
                      child: Icon(
                        Icons.history,
                        size: 14,
                        color: SupraTheme.textSecondary,
                      ),
                    ),
                    title: Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    subtitle: Text(
                      lm.area,
                      style: const TextStyle(
                        fontSize: 10,
                        color: SupraTheme.textSecondary,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${entry.value}x',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: SupraTheme.textSecondary,
                        ),
                      ),
                    ),
                    onTap: () => _selectDestination(entry.key, lm.point),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 4),

          // Explicit "Show Route" Button: Confirms both locations before displaying route!
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.alt_route, size: 18),
              label: const Text(
                'Show Route',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: SupraTheme.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              onPressed: _destCoord == null ? null : _fetchRoutes,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: SupraTheme.onSurface),
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      backgroundColor: const Color(0xFFF1F5F9),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
      onPressed: onTap,
    );
  }

  Widget _buildRouteOptionCard(RouteOption opt, bool isSelected) {
    IconData icon;
    Color iconColor;
    String modeLabel;
    String vehicleSub;

    switch (opt.mode) {
      case TransportMode.car:
        icon = Icons.directions_car;
        iconColor = const Color(0xFF2563EB);
        modeLabel = 'Car (Automobile)';
        vehicleSub = 'Sealed cabin • Shielded from rain & pollution';
        break;
      case TransportMode.motorcycle:
        icon = Icons.two_wheeler;
        iconColor = const Color(0xFFF59E0B);
        modeLabel = 'Motorcycle (Two-Wheeler)';
        vehicleSub = 'Fastest commute through traffic';
        break;
      case TransportMode.publicTransit:
        icon = Icons.directions_bus;
        iconColor = const Color(0xFF0F766E);
        modeLabel = opt.title;
        vehicleSub = 'Transit';
        break;
    }

    String trafficDesc;
    if (opt.trafficDensity < 0.35) {
      trafficDesc = 'Smooth traffic flow';
    } else if (opt.trafficDensity < 0.65) {
      trafficDesc = 'Moderate congestion';
    } else {
      trafficDesc = 'Heavy traffic delay';
    }

    return InkWell(
      onTap: () {
        setState(() => _selectedRoute = opt);
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? SupraTheme.brand.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? SupraTheme.brand : const Color(0xFFE2E8F0),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: iconColor.withValues(alpha: 0.12),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              modeLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (opt.isRecommended) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'RECOMMENDED',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF166534),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        vehicleSub,
                        style: const TextStyle(
                          fontSize: 10,
                          color: SupraTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      opt.formattedDuration,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: isSelected
                            ? SupraTheme.brand
                            : SupraTheme.onSurface,
                      ),
                    ),
                    Text(
                      '${opt.distanceKm.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontSize: 10,
                        color: SupraTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Environmental signals row (Traffic, Weather, Air Quality)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.traffic,
                        size: 11,
                        color: SupraTheme.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        trafficDesc,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: SupraTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: opt.rainfallMm > 0
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.water_drop_outlined,
                        size: 11,
                        color: opt.rainfallMm > 0
                            ? const Color(0xFF2563EB)
                            : SupraTheme.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        opt.rainfallMm > 0
                            ? '${opt.rainfallMm.toStringAsFixed(1)} mm rain'
                            : '0 mm rain',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: opt.rainfallMm > 0
                              ? const Color(0xFF1D4ED8)
                              : SupraTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: opt.pm25UgM3 >= 35
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.air,
                        size: 11,
                        color: opt.pm25UgM3 >= 35
                            ? const Color(0xFFD97706)
                            : const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'PM2.5: ${opt.pm25UgM3.toStringAsFixed(0)} µg/m³ (${opt.aqiCategory})',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: opt.pm25UgM3 >= 35
                              ? const Color(0xFF92400E)
                              : const Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Health & Safety Advisory
            if (opt.protectiveMeasures.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: opt.mode == TransportMode.motorcycle
                      ? const Color(0xFFFFFBEB)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      opt.mode == TransportMode.motorcycle
                          ? Icons.warning_amber_rounded
                          : Icons.verified_user_outlined,
                      size: 14,
                      color: opt.mode == TransportMode.motorcycle
                          ? const Color(0xFFD97706)
                          : const Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        opt.protectiveMeasures.first,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: opt.mode == TransportMode.motorcycle
                              ? const Color(0xFFB45309)
                              : const Color(0xFF15803D),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
