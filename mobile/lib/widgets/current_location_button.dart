import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/location.dart';

class CurrentLocationButton extends StatefulWidget {
  const CurrentLocationButton({super.key, required this.onSelected});

  final ValueChanged<LatLng> onSelected;

  @override
  State<CurrentLocationButton> createState() => _CurrentLocationButtonState();
}

class _CurrentLocationButtonState extends State<CurrentLocationButton> {
  bool _pending = false;

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _locate() async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showError('Turn on location services, then try again.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (!mounted) return;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (permission == LocationPermission.deniedForever) {
        _showError(
          'Allow SUPRA to access your location in your device settings.',
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        _showError(
          'Location permission was denied. You can still choose on the map.',
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      final point = LatLng(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!point.isInGreaterJakarta) {
        _showError(
          'Your location is outside SUPRA’s Greater Jakarta service area.',
        );
        return;
      }
      widget.onSelected(point);
    } on TimeoutException {
      _showError(
        'Could not get a location in time. Try again or choose on the map.',
      );
    } on LocationServiceDisabledException {
      _showError('Turn on location services, then try again.');
    } on PermissionDeniedException {
      _showError('Allow location access in settings or choose on the map.');
    } on PlatformException {
      _showError('Device location is unavailable. Choose on the map.');
    } on UnsupportedError {
      _showError('Device location is unavailable. Choose on the map.');
    } on MissingPluginException {
      _showError('Device location is unavailable. Choose on the map.');
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _pending ? null : _locate,
    icon: _pending
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.my_location),
    label: Text(_pending ? 'Getting location…' : 'Use current location'),
  );
}
