import 'dart:async';

import 'package:flutter/material.dart';

import '../models/location.dart';
import '../models/route_option.dart';
import '../models/saved_trip.dart';
import '../models/commute.dart';
import '../services/geocoding_service.dart';
import '../services/routing_service.dart';
import '../services/supra_api_service.dart';
import '../services/transit_network.dart';
import '../services/commute_recommendations.dart';
import '../services/display_preferences.dart';
import 'commutes_screen.dart';
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

/// Driving-route planner with explicit place selection and provider provenance.
/// Features:
/// - Persistent top map (at least half screen, always movable/zoomable even when read-only).
/// - Location input sheet with swipeable top grey bar to expand to full screen.
/// - Clicking a name input opens the map view with search automatically focused in typing mode.
/// - Predictive search autocomplete matching specific venues (e.g., McDonald's, Cibinong, malls).
/// - Vertical "Nearest Locations:" list scrolling top to bottom.
/// - Explicit "Show Route" button to confirm both locations before route and modes are rendered.
/// - Only configured routing modes are offered; no synthetic offline routes.
class TripScreen extends StatefulWidget {
  const TripScreen({super.key, this.geocodingService, this.routingService});
  final GeocodingService? geocodingService;
  final RoutingService? routingService;

  @override
  State<TripScreen> createState() => TripScreenState();
}

class TripScreenState extends State<TripScreen> {
  final _start = TextEditingController();
  final _destination = TextEditingController();
  final _mapSearchController = TextEditingController();
  final _mapSearchFocusNode = FocusNode();

  late final GeocodingService _geocoder;
  late final RoutingService _routingService;
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
  Timer? _searchDebounce;
  int _searchGeneration = 0;

  // Search state for main screen
  List<GeocodedPlace> _searchResults = [];

  // Routes state evaluated against traffic, weather, and air pollution
  List<RouteOption> _calculatedRoutes = [];
  RouteOption? _selectedRoute;
  bool _loadingRoutes = false;
  int _routeGeneration = 0;
  TransportMode _requestedMode = TransportMode.car;
  String? _routeKey;
  String? _activeTripId;

  // Trip History sorting state (Recent vs Frequency)
  TripHistorySort _historySort = TripHistorySort.recent;

  @override
  void initState() {
    super.initState();
    _geocoder = widget.geocodingService ?? GeocodingService();
    _routingService = widget.routingService ?? RoutingService();
    _start.text = 'Monas (Central Jakarta)';
    _updateSnapOptions(_defaultCurrentLocation);
    TripHistoryStore.instance.addListener(_onTripHistoryStoreChanged);
    DisplayPreferences.instance.addListener(_onDisplayPreferenceChanged);
    DisplayPreferences.instance.load();
  }

  void _onTripHistoryStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onDisplayPreferenceChanged() {
    if (mounted) setState(() {});
  }

  bool get _showMl => DisplayPreferences.instance.showMlPredictions;

  /// Loads start and destination for a trip, resolves their coordinates, and shows the route.
  Future<void> loadAndShowRoute({
    required String start,
    required String destination,
    LatLng? startPoint,
    LatLng? destPoint,
    String? mode,
  }) async {
    if (mode != null) {
      _requestedMode = TransportMode.values.firstWhere(
        (m) => m.apiValue == mode,
        orElse: () => TransportMode.car,
      );
    }
    _start.text = start;
    _destination.text = destination;

    if (startPoint == null || destPoint == null) {
      setState(() {
        _destCoord = null;
        _calculatedRoutes = [];
        _selectedRoute = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This planned trip has no confirmed coordinates. Select both locations first.',
          ),
        ),
      );
      return;
    }
    _startCoord = startPoint;
    _destCoord = destPoint;

