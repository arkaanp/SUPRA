import 'package:flutter/material.dart';

import '../models/commute.dart';
import '../models/location.dart';
import '../services/supra_api_service.dart';
import '../widgets/interactive_location_map.dart';

class CommutesScreen extends StatefulWidget {
  const CommutesScreen({super.key, this.onPlan});
  final void Function(SavedPlace origin, SavedPlace destination, String mode)?
  onPlan;
  @override
  State<CommutesScreen> createState() => _CommutesScreenState();
}

class _CommutesScreenState extends State<CommutesScreen> {
  List<SavedPlace> _places = [];
  List<RoutineTrip> _routines = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final places = await SupraService.instance.getSavedPlaces();
      final routines = await SupraService.instance.getRoutines();
      if (mounted) {
        setState(() {
          _places = places;
          _routines = routines;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editPlace([SavedPlace? place]) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => _PlaceEditor(place: place)));
    if (mounted) await _load();
  }

  Future<void> _editRoutine([RoutineTrip? routine]) async {
    if (_places.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save at least two places first.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _RoutineEditor(places: _places, routine: routine),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _delete(String id, bool place) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(place ? 'Delete place?' : 'Delete routine?'),
        content: Text(
          place
              ? 'Routines using this place will also be deleted. Trip history is preserved.'
              : 'This removes its future alert subscription, not trip history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (place) {
        await SupraService.instance.deletePlace(id);
      } else {
        await SupraService.instance.deleteRoutine(id);
      }
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Saved places & routines'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Places'),
            Tab(text: 'Routines'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FilledButton.icon(
                      onPressed: () => _editPlace(),
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Save a place'),
                    ),
                    if (_places.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Save Home, Work, School or a custom location.',
                        ),
                      ),
                    for (final p in _places)
                      Card(
                        child: ListTile(
                          title: Text(p.label),
                          subtitle: Text(
                            '${p.kind} · ${p.point.latitude.toStringAsFixed(4)}, ${p.point.longitude.toStringAsFixed(4)}',
                          ),
                          onTap: () => _editPlace(p),
                          trailing: IconButton(
                            tooltip: 'Delete place',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(p.id, true),
                          ),
                        ),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FilledButton.icon(
                      onPressed: () => _editRoutine(),
                      icon: const Icon(Icons.add_alarm),
                      label: const Text('Create routine'),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Routine schedules use Asia/Jakarta (WIB). Alerts respect both routine and profile preferences.',
                      ),
                    ),
                    for (final r in _routines)
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              title: Text(r.label),
                              subtitle: Text(
                                '${r.departureLabel} WIB · ${r.mode}\n${r.weekdays.map((d) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d]).join(', ')} · ${r.enabled ? 'Enabled' : 'Paused'}',
                              ),
                              onTap: () => _editRoutine(r),
                              trailing: IconButton(
                                tooltip: 'Delete routine',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(r.id, false),
                              ),
                            ),
                            if (widget.onPlan != null)
                              TextButton.icon(
                                icon: const Icon(Icons.route),
                                label: const Text('Plan now'),
                                onPressed: () {
                                  final origin = _places.firstWhere(
                                        (p) => p.id == r.originId,
                                      ),
                                      dest = _places.firstWhere(
                                        (p) => p.id == r.destinationId,
                                      );
                                  Navigator.pop(context);
                                  widget.onPlan!(origin, dest, r.mode);
                                },
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
    ),
  );
}

class _PlaceEditor extends StatefulWidget {
  const _PlaceEditor({this.place});
  final SavedPlace? place;
  @override
  State<_PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<_PlaceEditor> {
  late final _label = TextEditingController(text: widget.place?.label ?? '');
  late String _kind = widget.place?.kind ?? 'custom';
  late LatLng? _point = widget.place?.point;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_point == null || _label.text.trim().isEmpty) {
      setState(() => _error = 'Choose a location and enter a label.');
      return;
    }
    setState(() => _busy = true);
    try {
      await SupraService.instance.savePlace(
        placeId: widget.place?.id,
        label: _label.text,
        kind: _kind,
        point: _point!,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.place == null ? 'Save place' : 'Edit place'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _label,
          decoration: const InputDecoration(labelText: 'Label'),
          maxLength: 120,
        ),
        DropdownButtonFormField<String>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Place type'),
          items: [
            for (final k in ['home', 'work', 'school', 'custom'])
              DropdownMenuItem(value: k, child: Text(k)),
          ],
          onChanged: _busy ? null : (v) => setState(() => _kind = v!),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.map),
          label: Text(
            _point == null ? 'Choose location on map' : 'Change saved location',
          ),
          onPressed: _busy
              ? null
              : () async {
                  final picked = await showLocationPickerSheet(
                    context: context,
                    initialLocation: _point,
                  );
                  if (picked != null && mounted) {
                    setState(() => _point = picked);
                  }
                },
        ),
        if (_point != null)
          Text(
            '${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)}',
          ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save place'),
        ),
      ],
    ),
  );
}

