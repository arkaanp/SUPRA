import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../theme/app_theme.dart';

/// One message bubble in the Agent 1 chat screen.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onCopy;

  const ChatBubble({super.key, required this.message, this.onCopy});

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == MessageSender.user;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Assistant Avatar
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8, bottom: 4),
              decoration: BoxDecoration(
                color: SupraTheme.brand.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: SupraTheme.brand.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: SupraTheme.brand,
                ),
              ),
            ),
          ],

          // Bubble Container
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Pesan disalin ke clipboard'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    onCopy?.call();
                  },
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? SupraTheme.brand : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft:
                            isUser ? const Radius.circular(16) : Radius.zero,
                        bottomRight:
                            isUser ? Radius.zero : const Radius.circular(16),
                      ),
                      boxShadow: isUser
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                      border: isUser
                          ? null
                          : Border.all(
                              color: const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.isStreaming) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    SupraTheme.brand,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                message.statusText ??
                                    'SUPRA Assistant sedang berpikir…',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: SupraTheme.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                          if (message.text.isNotEmpty)
                            const SizedBox(height: 8),
                        ],
                        if (message.text.isNotEmpty || !message.isStreaming)
                          _buildFormattedText(context, message.text, isUser),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isUser && message.model != null && !message.isStreaming) ...[
                      Text(
                        message.model!,
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      message.isStreaming ? '' : _time(message.timestamp),
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormattedText(
    BuildContext context,
    String text,
    bool isUser,
  ) {
    final baseColor = isUser ? Colors.white : const Color(0xFF0F172A);
    final lines = text.split('\n');
    final children = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 6));
        continue;
      }

      // Heading ###
      if (line.startsWith('### ')) {
        final heading = line.substring(4);
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              heading,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: isUser ? Colors.white : SupraTheme.brand,
              ),
            ),
          ),
        );
        continue;
      }

      // Heading ##
      if (line.startsWith('## ')) {
        final heading = line.substring(3);
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              heading,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: isUser ? Colors.white : SupraTheme.brand,
              ),
            ),
          ),
        );
        continue;
      }

      // Bullet points
      final isBullet = line.startsWith('- ') ||
          line.startsWith('• ') ||
          line.startsWith('* ');
      final content = isBullet ? line.substring(2) : line;

      final spans = _parseInlineSpans(content, baseColor, isUser);

      if (isBullet) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 1, bottom: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: TextStyle(
                    color: isUser ? Colors.white70 : SupraTheme.brand,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: spans,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: baseColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Text.rich(
            TextSpan(
              children: spans,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: baseColor,
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  List<InlineSpan> _parseInlineSpans(
    String line,
    Color baseColor,
    bool isUser,
  ) {
    final spans = <InlineSpan>[];
    // Split on ** for bold
    final parts = line.split('**');
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;
      final isBold = i % 2 == 1;

      // Check for note formatting in italics: *(...)*
      if (part.startsWith('*(') && part.endsWith(')*')) {
        spans.add(
          TextSpan(
            text: part.substring(1, part.length - 1),
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: isUser ? Colors.white70 : SupraTheme.textSecondary,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: part,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
              color: baseColor,
            ),
          ),
        );
      }
    }
    return spans;
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
