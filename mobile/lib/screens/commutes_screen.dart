import '../utils/display_text.dart';

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
      if (mounted) setState(() => _error = displayError(e));
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
        const SnackBar(
          content: Text('Simpan minimal dua tempat terlebih dahulu.'),
        ),
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
        title: Text(place ? 'Hapus tempat?' : 'Hapus rutinitas?'),
        content: Text(
          place
              ? 'Rutinitas yang menggunakan tempat ini juga akan dihapus. Riwayat perjalanan tetap tersimpan.'
              : 'Peringatan berikutnya untuk rutinitas ini akan dihentikan. Riwayat perjalanan tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
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
            .showSnackBar(SnackBar(content: Text(displayError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Tempat dan rutinitas tersimpan'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Tempat'),
            Tab(text: 'Rutinitas'),
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
                  TextButton(onPressed: _load, child: const Text('Coba lagi')),
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
                      label: const Text('Simpan tempat'),
                    ),
                    if (_places.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Simpan lokasi rumah, kantor, sekolah, atau tempat lainnya.',
                        ),
                      ),
                    for (final p in _places)
                      Card(
                        child: ListTile(
                          title: Text(p.label),
                          subtitle: Text(
                            '${placeKindLabel(p.kind)} · ${p.point.latitude.toStringAsFixed(4)}, ${p.point.longitude.toStringAsFixed(4)}',
                          ),
                          onTap: () => _editPlace(p),
                          trailing: IconButton(
                            tooltip: 'Hapus tempat',
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
                      label: const Text('Buat rutinitas'),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Jadwal rutinitas menggunakan WIB. Peringatan mengikuti preferensi rutinitas dan profil.',
                      ),
                    ),
                    for (final r in _routines)
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              title: Text(r.label),
                              subtitle: Text(
                                '${r.departureLabel} WIB · ${travelModeLabel(r.mode)}\n${r.weekdays.map((d) => ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'][d]).join(', ')} · ${r.enabled ? 'Aktif' : 'Dijeda'}',
                              ),
                              onTap: () => _editRoutine(r),
                              trailing: IconButton(
                                tooltip: 'Hapus rutinitas',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(r.id, false),
                              ),
                            ),
                            if (widget.onPlan != null)
                              TextButton.icon(
                                icon: const Icon(Icons.route),
                                label: const Text('Rencanakan sekarang'),
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
      setState(() => _error = 'Pilih lokasi dan masukkan nama tempat.');
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
      if (mounted) setState(() => _error = displayError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.place == null ? 'Simpan tempat' : 'Ubah tempat'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _label,
          decoration: const InputDecoration(labelText: 'Nama tempat'),
          maxLength: 120,
        ),
        DropdownButtonFormField<String>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Jenis tempat'),
          items: [
            for (final k in ['home', 'work', 'school', 'custom'])
              DropdownMenuItem(value: k, child: Text(placeKindLabel(k))),
          ],
          onChanged: _busy ? null : (v) => setState(() => _kind = v!),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.map),
          label: Text(
            _point == null ? 'Pilih lokasi di peta' : 'Ubah lokasi tersimpan',
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
          child: Text(_busy ? 'Menyimpan…' : 'Simpan tempat'),
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
  late final Set<int> _days = (widget.routine?.weekdays ?? [0, 1, 2, 3, 4])
      .toSet();
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
        () => _error =
            'Masukkan nama, dua tempat berbeda, dan minimal satu hari.',
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
      if (mounted) setState(() => _error = displayError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.routine == null ? 'Buat rutinitas' : 'Ubah rutinitas'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _label,
          decoration: const InputDecoration(labelText: 'Nama rutinitas'),
          maxLength: 120,
        ),
        for (final origin in [true, false])
          DropdownButtonFormField<String>(
            initialValue: origin ? _origin : _dest,
            decoration: InputDecoration(labelText: origin ? 'Dari' : 'Ke'),
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
          decoration: const InputDecoration(labelText: 'Moda transportasi'),
          items: [
            for (final m in ['car', 'motorcycle', 'walk', 'public_transit'])
              DropdownMenuItem(value: m, child: Text(travelModeLabel(m))),
          ],
          onChanged: (v) => setState(() => _mode = v!),
        ),
        Wrap(
          spacing: 4,
          children: [
            for (var d = 0; d < 7; d++)
              FilterChip(
                label: Text(
                  ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'][d],
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
          title: const Text('Waktu keberangkatan (WIB)'),
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
            labelText: 'Periksa sebelum berangkat (menit)',
          ),
          items: [
            for (final n in {15, 30, 60, 120, 180, _lead}.toList()..sort())
              DropdownMenuItem(value: n, child: Text('$n')),
          ],
          onChanged: (n) => setState(() => _lead = n!),
        ),
        SwitchListTile(
          title: const Text('Rutinitas aktif'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        SwitchListTile(
          title: const Text('Peringatan lingkungan dan lalu lintas'),
          value: _alerts,
          onChanged: (v) => setState(() => _alerts = v),
        ),
        SwitchListTile(
          title: const Text('Berita relevan'),
          subtitle: const Text(
            'Berita dari sumber tepercaya yang sesuai dengan perjalanan Anda.',
          ),
          value: _news,
          onChanged: (v) => setState(() => _news = v),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Menyimpan…' : 'Simpan rutinitas'),
        ),
      ],
    ),
  );
}
