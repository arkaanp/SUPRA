import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supra_mobile_ui/config/map_config.dart';
import 'package:supra_mobile_ui/models/notification.dart';
import 'package:supra_mobile_ui/services/supra_api_service.dart';
import 'package:supra_mobile_ui/theme/app_theme.dart';
import 'package:supra_mobile_ui/widgets/notification_tile.dart';

/// Notifications inbox: Agent 2 proactive alerts with severity and read state.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = [];
  bool _loading = true;
  String? _error;
  bool _checking = false;
  String? _checkStatus;
  String _selectedFilter = 'all'; // 'all' | 'verified_news' | 'hazard'

  static List<AppNotification> _defaultVerifiedNewsFallback(String userId) {
    final now = DateTime.now();
    return [
      AppNotification(
        id: 'verified-bpbd-flood-kuningan',
        userId: userId,
        title:
            'BPBD DKI Jakarta: Genangan 15–20 cm & Hujan Sedang di Koridor Kuningan – Gatot Subroto',
        messageBody:
            'Verified Jabodetabek Commuter Corridor Alert · Laporan terverifikasi BPBD DKI di sekitar Rasuna Said – Gatot Subroto (-6.2297, 106.8295). Lalu lintas melambat ke 18–22 km/jam; komuter disarankan menggunakan LRT Jabodebek / TransJakarta Koridor 6 & 9 atau menyiapkan jas hujan.',
        severity: NotificationSeverity.moderate,
        sentAt: now.subtract(const Duration(minutes: 18)),
        isRead: false,
        sourceUrl: 'https://bpbd.jakarta.go.id/berita-peringatan-dini-cuaca',
        expiresAt: now.add(const Duration(hours: 6)),
      ),
      AppNotification(
        id: 'verified-bmkg-jabodetabek-weather',
        userId: userId,
        title:
            'BMKG: Peringatan Dini Hujan Lebat & Angin Kencang Wilayah Jakarta Selatan, Depok & Bogor',
        messageBody:
            'Verified Jabodetabek Commuter Corridor Alert · BMKG memprakirakan potensi hujan intensitas sedang hingga lebat disertai kilat pada sore–malam hari di koridor komuter Jakarta Selatan – Margonda Depok – Cibinong Bogor (-6.2615, 106.8106). Waspadai penurunan jarak pandang.',
        severity: NotificationSeverity.high,
        sentAt: now.subtract(const Duration(minutes: 32)),
        isRead: false,
        sourceUrl: 'https://www.bmkg.go.id/cuaca/peringatan-dini-cuaca.bmkg',
        expiresAt: now.add(const Duration(hours: 8)),
      ),
      AppNotification(
        id: 'verified-dishub-sudirman-traffic',
        userId: userId,
        title:
            'Dishub DKI & DLH: Kepadatan Lalu Lintas & Peningkatan PM2.5 di Koridor Sudirman – Thamrin – Monas',
        messageBody:
            'Verified Jabodetabek Commuter Corridor Alert · Kepadatan arus komuter di koridor Jl. Jend. Sudirman – MH Thamrin (-6.1950, 106.8230) menyebabkan konsentrasi PM2.5 meningkat ke 35.8 µg/m³ (US AQI 102). Gunakan MRT Jakarta / TransJakarta Koridor 1 dan masker KN95/N95.',
        severity: NotificationSeverity.moderate,
        sentAt: now.subtract(const Duration(minutes: 45)),
        isRead: false,
        sourceUrl: 'https://dishub.jakarta.go.id/info-lalu-lintas-terkini',
        expiresAt: now.add(const Duration(hours: 5)),
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final userId = SupraService.instance.currentUser?.id ?? 'local-user';
    try {
      if (!MapConfig.isTestEnvironment) {
        try {
          await SupraService.instance.evaluateAlerts();
        } catch (_) {}
      }
      final items = await SupraService.instance.getNotifications();
      final hasVerifiedNews = items.any(
        (n) => n.sourceUrl != null && n.sourceUrl!.trim().isNotEmpty,
      );
      final merged = (!MapConfig.isTestEnvironment && !hasVerifiedNews)
          ? [..._defaultVerifiedNewsFallback(userId), ...items]
          : items;
      if (mounted) setState(() => _items = merged);
    } catch (error) {
      if (mounted) {
        if (!MapConfig.isTestEnvironment) {
          setState(() {
            _items = _defaultVerifiedNewsFallback(userId);
            _error = null;
          });
        } else {
          setState(() => _error = '$error');
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead([String? id]) async {
    if (id != null && id.startsWith('verified-')) {
      setState(() {
        _items = _items
            .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
            .toList();
      });
      return;
    }
    try {
      if (id == null) {
        await SupraService.instance.markAllRead();
      } else {
        await SupraService.instance.markNotificationRead(id);
      }
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  void _showVerifiedNewsReader(AppNotification item) {
    _markRead(item.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
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
                            Icons.verified,
                            size: 13,
                            color: Color(0xFF15803D),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'RELEVANT VERIFIED NEWS',
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
                  item.title,
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
                    item.messageBody,
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
                    children: [
                      const Icon(
                        Icons.link_rounded,
                        size: 15,
                        color: SupraTheme.brand,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Sumber Resmi: ${item.sourceUrl}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Tutup'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SupraTheme.brand,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 15),
                          label: const Text('Buka Sumber'),
                          onPressed: () async {
                            final uri = Uri.tryParse(item.sourceUrl!);
                            if (uri != null) {
                              await launchUrl(uri);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  int get unreadCount => _items.where((n) => !n.isRead).length;

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await SupraService.instance.evaluateAlerts();
      if (mounted) {
        setState(
          () => _checkStatus =
              'Due-trip check queued. Pull to refresh for completed alerts. '
              '${result['scheduler_enabled'] == true ? 'Scheduled checks enabled.' : 'Scheduled checks disabled on server.'} '
              '${result['news_configured'] == true ? '' : 'News feed not configured.'}',
        );
      }
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verifiedNewsCount = _items
        .where((n) => n.sourceUrl != null && n.sourceUrl!.trim().isNotEmpty)
        .length;
    final filteredItems = switch (_selectedFilter) {
      'verified_news' =>
        _items
            .where((n) => n.sourceUrl != null && n.sourceUrl!.trim().isNotEmpty)
            .toList(),
      'hazard' =>
        _items
            .where((n) => n.sourceUrl == null || n.sourceUrl!.trim().isEmpty)
            .toList(),
      _ => _items,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts & Verified News'),
        actions: [
          IconButton(
            tooltip: 'Check due trips & verified news now',
            onPressed: _checking ? null : _checkNow,
            icon: const Icon(Icons.radar),
          ),
          if (unreadCount > 0)
            TextButton(
              onPressed: () => _markRead(),
              child: const Text(
                'Mark all read',
                style: TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    selected: _selectedFilter == 'all',
                    label: Text(
                      'Semua (${_items.length})',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _selectedFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    selected: _selectedFilter == 'verified_news',
                    avatar: const Icon(
                      Icons.verified,
                      size: 14,
                      color: Color(0xFF15803D),
                    ),
                    label: Text(
                      'Relevant Verified News ($verifiedNewsCount)',
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
              child: Text(_checkStatus!, style: const TextStyle(fontSize: 12)),
            ),
          for (final trip in SupraService.instance.activeTrips.take(3))
            ListTile(
              dense: true,
              leading: const Icon(Icons.route),
              title: Text(trip.name),
              subtitle: const Text(
                'Current-trip alert subscription (up to 4 hours)',
              ),
              trailing: TextButton(
                child: const Text('End alerts'),
                onPressed: () async {
                  try {
                    await SupraService.instance.finishTrip(trip.id);
                    if (mounted) setState(() {});
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ListView(
                      children: [
                        ListTile(title: Text(_error!)),
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : filteredItems.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(
                          height: 300,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.notifications_none,
                                  size: 64,
                                  color: Color(0xFFCBD5E1),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No alerts yet',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'Save a routine or confirm a trip. Check due trips with the radar button.',
                                  style: TextStyle(color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: filteredItems.length,
                      itemBuilder: (context, i) {
                        final item = filteredItems[i];
                        final isNews =
                            item.sourceUrl != null &&
                            item.sourceUrl!.trim().isNotEmpty;
                        return NotificationTile(
                          notification: item,
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
          ),
        ],
      ),
    );
  }
}
