import 'package:flutter/material.dart';

import '../services/supra_api_service.dart';

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
        'Trips are saved to your account. Route generation, forecasts '
        'and map overlays are not available yet.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _start,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Start location'),
      ),
      TextField(
        controller: _destination,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Destination'),
      ),
      TextButton(
        onPressed: _busy ? null : _pickDeparture,
        child: Text(
          _departure == null
              ? 'Departure: now (change)'
              : 'Departure: $_departure',
        ),
      ),
      ElevatedButton(
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
              }),
        child: Text(_busy ? 'Saving…' : 'Save trip'),
      ),
      const Divider(),
      for (final trip in SupraService.instance.trips)
        ListTile(
          title: Text(trip.name),
          subtitle: Text('${trip.plannedDeparture}'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete trip',
            onPressed: _busy
                ? null
                : () =>
                      _perform(() => SupraService.instance.deleteTrip(trip.id)),
          ),
        ),
    ],
  );
}
