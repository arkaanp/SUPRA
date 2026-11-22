import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Keeps provenance and optional publisher links beside the reading they describe.
class SourceInfoButton extends StatelessWidget {
  const SourceInfoButton({
    super.key,
    required this.title,
    required this.details,
    this.url,
    this.color,
    this.compact = false,
  });

  final String title, details;
  final String? url;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: title,
    visualDensity: compact ? VisualDensity.compact : null,
    constraints: compact
        ? const BoxConstraints(minWidth: 32, minHeight: 32)
        : null,
    padding: compact ? EdgeInsets.zero : null,
    icon: Icon(Icons.info_outline, size: 18, color: color),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (dialog) {
        final uri = Uri.tryParse(url ?? '');
        return AlertDialog(
          scrollable: true,
          title: Text(title),
          content: SelectableText(details),
          actions: [
            if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty)
              TextButton(
                child: const Text('Buka sumber'),
                onPressed: () async {
                  try {
                    if (await launchUrl(uri)) return;
                  } catch (_) {
                    // Keep the link available to copy when a browser cannot open.
                  }
                  if (dialog.mounted) {
                    ScaffoldMessenger.of(dialog).showSnackBar(
                      const SnackBar(
                        content: Text('Tautan sumber gagal dibuka.'),
                      ),
                    );
                  }
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    ),
  );
}
