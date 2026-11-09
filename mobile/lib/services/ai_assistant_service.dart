import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/saved_trip.dart';
import 'supra_api_service.dart';

class ChatEnvironmentalContext {
  final String? currentLocation;
  final int? aqi;
  final String? weather;
  final String? temperature;
  final List<String>? frequentRoutes;
  final String? conditionsStatus;
  final String? conditionsSource;
  final String? conditionsObservedAt;
  final bool? conditionsStale;
  const ChatEnvironmentalContext({
    this.currentLocation,
    this.aqi,
    this.weather,
    this.temperature,
    this.frequentRoutes,
    this.conditionsStatus,
    this.conditionsSource,
    this.conditionsObservedAt,
    this.conditionsStale,
  });
  Map<String, dynamic> toJson() => {
    if (currentLocation != null) 'current_location': currentLocation,
    if (aqi != null) 'aqi': aqi,
    if (weather != null) 'weather': weather,
    if (temperature != null) 'temperature': temperature,
    if (frequentRoutes?.isNotEmpty == true) 'frequent_routes': frequentRoutes,
    if (conditionsStatus != null) 'conditions_status': conditionsStatus,
    if (conditionsSource != null) 'conditions_source': conditionsSource,
    if (conditionsObservedAt != null)
      'conditions_observed_at': conditionsObservedAt,
    if (conditionsStale != null) 'conditions_stale': conditionsStale,
  };
}

/// Gemini credentials and provider calls belong exclusively to Axum.
/// Chat is session-scoped; ambiguous legacy device-global history is not loaded.
class AiAssistantService extends ChangeNotifier {
  static final instance = AiAssistantService();
  AiAssistantService({this.send}) {
    _welcome();
  }
  final Future<Map<String, dynamic>> Function(
    String message,
    List<Map<String, dynamic>> history,
    Map<String, dynamic> context,
  )?
  send;
  final List<ChatMessage> _messages = [];
  String? _userId;
  int _generation = 0;
  bool _isLoading = false;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;

  void _welcome() => _messages.add(
    ChatMessage(
      id: 'welcome',
      sender: MessageSender.assistant,
      timestamp: DateTime.now(),
      text:
          'Halo! Saya asisten perjalanan SUPRA. Data kondisi terkini hanya tersedia '
          'bila sumber dan lokasinya diberikan; saya tidak memiliki pemantauan langsung.',
    ),
  );

  void bindUser(String? userId) {
    if (_userId == userId) return;
    _userId = userId;
    _generation++;
    _isLoading = false;
    _messages.clear();
    _welcome();
    // Remove the old client-side credential; never migrate it into requests.
    SharedPreferences.getInstance()
        .then((p) => p.remove('supra_gemini_api_key'))
        .catchError((_) => false);
    notifyListeners();
  }

  Future<void> sendMessage(
    String text, {
    ChatEnvironmentalContext? envContext,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;
    final generation = _generation;
    final history = _messages
        .where((m) => m.model != 'unavailable' && m.id != 'welcome')
        .toList()
        .reversed
        .take(6)
        .toList()
        .reversed
        .map(
          (m) => <String, dynamic>{
            'role': m.sender == MessageSender.user ? 'user' : 'model',
            'content': m.text,
          },
        )
        .toList();
    final context =
        (envContext ??
                ChatEnvironmentalContext(
                  frequentRoutes: TripHistoryStore.instance.frequentCommutes
                      .take(3)
                      .map((t) => t.routeLabel)
                      .toList(),
                ))
            .toJson();
    _messages.add(
      ChatMessage(
        id: 'user_${DateTime.now().microsecondsSinceEpoch}',
        sender: MessageSender.user,
        text: trimmed,
        timestamp: DateTime.now(),
      ),
    );
    final id = 'reply_${DateTime.now().microsecondsSinceEpoch}';
    _messages.add(
      ChatMessage(
        id: id,
        sender: MessageSender.assistant,
        text: '',
        timestamp: DateTime.now(),
        isStreaming: true,
        statusText: 'Menghubungi asisten...',
      ),
    );
    _isLoading = true;
    notifyListeners();
    var reply =
        'Asisten tidak tersedia. Periksa koneksi atau konfigurasi server. '
        'Tidak ada data kondisi terkini yang disubstitusi.';
    var model = 'unavailable';
    try {
      final response =
          await (send?.call(trimmed, history, context) ??
                  SupraService.instance.sendAgentChat(
                    message: trimmed,
                    history: history,
                    context: context,
                  ))
              .timeout(const Duration(seconds: 20));
      final result = response['reply'];
      if (response['simulated'] == true ||
          result is! String ||
          result.trim().isEmpty) {
        throw StateError('Assistant response unavailable');
      }
      reply = result;
      model = response['model'] as String? ?? 'server';
    } catch (_) {
      // Deliberately no direct Google call or fabricated offline answer.
    } finally {
      if (generation == _generation) {
        final index = _messages.indexWhere((m) => m.id == id);
        if (index >= 0) {
          _messages[index] = ChatMessage(
            id: id,
            sender: MessageSender.assistant,
            text: reply,
            timestamp: DateTime.now(),
            model: model,
            isError: model == 'unavailable',
          );
        }
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> clearHistory() async {
    _generation++;
    _isLoading = false;
    _messages.clear();
    _welcome();
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    clearHistory();
  }
}