    if (mounted && _destCoord != null) {
      await _fetchRoutes();
    }
  }

  @override
  void dispose() {
    TripHistoryStore.instance.removeListener(_onTripHistoryStoreChanged);
    DisplayPreferences.instance.removeListener(_onDisplayPreferenceChanged);
    _topNotificationTimer?.cancel();
    _searchDebounce?.cancel();
    _searchGeneration++;
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
    _searchDebounce?.cancel();
    _searchGeneration++;
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
    _searchDebounce?.cancel();
    _searchGeneration++;
    _routeGeneration++;
    _loadingRoutes = false;
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
      _selectedRoute = null;
      _calculatedRoutes = [];
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
    _searchDebounce?.cancel();
    _searchGeneration++;
    setState(() {
      _tempTappedPoint = target;
      _tempTappedName = name;
      _mapSearchResults = [];
      _mapSearchController.text = name;
      _updateSnapOptions(target, customName: name);
    });
    _mapKey.currentState?.animateToLocation(target);
  }

  void _choosePlaceAndConfirm(GeocodedPlace place) {
    _searchDebounce?.cancel();
    _searchGeneration++;
    setState(() {
      if (_isPickingStart) {
        _startCoord = place.point;
        _start.text = place.name;
      } else {
        _destCoord = place.point;
        _destination.text = place.name;
      }
      _isPickingOnMap = false;
      _mapSearchResults = [];
      _tempTappedPoint = place.point;
      _tempTappedName = place.name;
      _mapSearchController.text = place.name;
      _selectedRoute = null;
      _calculatedRoutes = [];
      _isTrackingActive = false;
    });
    _mapKey.currentState?.animateToLocation(place.point);
  }

  Future<void> _chooseTypedPlaceAndConfirm(String query) async {
    if (query.trim().isEmpty) return;
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    try {
      final results = await _geocoder.searchPlaces(query);
      if (!mounted || generation != _searchGeneration || !_isPickingOnMap) {
        return;
      }
      setState(() => _mapSearchResults = results);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            results.isEmpty
                ? 'No matching places. Try a fuller address or choose on the map.'
                : 'Select a search result to confirm its location.',
          ),
        ),
      );
    } catch (error) {
      if (mounted && generation == _searchGeneration) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  void _onMapSearchChanged(String query) {
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _mapSearchResults = [];
      _tempTappedPoint = null;
    });
    if (query.trim().isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await _geocoder.searchPlaces(query, remote: false);
      if (mounted && generation == _searchGeneration && _isPickingOnMap) {
        setState(() => _mapSearchResults = results);
      }
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
      _searchResults = [];
    });
  }

  Future<void> _useSavedPlace(String kind) async {
    try {
      final List<SavedPlace> places = await SupraService.instance
          .getSavedPlaces();
      if (!mounted) return;
      final matches = places.where((p) => p.kind == kind);
      if (matches.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save a $kind location first.')));
        await _openCommutes();
        return;
      }
      _selectDestination(matches.first.label, matches.first.point);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _openCommutes() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CommutesScreen(
        onPlan: (origin, destination, mode) {
          _requestedMode = TransportMode.values.firstWhere(
            (m) => m.apiValue == mode,
            orElse: () => TransportMode.car,
          );
          loadAndShowRoute(
            start: origin.label,
            destination: destination.label,
            startPoint: origin.point,
            destPoint: destination.point,
          );
        },
      ),
    ),
  );

  Widget _modeSelector() => DropdownButton<TransportMode>(
    value: _requestedMode,
    isExpanded: true,
    underline: const SizedBox.shrink(),
    style: const TextStyle(fontSize: 12, color: SupraTheme.onSurface),
    items: [
      for (final mode in TransportMode.values)
        DropdownMenuItem(
          value: mode,
          child: Text(
            '${mode.iconEmoji} ${mode.shortName}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: _loadingRoutes || _busy
        ? null
        : (mode) {
            if (mode == null) return;
            final hadRoutes = _calculatedRoutes.isNotEmpty;
            setState(() => _requestedMode = mode);
            if (hadRoutes) _fetchRoutes();
          },
  );

  /// Selects a historical trip from Trip History and loads/renders its route
  void _selectTripHistoryItem(SavedTrip trip) {
    setState(() {
      _requestedMode = TransportMode.values.firstWhere(
        (m) => m.apiValue == trip.mode,
        orElse: () => TransportMode.car,
      );
      _start.text = trip.start;
      _startCoord = trip.startPoint;
      _destination.text = trip.destination;
      _destCoord = trip.destPoint;
      _searchResults = [];
    });
    _fetchRoutes();
  }

  /// Handles deleting or reducing frequency of a trip item
  void _handleDeleteTrip(SavedTrip trip) {
    if (_busy) return;
    if (trip.frequency > 1) {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    trip.routeLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: SupraTheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current frequency: ${trip.frequency} trips recorded',
                    style: const TextStyle(
                      fontSize: 12,
                      color: SupraTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEFF6FF),
                      child: Icon(
                        Icons.exposure_minus_1,
                        color: SupraTheme.brand,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Reduce frequency (-1)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      'Decrease count from ${trip.frequency}x to ${trip.frequency - 1}x',
                      style: const TextStyle(
                        fontSize: 11,
                        color: SupraTheme.textSecondary,
                      ),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      if (!await _deleteHistoryEvents(trip.eventIds.take(1))) {
                        return;
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Reduced frequency for "${trip.destination}" to ${trip.frequency - 1}x',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFEE2E2),
                      child: Icon(
                        Icons.delete_forever,
                        color: Color(0xFFDC2626),
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Delete trip completely',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    subtitle: const Text(
                      'Remove this route entirely from Trip History',
                      style: TextStyle(
                        fontSize: 11,
                        color: SupraTheme.textSecondary,
                      ),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      if (!await _deleteHistoryEvents(trip.eventIds)) return;
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Deleted "${trip.destination}" from history',
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      _deleteHistoryEvents(trip.eventIds);
    }
  }

  Future<bool> _deleteHistoryEvents(Iterable<String> ids) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      for (final id in ids.toList()) {
        await SupraService.instance.deleteTrip(id);
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete trip: $error')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final generation = ++_routeGeneration;
    final key =
        '${_startCoord.latitude},${_startCoord.longitude}:${_destCoord!.latitude},${_destCoord!.longitude}';
    final previous = _routeKey == key
        ? List<RouteOption>.of(_calculatedRoutes)
        : <RouteOption>[];
    setState(() {
      _loadingRoutes = true;
      _isTrackingActive = false;
      _calculatedRoutes = [];
      _selectedRoute = null;
    });

    try {
      final fetched = await _routingService.calculateMode(
        start: _startCoord,
        destination: _destCoord!,
        mode: _requestedMode,
      );
      final routes = CommuteRecommendations.rank([
        ...previous.where((r) => r.mode != _requestedMode),
        ...fetched,
      ]);

      if (mounted && generation == _routeGeneration) {
        setState(() {
          _calculatedRoutes = routes;
          _routeKey = key;
          _selectedRoute = routes.firstWhere(
            (r) => r.mode == _requestedMode,
            orElse: () => routes.first,
          );
          _loadingRoutes = false;
        });

        // When show route is finished, center and zoom in/out the view such that it shows the whole route
        final points = _selectedRoute?.waypoints ?? [_startCoord, _destCoord!];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapKey.currentState?.fitToRoute(points);
        });
      }
    } catch (_) {
      if (mounted && generation == _routeGeneration) {
        setState(() {
          _loadingRoutes = false;
          _calculatedRoutes = previous;
          _selectedRoute = previous.isEmpty ? null : previous.first;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Route unavailable. Check your connection/provider configuration. Transit requires a Jakarta GTFS planner. No estimated route has been substituted.',
            ),
          ),
        );
      }
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
      case TransportMode.walk:
        return const Color(0xFF7C3AED);
    }
  }

  bool _isTrackingActive = false;

  // Floating top notification popup state (never blocks the bottom sheet/buttons)
  String? _topNotificationMessage;
  IconData? _topNotificationIcon;
  Color _topNotificationColor = SupraTheme.brand;
  Timer? _topNotificationTimer;

  void _showTopNotification({
    required String message,
    IconData icon = Icons.navigation_rounded,
    Color color = SupraTheme.brand,
    Duration duration = const Duration(seconds: 4),
  }) {
    _topNotificationTimer?.cancel();
    setState(() {
      _topNotificationMessage = message;
      _topNotificationIcon = icon;
      _topNotificationColor = color;
    });
    _topNotificationTimer = Timer(duration, () {
      if (mounted) {
        setState(() {
          _topNotificationMessage = null;
        });
      }
    });
  }

  void _dismissTopNotification() {
    _topNotificationTimer?.cancel();
    if (mounted) {
      setState(() {
        _topNotificationMessage = null;
      });
    }
  }

  /// Confirms the trip: saves to TripHistoryStore and backend, focuses map
  /// camera on the start location, and begins tracking user location towards destination.
  Future<void> _confirmTripAndStartTracking() async {
    if (_busy || _destCoord == null || _selectedRoute == null) return;
    setState(() {
      _busy = true;
    });
    final startName = _start.text;
    final destName = _destination.text;
    try {
      // Only a successful backend confirmation becomes history.
      final trip = await SupraService.instance.createTrip(
        start: startName,
        destination: destName,
        departure: DateTime.now(),
        startPoint: _startCoord,
        destPoint: _destCoord!,
        mode: _selectedRoute!.mode.apiValue,
        routeWaypoints: _selectedRoute!.waypoints,
      );
      _activeTripId = trip.id;
      if (!mounted) return;
      setState(() => _isTrackingActive = true);

      // 3. Focus on the start location to begin tracking location
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapKey.currentState?.animateToLocation(_startCoord);
      });

      // 4. Confirmation notification displayed on top (not blocking the bottom buttons)
      if (mounted) {
        _showTopNotification(
          message:
              'Trip saved: $startName → $destName. Route preview active (not live GPS navigation).',
          icon: Icons.navigation_rounded,
          color: SupraTheme.brand,
        );
      }
    } catch (e) {
      if (mounted) {
        _showTopNotification(
          message: 'Trip could not be saved: $e',
          icon: Icons.error_outline,
          color: const Color(0xFFEF4444),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prompts a confirmation dialog before cancelling live trip tracking to prevent accidental touches.
  Future<void> _promptCancelTrackingConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: const [
              Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFDC2626),
                size: 24,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Close Route Preview?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: SupraTheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Close this route preview to ${_destination.text}? Your confirmed trip remains in history. Live GPS navigation is not connected.',
            style: const TextStyle(
              fontSize: 13,
              color: SupraTheme.textSecondary,
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Keep Preview',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: SupraTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                minimumSize: const Size(128, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Close Preview',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      _cancelTracking();
    }
  }

  /// Cancels active trip tracking, restoring the Confirm button and re-centering camera to full route.
  Future<void> _cancelTracking() async {
    if (_activeTripId != null) {
      try {
        await SupraService.instance.finishTrip(_activeTripId!);
      } catch (e) {
        if (mounted) {
          _showTopNotification(message: 'Could not finish trip alerts: $e');
        }
        return;
      }
      _activeTripId = null;
    }
    if (!mounted) return;
    setState(() {
      _isTrackingActive = false;
    });
    final routeWaypoints =
        _selectedRoute?.waypoints ??
        (_destCoord != null ? [_startCoord, _destCoord!] : [_startCoord]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapKey.currentState?.fitToRoute(routeWaypoints);
    });
    _showTopNotification(
      message: 'Route preview closed',
      icon: Icons.info_outline,
      color: const Color(0xFF475569),
    );
  }

  /// Builds a floating top notification popup that displays confirmations
  /// without obstructing or blocking the bottom sheet and action buttons.
  Widget _buildTopNotificationPopup() {
    if (_topNotificationMessage == null) return const SizedBox.shrink();

    return Positioned(
      top: 10,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _topNotificationColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_topNotificationIcon != null) ...[
                Icon(_topNotificationIcon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  _topNotificationMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _dismissTopNotification,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, color: Colors.white70, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedTrips = TripHistoryStore.instance.getSortedTrips(_historySort);

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
        child: Stack(
          children: [
            Column(
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
                                        onPressed: () => setState(
                                          () => _isPickingOnMap = false,
                                        ),
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
                                                ? 'Search start (Enter to search online)'
                                                : 'Search destination (Enter to search online)',
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 8,
                                                ),
                                          ),
                                          onChanged: _onMapSearchChanged,
                                          onSubmitted: (val) =>
                                              _chooseTypedPlaceAndConfirm(val),
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
                                            _onMapSearchChanged('');
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
                                              _choosePlaceAndConfirm(place);
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
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 240),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '🌤️',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '${_selectedRoute!.pm25Label} • ${_selectedRoute!.rainLabel}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: SupraTheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
                        Expanded(child: _buildBottomSheetContent(sortedTrips)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Floating top notification popup (does not block the bottom)
            _buildTopNotificationPopup(),
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

  Widget _buildBottomSheetContent(List<SavedTrip> sortedTrips) {
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
                        fontWeight: isCurrent
                            ? FontWeight.w800
                            : FontWeight.w600,
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
                onPressed: _tempTappedPoint == null
                    ? null
                    : _confirmPickedLocation,
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
            Row(
              children: [
                const Icon(
                  Icons.auto_graph_rounded,
                  size: 16,
                  color: SupraTheme.brand,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Show ML predictions',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SupraTheme.onSurface,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: _showMl,
                  activeThumbColor: SupraTheme.brand,
                  onChanged: (value) =>
                      DisplayPreferences.instance.setShowMlPredictions(value),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: 140, child: _modeSelector()),
            ),
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
                      _isTrackingActive = false;
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

            // Live Tracking Banner when tracking is active
            if (_isTrackingActive)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.my_location,
                      size: 15,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Route preview (not live GPS): ${_destination.text}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF15803D),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // Dynamic Action Button: Confirm saves trip & starts tracking;
            // while tracking is active, it is replaced by "Cancel Tracking".
            SizedBox(
              width: double.infinity,
              height: 46,
              child: _isTrackingActive
                  ? ElevatedButton.icon(
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text(
                        'Close Preview',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(
                          0xFFDC2626,
                        ), // Destructive red
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      onPressed: _busy
                          ? null
                          : _promptCancelTrackingConfirmation,
                    )
                  : ElevatedButton.icon(
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text(
                        'Confirm',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SupraTheme.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      onPressed: _busy ? null : _confirmTripAndStartTracking,
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
                      onPressed: () =>
                          _startPickingMode(forStart: true, focusSearch: false),
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

          // Real saved places and configured modes; no hardcoded Home/Work.
          Row(
            children: [
              _buildQuickActionChip(
                icon: Icons.home,
                label: 'Home',
                onTap: () => _useSavedPlace('home'),
              ),
              const SizedBox(width: 8),
              _buildQuickActionChip(
                icon: Icons.work,
                label: 'Work',
                onTap: () => _useSavedPlace('work'),
              ),
              IconButton(
                tooltip: 'Saved places & routines',
                onPressed: _openCommutes,
                icon: const Icon(Icons.bookmarks_outlined, size: 18),
              ),
              Expanded(child: _modeSelector()),
            ],
          ),
          const SizedBox(height: 8),

          // Loading indicator for route calculations: Expanded to fill the sheet area smoothly
          if (_loadingRoutes)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: SupraTheme.brand,
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Calculating optimal eco-routes...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: SupraTheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Loading driving route and available origin conditions',
                      style: TextStyle(
                        fontSize: 11,
                        color: SupraTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
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
          // Trip History Section with Sort Option
          else ...[
            _buildTripHistoryHeader(sortedTrips.length),
            const SizedBox(height: 6),
            Expanded(child: _buildTripHistoryList(sortedTrips)),
          ],

          const SizedBox(height: 4),

          // Explicit "Show Route" Button: Erased while loading so it never appears in the middle
          if (!_loadingRoutes)
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

  Widget _buildTripHistoryHeader(int count) {
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Flexible(
          child: Text(
            'Trip History',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: SupraTheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: SupraTheme.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: SupraTheme.brand,
            ),
          ),
        ),
      ],
    );
    Widget sortSelector(bool compact) => Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSortSegment(
            title: 'Recent',
            icon: Icons.access_time_rounded,
            isSelected: _historySort == TripHistorySort.recent,
            compact: compact,
            onTap: () => setState(() => _historySort = TripHistorySort.recent),
          ),
          _buildSortSegment(
            title: 'Frequency',
            icon: Icons.local_fire_department_rounded,
            isSelected: _historySort == TripHistorySort.frequency,
            compact: compact,
            onTap: () =>
                setState(() => _historySort = TripHistorySort.frequency),
          ),
        ],
      ),
    );
    // A stacked header would consume height the short 16:9 panel does not have.
    // Narrow widths keep one row and drop the segment labels to icons so the
    // selector cannot overflow; tooltips retain the meaning.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 6),
            sortSelector(compact),
          ],
        );
      },
    );
  }

  Widget _buildSortSegment({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    final content = Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 3),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        boxShadow: isSelected
            ? const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isSelected ? SupraTheme.brand : SupraTheme.textSecondary,
          ),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? SupraTheme.brand : SupraTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
    if (!compact) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }
    return Tooltip(
      message: title,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );
  }

  Widget _buildTripHistoryList(List<SavedTrip> trips) {
    if (trips.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No saved trips yet.\nSave a route or search a destination to add one!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: SupraTheme.textSecondary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: trips.length,
      separatorBuilder: (context, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = trips[i];
        final isHighFreq = item.frequency >= 4;
        return Material(
          color: Colors.transparent,
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 2,
            ),
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: _historySort == TripHistorySort.frequency
                  ? (isHighFreq
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFFF1F5F9))
                  : const Color(0xFFF1F5F9),
              child: Icon(
                _historySort == TripHistorySort.frequency
                    ? Icons.local_fire_department
                    : Icons.history,
                size: 14,
                color: _historySort == TripHistorySort.frequency
                    ? (isHighFreq ? const Color(0xFFEA580C) : SupraTheme.brand)
                    : SupraTheme.brand,
              ),
            ),
            title: Text(
              item.destination,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: SupraTheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'From: ${item.start} • ${item.timeAgo}',
              style: const TextStyle(
                fontSize: 10.5,
                color: SupraTheme.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isHighFreq
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${item.frequency}x',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isHighFreq
                          ? const Color(0xFFB45309)
                          : SupraTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: SupraTheme.textSecondary,
                  ),
                  tooltip: 'Delete or reduce frequency',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  onPressed: () => _handleDeleteTrip(item),
                ),
              ],
            ),
            onTap: () => _selectTripHistoryItem(item),
          ),
        );
      },
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
        vehicleSub = 'Driving estimate, not live-traffic ETA';
        break;
      case TransportMode.motorcycle:
        icon = Icons.two_wheeler;
        iconColor = const Color(0xFFF59E0B);
        modeLabel = 'Motorcycle (Two-Wheeler)';
        vehicleSub = 'Mode-specific routing required';
        break;
      case TransportMode.publicTransit:
        icon = Icons.directions_bus;
        iconColor = const Color(0xFF0F766E);
        modeLabel = opt.title;
        vehicleSub = 'Transit';
        break;
      case TransportMode.walk:
        icon = Icons.directions_walk;
        iconColor = const Color(0xFF7C3AED);
        modeLabel = 'Walking';
        vehicleSub = 'Pedestrian routing • Outdoor exposure';
        break;
    }

    String trafficDesc;
    if (opt.trafficDensity == null) {
      trafficDesc = 'Route traffic unavailable';
    } else if (opt.trafficDensity! < 0.35) {
      trafficDesc = 'Smooth traffic flow';
    } else if (opt.trafficDensity! < 0.65) {
      trafficDesc = 'Moderate congestion';
    } else {
      trafficDesc = 'Heavy traffic delay';
    }

    return InkWell(
      onTap: () {
        setState(() => _selectedRoute = opt);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (opt.waypoints.isNotEmpty) {
            _mapKey.currentState?.fitToRoute(opt.waypoints);
          }
        });
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
                    color: (opt.rainfallMm ?? -1) > 0
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
                        color: (opt.rainfallMm ?? -1) > 0
                            ? const Color(0xFF2563EB)
                            : SupraTheme.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        opt.rainLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: (opt.rainfallMm ?? -1) > 0
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
                    color: opt.pm25UgM3 == null
                        ? const Color(0xFFF1F5F9)
                        : opt.pm25UgM3! >= 35
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
                        color: opt.pm25UgM3 == null
                            ? Colors.grey
                            : opt.pm25UgM3! >= 35
                            ? const Color(0xFFD97706)
                            : const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        opt.pm25Label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: opt.pm25UgM3 == null
                              ? Colors.grey
                              : opt.pm25UgM3! >= 35
                              ? const Color(0xFF92400E)
                              : const Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showMl)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_graph_rounded,
                          size: 11,
                          color: Color(0xFF6D28D9),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          opt.predictedAqi == null
                              ? 'ML AQI unavailable'
                              : 'ML AQI ${opt.predictedAqi!.round()}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6D28D9),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                opt.provenanceLabel,
                style: const TextStyle(
                  fontSize: 10,
                  color: SupraTheme.textSecondary,
                ),
              ),
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
