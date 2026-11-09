import 'package:flutter/material.dart';

import 'package:supra_mobile_ui/models/notification.dart';
import 'package:supra_mobile_ui/services/supra_api_service.dart';
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
    try {
      final items = await SupraService.instance.getNotifications();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead([String? id]) async {
    try {
      if (id == null) {
        await SupraService.instance.markAllRead();
      } else {
        await SupraService.instance.markNotificationRead(id);
      }
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            tooltip: 'Check due trips now',
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
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$e')));
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
                  : _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(
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
                      itemCount: _items.length,
                      itemBuilder: (context, i) => NotificationTile(
                        notification: _items[i],
                        onTap: () => _markRead(_items[i].id),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
