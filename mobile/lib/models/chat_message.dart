enum MessageSender { user, assistant }

/// A single message in the Agent 1 conversational chat screen.
class ChatMessage {
  final String id;
  final MessageSender sender;
  final String text;
  final DateTime timestamp;

  /// While true the assistant message is still being streamed in.
  final bool isStreaming;

  /// Optional status label shown while streaming (e.g. which forecast tool is running).
  final String? statusText;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.isStreaming = false,
    this.statusText,
  });

  ChatMessage copyWith({String? text, bool? isStreaming, String? statusText}) =>
      ChatMessage(
        id: id,
        sender: sender,
        text: text ?? this.text,
        timestamp: timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
        statusText: statusText ?? this.statusText,
      );
}
