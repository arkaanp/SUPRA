import '../utils/display_text.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/source_info_button.dart';

import 'package:flutter/foundation.dart';

import 'package:supra_mobile_ui/models/notification.dart';

import '../models/notification_preference.dart';
import '../widgets/news_severity_selector.dart';
import 'settings_screen.dart';

import 'package:supra_mobile_ui/services/supra_api_service.dart';
import 'package:supra_mobile_ui/widgets/notification_tile.dart';

/// Notifications inbox: Agent 2 proactive alerts with severity and read state.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.loadNotifications,
    this.saveNewsSeverity,
    this.initialPreferences,
    this.preferenceChanges,
    this.deleteReadAlerts,
    this.setReadState,
    this.markSelectedUnread,
    this.markAllReadAlerts,
  });
  final Future<List<AppNotification>> Function(String)? loadNotifications;
  final Future<NotificationPreference> Function(String)? saveNewsSeverity;
  final NotificationPreference? initialPreferences;
  final ValueListenable<NotificationPreference>? preferenceChanges;
  final Future<int> Function()? deleteReadAlerts;
  final Future<void> Function(String, bool)? setReadState;
  final Future<int> Function(List<String>)? markSelectedUnread;
  final Future<int> Function()? markAllReadAlerts;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = [];
  bool _loading = true;
  String? _error;
  bool _checking = false;
  String? _checkStatus;
  String _newsMinimum = 'low';
  bool _savingFilter = false;
  bool _mutatingAlerts = false;
  final Set<String> _selectedIds = {};
  void _pruneSelection() {
    final visible = _visibleItems.map((n) => n.id).toSet();
    _selectedIds.retainAll(visible);
  }

  late NotificationPreference _preferences;
  late NotificationPreference _observedPreferences;
  String? _observedUser;
  Listenable get _preferenceSource =>
      widget.preferenceChanges ?? SupraService.instance;
  NotificationPreference get _storedPreferences =>
      widget.preferenceChanges?.value ?? SupraService.instance.preferences;
  List<AppNotification> get _visibleItems =>
      _items.where(_preferences.allowsNotification).toList();
  int _generation = 0;
  String _selectedFilter = 'all'; // 'all' | 'verified_news' | 'hazard'

  @override
  void initState() {
    super.initState();
    _observedPreferences = _storedPreferences;
    _observedUser = SupraService.instance.currentUser?.id;
    _preferences = widget.initialPreferences ?? _observedPreferences;
    _newsMinimum = _preferences.newsMinSeverity;
    _preferenceSource.addListener(_onPreferencesChanged);
    _refresh();
  }

  void _onPreferencesChanged() {
    if (!mounted) return;
    final next = _storedPreferences;
    final user = SupraService.instance.currentUser?.id;
    final accountChanged = user != _observedUser;
    if (!accountChanged &&
        mapEquals(next.toJson(), _observedPreferences.toJson())) {
      return;
    }
    setState(() {
      _observedPreferences = next;
      _observedUser = user;
      _preferences = next;
      _newsMinimum = next.newsMinSeverity;
      _generation++;
      if (accountChanged) {
        _items = [];
        _selectedIds.clear();
      }
      _pruneSelection();
    });
    if (!_savingFilter &&
        (!accountChanged || user != null || widget.preferenceChanges != null)) {
      unawaited(_refresh(showLoading: false));
    }
  }

  @override
  void didUpdateWidget(covariant NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferenceChanges != widget.preferenceChanges) {
      (oldWidget.preferenceChanges ?? SupraService.instance).removeListener(
        _onPreferencesChanged,
      );
      _preferenceSource.addListener(_onPreferencesChanged);
      _onPreferencesChanged();
    }
  }

  @override
  void dispose() {
    _preferenceSource.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  Future<void> _refresh({bool showLoading = true}) async {
    final generation = ++_generation;
    setState(() {
      if (showLoading) _loading = true;
      _error = null;
    });
    try {
      final items =
          await (widget.loadNotifications?.call(_newsMinimum) ??
              SupraService.instance.getNotifications(
                newsMinSeverity: _newsMinimum,
              ));
      if (mounted && generation == _generation) {
        setState(() {
          _items = List<AppNotification>.of(items);
          _pruneSelection();
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = displayError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveSeverity(String severity) async {
    final previous = _preferences;
    setState(() {
      _newsMinimum = severity;
      _preferences = _preferences.copyWith(newsMinSeverity: severity);
      _savingFilter = true;
    });
    try {
      final prefs =
          await (widget.saveNewsSeverity ??
              SupraService.instance.updateNewsSeverity)(severity);
      if (mounted) {
        setState(() {
          _preferences = prefs;
          _newsMinimum = prefs.newsMinSeverity;
        });
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _preferences = previous;
          _newsMinimum = previous.newsMinSeverity;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Filter berita gagal disimpan: ${displayError(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingFilter = false);
    }
  }

  Future<void> _setReadState(String id, bool read) async {
    if (_mutatingAlerts) return;
    setState(() => _mutatingAlerts = true);
    try {
      if (widget.setReadState != null) {
        await widget.setReadState!(id, read);
      } else if (read) {
        await SupraService.instance.markNotificationRead(id);
      } else {
        await SupraService.instance.markNotificationUnread(id);
      }
      if (!mounted) return;
      setState(
        () => _items = _items
            .map((n) => n.id == id ? n.copyWith(isRead: read) : n)
            .toList(),
      );
      await _refresh(showLoading: false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengubah status peringatan ${read ? "menjadi sudah dibaca" : "menjadi belum dibaca"}: ${displayError(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _mutatingAlerts = false);
    }
  }

  Future<void> _markRead([String? id]) async {
    if (id != null) return _setReadState(id, true);
    if (_mutatingAlerts) return;
    setState(() => _mutatingAlerts = true);
    try {
      await (widget.markAllReadAlerts ?? SupraService.instance.markAllRead)();
      if (!mounted) return;
      setState(
        () => _items = _items
            .map(
              (n) => _preferences.allowsNotification(n)
                  ? n.copyWith(isRead: true)
                  : n,
            )
            .toList(),
      );
      await _refresh(showLoading: false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal menandai semua sudah dibaca: ${displayError(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _mutatingAlerts = false);
    }
  }

  Future<void> _markSelectedUnread() async {
    final ids = _visibleItems
        .where((n) => _selectedIds.contains(n.id))
        .map((n) => n.id)
        .toList();
    if (_mutatingAlerts || ids.isEmpty) return;
    setState(() => _mutatingAlerts = true);
    try {
      await (widget.markSelectedUnread ??
          SupraService.instance.markNotificationsUnread)(ids);
      if (!mounted) return;
      final selected = ids.toSet();
      setState(() {
        _items = _items
            .map((n) => selected.contains(n.id) ? n.copyWith(isRead: false) : n)
            .toList();
        _selectedIds.clear();
      });
      await _refresh(showLoading: false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal menandai pilihan belum dibaca: ${displayError(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _mutatingAlerts = false);
    }
  }

  Future<void> _deleteRead() async {
    if (_mutatingAlerts) return;
    setState(() => _mutatingAlerts = true);
    try {
      final count =
          await (widget.deleteReadAlerts ??
              SupraService.instance.deleteReadNotifications)();
      if (!mounted) return;
      setState(() {
        _items = _items.where((item) => !item.isRead).toList();
        _pruneSelection();
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              count == 0
                  ? 'Tidak ada peringatan yang sudah dibaca untuk dihapus.'
                  : '$count peringatan yang sudah dibaca dihapus.',
            ),
          ),
        );
      await _refresh(showLoading: false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Peringatan yang sudah dibaca gagal dihapus: ${displayError(error)}',
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _mutatingAlerts = false);
    }
  }

  void _showVerifiedNewsReader(AppNotification item) {
    if (!item.isRead) unawaited(_markRead(item.id));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (readerContext) => Scaffold(
          appBar: AppBar(title: const Text('Berita')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.newspaper_outlined,
                          size: 13,
                          color: Color(0xFF15803D),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'LAPORAN BERITA',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.timeLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.displayTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  item.displayBody,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF334155),
                    height: 1.45,
                  ),
                ),
              ),
              if (item.sourceUrl != null) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SourceInfoButton(
                      title: 'Sumber berita',
                      details: item.sourceUrl!,
                      url: item.sourceUrl,
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(readerContext),
                      child: const Text('Tutup'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  int get unreadCount => _visibleItems.where((n) => !n.isRead).length;

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await SupraService.instance.evaluateAlerts();
      if (mounted) {
        setState(
          () => _checkStatus =
              'Pemeriksaan jadwal perjalanan diantrekan. Tarik untuk memperbarui hasil peringatan. '
              '${result['scheduler_enabled'] == true ? 'Pemeriksaan terjadwal aktif.' : 'Pemeriksaan terjadwal nonaktif di server.'} '
              '${result['news_configured'] == true ? '' : 'Sumber berita belum dikonfigurasi.'}',
        );
      }
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(displayError(e))));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems;
    final verifiedNewsCount = visibleItems
        .where((n) => n.sourceUrl != null && n.sourceUrl!.trim().isNotEmpty)
        .length;
    final filteredItems = (switch (_selectedFilter) {
      'verified_news' =>
        visibleItems
            .where((n) => n.sourceUrl != null && n.sourceUrl!.trim().isNotEmpty)
            .toList(),
      'hazard' =>
        visibleItems
            .where((n) => n.sourceUrl == null || n.sourceUrl!.trim().isEmpty)
            .toList(),
      _ => visibleItems,
    }).where((n) => n.meetsNewsMinimum(_newsMinimum)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peringatan dan berita'),
        actions: [
          IconButton(
            tooltip: 'Preferensi peringatan',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Preferensi peringatan')),
                    body: const SettingsScreen(),
                  ),
                ),
              );
              if (mounted) {
                _onPreferencesChanged();
                await _refresh(showLoading: false);
              }
            },
          ),
          IconButton(
            tooltip: 'Periksa jadwal perjalanan dan berita',
            onPressed: _checking ? null : _checkNow,
            icon: const Icon(Icons.radar),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: const ValueKey('alerts-page-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverList.list(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _mutatingAlerts || unreadCount == 0
                              ? null
                              : () => unawaited(_markRead()),
                          icon: const Icon(Icons.done_all, size: 18),
                          label: const Text('Tandai semua sudah dibaca'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _mutatingAlerts
                              ? null
                              : () => unawaited(_deleteRead()),
                          icon: const Icon(
                            Icons.delete_sweep_outlined,
                            size: 18,
                          ),
                          label: const Text('Hapus yang sudah dibaca'),
                        ),
                        if (_selectedIds.isNotEmpty) ...[
                          FilledButton.tonalIcon(
                            onPressed:
                                _mutatingAlerts ||
                                    !visibleItems.any(
                                      (n) =>
                                          _selectedIds.contains(n.id) &&
                                          n.isRead,
                                    )
                                ? null
                                : () => unawaited(_markSelectedUnread()),
                            icon: const Icon(
                              Icons.mark_email_unread_outlined,
                              size: 18,
                            ),
                            label: const Text('Tandai pilihan belum dibaca'),
                          ),
                          TextButton(
                            onPressed: _mutatingAlerts
                                ? null
                                : () => setState(() => _selectedIds.clear()),
                            child: Text(
                              'Batal pilih (${_selectedIds.length} dipilih)',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          selected: _selectedFilter == 'all',
                          label: Text(
                            'Semua (${visibleItems.length})',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _selectedFilter = 'all'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          selected: _selectedFilter == 'verified_news',
                          avatar: const Icon(
                            Icons.newspaper_outlined,
                            size: 14,
                            color: Color(0xFF15803D),
                          ),
                          label: Text(
                            'Berita ($verifiedNewsCount)',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _selectedFilter = 'verified_news'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          selected: _selectedFilter == 'hazard',
                          label: const Text(
                            'Peringatan Cuaca & AQI',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _selectedFilter = 'hazard'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_checkStatus != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _checkStatus!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: NewsSeveritySelector(
                    value: _newsMinimum,
                    onChanged: _savingFilter ? null : _saveSeverity,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'Saring berita dan simpan preferensi pengiriman. Peringatan cuaca dan AQI mengikuti pengaturannya masing-masing.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                for (final trip in SupraService.instance.activeTrips.take(3))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.route),
                    title: Text(trip.name),
                    subtitle: const Text(
                      'Peringatan perjalanan aktif (maksimal 4 jam)',
                    ),
                    trailing: TextButton(
                      child: const Text('Hentikan peringatan'),
                      onPressed: () async {
                        try {
                          await SupraService.instance.finishTrip(trip.id);
                          if (mounted) setState(() {});
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(displayError(e))),
                            );
                          }
                        }
                      },
                    ),
                  ),
              ],
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              SliverList.list(
                children: [
                  ListTile(title: Text(_error!)),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Coba lagi'),
                  ),
                ],
              )
            else if (filteredItems.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 64,
                        color: Color(0xFFCBD5E1),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Belum ada peringatan',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Simpan rutinitas atau konfirmasi perjalanan. Gunakan tombol radar untuk memeriksa jadwal perjalanan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 16),
                sliver: SliverList.builder(
                  itemCount: filteredItems.length,
                  itemBuilder: (context, i) {
                    final item = filteredItems[i];
                    final isNews =
                        item.sourceUrl != null &&
                        item.sourceUrl!.trim().isNotEmpty;
                    return NotificationTile(
                      notification: item,
                      selected: _selectedIds.contains(item.id),
                      actionsEnabled: !_mutatingAlerts,
                      onSelectionChanged: (selected) => setState(() {
                        if (selected) {
                          _selectedIds.add(item.id);
                        } else {
                          _selectedIds.remove(item.id);
                        }
                      }),
                      onToggleRead: () =>
                          unawaited(_setReadState(item.id, !item.isRead)),
                      onTap: isNews
                          ? () => _showVerifiedNewsReader(item)
                          : () => _markRead(item.id),
                      onReadNews: isNews
                          ? () => _showVerifiedNewsReader(item)
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
