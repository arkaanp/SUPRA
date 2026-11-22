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
        _showError('Aktifkan layanan lokasi, lalu coba lagi.');
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
          'Izinkan SUPRA mengakses lokasi melalui pengaturan perangkat.',
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        _showError(
          'Izin lokasi ditolak. Anda tetap dapat memilih lokasi di peta.',
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
          'Lokasi Anda berada di luar wilayah layanan SUPRA di Jabodetabek.',
        );
        return;
      }
      widget.onSelected(point);
    } on TimeoutException {
      _showError('Lokasi belum ditemukan. Coba lagi atau pilih di peta.');
    } on LocationServiceDisabledException {
      _showError('Aktifkan layanan lokasi, lalu coba lagi.');
    } on PermissionDeniedException {
      _showError('Izinkan akses lokasi di pengaturan atau pilih di peta.');
    } on PlatformException {
      _showError('Lokasi perangkat tidak tersedia. Pilih di peta.');
    } on UnsupportedError {
      _showError('Lokasi perangkat tidak tersedia. Pilih di peta.');
    } on MissingPluginException {
      _showError('Lokasi perangkat tidak tersedia. Pilih di peta.');
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
    label: Text(_pending ? 'Mencari lokasi…' : 'Gunakan lokasi saat ini'),
  );
}
