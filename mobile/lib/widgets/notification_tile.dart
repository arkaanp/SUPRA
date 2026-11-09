import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/notification.dart';
import '../theme/app_theme.dart';

/// One proactive notification row (Agent 2 output).
class NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;

  const NotificationTile({super.key, required this.notification, this.onTap});

  @override
  Widget build(BuildContext context) {
    final severity = notification.severity;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: notification.isRead
                ? const Color(0xFFCBD5E1)
                : SupraTheme.brand,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: notification.isRead
                ? const Color(0xFF475569)
                : const Color(0xFF0F172A),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              notification.messageBody,
              style: TextStyle(
                fontSize: 13,
                color: notification.isRead
                    ? const Color(0xFF64748B)
                    : const Color(0xFF334155),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            if (notification.expiresAt?.isBefore(DateTime.now()) == true)
              const Text(
                'Expired report — kept for history',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            if (notification.sourceUrl != null)
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Read source report'),
                onPressed: () async {
                  final uri = Uri.tryParse(notification.sourceUrl!);
                  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
                    return;
                  }
                  try {
                    if (!await launchUrl(uri)) {
                      throw StateError('Source could not open');
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(notification.sourceUrl!)),
                      );
                    }
                  }
                },
              ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: severity.color().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${severity.label()} severity',
                    style: TextStyle(
                      color: severity.color(),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  notification.timeLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: notification.isRead
            ? const Icon(Icons.check_circle, color: Color(0xFF94A3B8), size: 18)
            : const Icon(Icons.circle, color: Color(0xFF94A3B8), size: 8),
        onTap: onTap,
      ),
    );
  }
}
