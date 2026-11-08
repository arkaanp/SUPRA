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

  /// Whether message resulted in an error
  final bool isError;

  /// Model name that generated this message (e.g. "gemini-1.5-flash")
  final String? model;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.isStreaming = false,
    this.statusText,
    this.isError = false,
    this.model,
  });

  ChatMessage copyWith({
    String? text,
    bool? isStreaming,
    String? statusText,
    bool? isError,
    String? model,
  }) =>
      ChatMessage(
        id: id,
        sender: sender,
        text: text ?? this.text,
        timestamp: timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
        statusText: statusText ?? this.statusText,
        isError: isError ?? this.isError,
        model: model ?? this.model,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': sender == MessageSender.user ? 'user' : 'assistant',
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'is_streaming': isStreaming,
        if (statusText != null) 'status_text': statusText,
        'is_error': isError,
        if (model != null) 'model': model,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        sender: json['sender'] == 'user'
            ? MessageSender.user
            : MessageSender.assistant,
        text: json['text'] as String? ?? '',
        timestamp: json['timestamp'] != null
            ? (DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now())
            : DateTime.now(),
        isStreaming: json['is_streaming'] as bool? ?? false,
        statusText: json['status_text'] as String?,
        isError: json['is_error'] as bool? ?? false,
        model: json['model'] as String?,
      );
}