class _RoutineEditor extends StatefulWidget {
  const _RoutineEditor({required this.places, this.routine});
  final List<SavedPlace> places;
  final RoutineTrip? routine;
  @override
  State<_RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<_RoutineEditor> {
  late final _label = TextEditingController(text: widget.routine?.label ?? '');
  late String _origin = widget.routine?.originId ?? widget.places.first.id,
      _dest = widget.routine?.destinationId ?? widget.places.last.id;
  late String _mode = widget.routine?.mode ?? 'car';
  late final Set<int> _days =
      (widget.routine?.weekdays ?? [0, 1, 2, 3, 4]).toSet();
  late int _minute = widget.routine?.departureMinute ?? 420,
      _lead = widget.routine?.leadMinutes ?? 30;
  late bool _enabled = widget.routine?.enabled ?? true,
      _alerts = widget.routine?.alertsEnabled ?? true,
      _news = widget.routine?.newsEnabled ?? false;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_label.text.trim().isEmpty || _origin == _dest || _days.isEmpty) {
      setState(
        () =>
            _error = 'Enter a name, distinct places and at least one weekday.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await SupraService.instance.saveRoutine({
        'label': _label.text.trim(),
        'origin_id': _origin,
        'destination_id': _dest,
        'mode': _mode,
        'weekdays': (_days.toList()..sort()),
        'departure_minute': _minute,
        'timezone': 'Asia/Jakarta',
        'lead_minutes': _lead,
        'enabled': _enabled,
        'alerts_enabled': _alerts,
        'news_enabled': _news,
      }, routineId: widget.routine?.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.routine == null ? 'Create routine' : 'Edit routine'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _label,
          decoration: const InputDecoration(labelText: 'Routine name'),
          maxLength: 120,
        ),
        for (final origin in [true, false])
          DropdownButtonFormField<String>(
            initialValue: origin ? _origin : _dest,
            decoration: InputDecoration(labelText: origin ? 'From' : 'To'),
            items: [
              for (final p in widget.places)
                DropdownMenuItem(value: p.id, child: Text(p.label)),
            ],
            onChanged: (v) => setState(() {
              if (origin) {
                _origin = v!;
              } else {
                _dest = v!;
              }
            }),
          ),
        DropdownButtonFormField<String>(
          initialValue: _mode,
          decoration: const InputDecoration(labelText: 'Travel mode'),
          items: [
            for (final m in ['car', 'motorcycle', 'walk', 'public_transit'])
              DropdownMenuItem(value: m, child: Text(m)),
          ],
          onChanged: (v) => setState(() => _mode = v!),
        ),
        Wrap(
          spacing: 4,
          children: [
            for (var d = 0; d < 7; d++)
              FilterChip(
                label: Text(
                  ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d],
                ),
                selected: _days.contains(d),
                onSelected: (on) => setState(() {
                  if (on) {
                    _days.add(d);
                  } else {
                    _days.remove(d);
                  }
                }),
              ),
          ],
        ),
        ListTile(
          title: const Text('Departure time (WIB)'),
          subtitle: Text(
            '${(_minute ~/ 60).toString().padLeft(2, '0')}:${(_minute % 60).toString().padLeft(2, '0')}',
          ),
          onTap: () async {
            final t = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: _minute ~/ 60, minute: _minute % 60),
            );
            if (t != null && mounted) {
              setState(() => _minute = t.hour * 60 + t.minute);
            }
          },
        ),
        DropdownButtonFormField<int>(
          initialValue: _lead,
          decoration: const InputDecoration(
            labelText: 'Check before departure (minutes)',
          ),
          items: [
            for (final n in {15, 30, 60, 120, 180, _lead}.toList()..sort())
              DropdownMenuItem(value: n, child: Text('$n')),
          ],
          onChanged: (n) => setState(() => _lead = n!),
        ),
        SwitchListTile(
          title: const Text('Routine enabled'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        SwitchListTile(
          title: const Text('Environmental and traffic alerts'),
          value: _alerts,
          onChanged: (v) => setState(() => _alerts = v),
        ),
        SwitchListTile(
          title: const Text('Relevant verified news'),
          subtitle: const Text('Requires a configured trusted incident feed.'),
          value: _news,
          onChanged: (v) => setState(() => _news = v),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save routine'),
        ),
      ],
    ),
  );
}
