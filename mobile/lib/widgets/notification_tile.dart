import 'package:flutter/material.dart';

import 'source_info_button.dart';

import '../models/notification.dart';
import '../theme/app_theme.dart';

/// One proactive notification row (Agent 2 output).
class NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onReadNews;
  final VoidCallback? onToggleRead;
  final ValueChanged<bool>? onSelectionChanged;
  final bool selected, actionsEnabled;

  const NotificationTile({
    super.key,
    required this.notification,
    this.onTap,
    this.onReadNews,
    this.onToggleRead,
    this.onSelectionChanged,
    this.selected = false,
    this.actionsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final severity = notification.severity;
    final isVerifiedNews =
        notification.sourceUrl != null &&
        notification.sourceUrl!.trim().isNotEmpty;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: SizedBox(
          width: onSelectionChanged == null ? 10 : 58,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onSelectionChanged != null)
                Semantics(
                  label: 'Pilih peringatan: ${notification.displayTitle}',
                  child: Checkbox(
                    value: selected,
                    onChanged: actionsEnabled
                        ? (v) => onSelectionChanged!(v ?? false)
                        : null,
                  ),
                ),
              Tooltip(
                message: notification.isRead ? 'Sudah dibaca' : 'Belum dibaca',
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: notification.isRead
                        ? const Color(0xFFCBD5E1)
                        : SupraTheme.brand,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            if (isVerifiedNews) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.newspaper_outlined,
                      size: 11,
                      color: Color(0xFF15803D),
                    ),
                    SizedBox(width: 3),
                    Text(
                      'BERITA',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Expanded(
              child: Text(
                notification.displayTitle,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: notification.isRead
                      ? const Color(0xFF475569)
                      : const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              notification.displayBody,
              style: TextStyle(
                fontSize: 12.5,
                color: notification.isRead
                    ? const Color(0xFF64748B)
                    : const Color(0xFF334155),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            if (notification.expiresAt?.isBefore(DateTime.now()) == true)
              const Text(
                'Berita kedaluwarsa — disimpan sebagai riwayat',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            if (onToggleRead != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: actionsEnabled ? onToggleRead : null,
                  icon: Icon(
                    notification.isRead
                        ? Icons.mark_email_unread_outlined
                        : Icons.mark_email_read_outlined,
                    size: 16,
                  ),
                  label: Text(
                    notification.isRead
                        ? 'Tandai belum dibaca'
                        : 'Tandai sudah dibaca',
                  ),
                ),
              ),
            if (isVerifiedNews)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (onReadNews != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.article_outlined, size: 14),
                      label: const Text(
                        'Baca Berita',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: onReadNews,
                    ),
                  SourceInfoButton(
                    title: 'Sumber berita',
                    details: notification.sourceUrl!,
                    url: notification.sourceUrl,
                  ),
                ],
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
        onLongPress: actionsEnabled && onSelectionChanged != null
            ? () => onSelectionChanged!(!selected)
            : null,
      ),
    );
  }
}
