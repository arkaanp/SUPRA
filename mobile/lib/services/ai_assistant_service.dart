import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/chat_message.dart';
import '../models/saved_trip.dart';
import 'supra_api_service.dart';

/// Environmental context passed to Agent 1 to give location-aware commute guidance.
class ChatEnvironmentalContext {
  final String? currentLocation;
  final int? aqi;
  final String? weather;
  final String? temperature;
  final List<String>? frequentRoutes;

  const ChatEnvironmentalContext({
    this.currentLocation,
    this.aqi,
    this.weather,
    this.temperature,
    this.frequentRoutes,
  });

  Map<String, dynamic> toJson() => {
        if (currentLocation != null) 'current_location': currentLocation,
        if (aqi != null) 'aqi': aqi,
        if (weather != null) 'weather': weather,
        if (temperature != null) 'temperature': temperature,
        if (frequentRoutes != null && frequentRoutes!.isNotEmpty)
          'frequent_routes': frequentRoutes,
      };
}

/// Service managing Agent 1 AI Assistant conversation, persistence,
/// and communication with Google AI Studio Gemini / backend.
class AiAssistantService extends ChangeNotifier {
  static final AiAssistantService instance = AiAssistantService._internal();

  static const String _storageKey = 'supra_chat_history_v1';
  static const String _apiKeyStorageKey = 'supra_gemini_api_key';

  AiAssistantService._internal() {
    _initDefaults();
    _loadFromStorage();
  }

  final List<ChatMessage> _messages = [];
  String? _customApiKey;
  bool _isLoading = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get customApiKey => _customApiKey;

  /// Effective API key in order of priority:
  /// 1. User in-app entered key
  /// 2. Build-time AppConfig.geminiApiKey (from local.json)
  String? get effectiveApiKey {
    if (_customApiKey != null && _customApiKey!.trim().isNotEmpty) {
      return _customApiKey!.trim();
    }
    if (AppConfig.geminiApiKey.trim().isNotEmpty) {
      return AppConfig.geminiApiKey.trim();
    }
    return null;
  }

  bool get hasApiKey => effectiveApiKey != null && effectiveApiKey!.isNotEmpty;

  void _initDefaults() {
    if (_messages.isEmpty) {
      _messages.add(
        ChatMessage(
          id: 'welcome_1',
          sender: MessageSender.assistant,
          text: 'Halo! Saya **SUPRA Agent 1**, asisten cerdas perjalanan & kualitas udara Anda di Jabodetabek.\n\n'
              'Anda bisa menanyakan rekomendasi rute, perkiraan cuaca & hujan, '
              'level polusi udara (AQI), serta jam terbaik untuk berangkat.\n\n'
              'Ada yang bisa saya bantu untuk perjalanan Anda hari ini?',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customApiKey = prefs.getString(_apiKeyStorageKey);

      final rawMessages = prefs.getString(_storageKey);
      if (rawMessages != null && rawMessages.isNotEmpty) {
        final decoded = jsonDecode(rawMessages) as List<dynamic>;
        final loaded = decoded
            .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
            .where((m) => !m.isStreaming)
            .toList();
        if (loaded.isNotEmpty) {
          _messages.clear();
          _messages.addAll(loaded);
          notifyListeners();
        }
      }
    } catch (_) {
      // Retain in-memory defaults on storage failure
    }
  }

  Future<void> _persistToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nonStreaming = _messages.where((m) => !m.isStreaming).toList();
      final serialized = jsonEncode(nonStreaming.map((m) => m.toJson()).toList());
      await prefs.setString(_storageKey, serialized);
    } catch (_) {
      // Ignore storage persistence errors
    }
  }

  /// Sets or clears in-app custom Gemini API key
  Future<void> setCustomApiKey(String? key) async {
    _customApiKey = key?.trim().isEmpty == true ? null : key?.trim();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_customApiKey == null) {
        await prefs.remove(_apiKeyStorageKey);
      } else {
        await prefs.setString(_apiKeyStorageKey, _customApiKey!);
      }
    } catch (_) {}
  }

  /// Tests connectivity to Google AI Studio Gemini with the given key
  Future<bool> testApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return false;
    final modelCandidates = <String>[
      AppConfig.geminiModel,
      if (AppConfig.geminiModel != 'gemini-3.5-flash') 'gemini-3.5-flash',
      'gemini-flash-latest',
      'gemini-3.8-flash',
      'gemini-2.5-flash-lite',
      'gemini-1.5-flash',
    ];

    for (final model in modelCandidates) {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$trimmed',
      );
      try {
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': 'Ping'}
                    ]
                  }
                ]
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Sends a message from the user and queries the AI assistant.
  Future<void> sendMessage(
    String text, {
    ChatEnvironmentalContext? envContext,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;

    // 1. Add user message
    final userMsg = ChatMessage(
      id: 'msg_user_${DateTime.now().millisecondsSinceEpoch}',
      sender: MessageSender.user,
      text: trimmed,
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);

    // 2. Add placeholder assistant streaming message
    final assistantId = 'msg_ast_${DateTime.now().millisecondsSinceEpoch}';
    final placeholder = ChatMessage(
      id: assistantId,
      sender: MessageSender.assistant,
      text: '',
      timestamp: DateTime.now(),
      isStreaming: true,
      statusText: 'Menganalisis kondisi & rute...',
    );
    _messages.add(placeholder);
    _isLoading = true;
    notifyListeners();

    // 3. Prepare context (including frequent routes from TripHistoryStore)
    final savedTrips = TripHistoryStore.instance.trips
        .take(3)
        .map((t) => '${t.start} → ${t.destination}')
        .toList();

    final contextPayload = ChatEnvironmentalContext(
      currentLocation: envContext?.currentLocation ?? 'Kuningan, Jakarta',
      aqi: envContext?.aqi ?? 72,
      weather: envContext?.weather ?? 'Moderate',
      temperature: envContext?.temperature ?? '31°C',
      frequentRoutes: envContext?.frequentRoutes ?? savedTrips,
    ).toJson();

    // Prepare recent history
    final historyPayload = _messages
        .where((m) => !m.isStreaming && m.id != assistantId && m.id != userMsg.id)
        .toList()
        .reversed
        .take(6)
        .toList()
        .reversed
        .map((m) => {
              'role': m.sender == MessageSender.user ? 'user' : 'model',
              'content': m.text,
            })
        .toList();

    String replyText = '';
    String modelName = 'supra-agent';

    try {
      // Strategy A: Try backend endpoint POST /api/agent/chat
      try {
        final backendResp = await SupraService.instance
            .sendAgentChat(
              message: trimmed,
              history: historyPayload,
              context: contextPayload,
              apiKeyOverride: effectiveApiKey,
            )
            .timeout(const Duration(seconds: 12));

        replyText = backendResp['reply'] as String? ?? '';
        modelName = backendResp['model'] as String? ?? 'gemini-1.5-flash';
      } catch (_) {
        // Backend unavailable or unauthorized -> proceed to Strategy B
      }

      // Strategy B: If backend didn't return reply, try direct Google AI Studio call if key exists
      if (replyText.isEmpty && hasApiKey) {
        try {
          replyText = await _callGeminiDirect(
            apiKey: effectiveApiKey!,
            userPrompt: trimmed,
            history: historyPayload,
            context: contextPayload,
          ).timeout(const Duration(seconds: 14));
          modelName = AppConfig.geminiModel;
        } catch (_) {
          // Direct call failed -> fall through to Strategy C
        }
      }

      // Strategy C: Smart local commute agent fallback
      if (replyText.isEmpty) {
        replyText = _generateLocalFallback(trimmed, contextPayload);
        modelName = 'supra-commute-agent';
      }
    } finally {
      // 4. Update assistant message with completed reply
      final index = _messages.indexWhere((m) => m.id == assistantId);
      if (index >= 0) {
        _messages[index] = ChatMessage(
          id: assistantId,
          sender: MessageSender.assistant,
          text: replyText,
          timestamp: DateTime.now(),
          isStreaming: false,
          model: modelName,
        );
      }
      _isLoading = false;
      notifyListeners();
      _persistToStorage();
    }
  }

  /// Calls Google AI Studio Gemini API directly from client
  Future<String> _callGeminiDirect({
    required String apiKey,
    required String userPrompt,
    required List<Map<String, dynamic>> history,
    required Map<String, dynamic> context,
  }) async {
    final systemInstruction =
        'You are SUPRA Agent 1, the AI Commute & Environmental Assistant for Greater Jakarta (Jabodetabek). '
        'Provide helpful, concise, actionable advice for commuters on weather, air quality (AQI), '
        'traffic congestion, flood spots, odd-even rules, and public transit (MRT, LRT, KRL, TransJakarta). '
        'Respond in the same language as the user (Indonesian or English). Use clean markdown formatting.';

    String contextStr = '\n[User Commute Context]:\n'
        '- Location: ${context['current_location']}\n'
        '- AQI: ${context['aqi']}\n'
        '- Weather: ${context['weather']}\n'
        '- Temperature: ${context['temperature']}\n';
    if (context['frequent_routes'] != null) {
      contextStr += '- Saved Routes: ${context['frequent_routes']}\n';
    }

    final contents = <Map<String, dynamic>>[];
    for (final h in history) {
      contents.add({
        'role': h['role'],
        'parts': [
          {'text': h['content']}
        ]
      });
    }
    contents.add({
      'role': 'user',
      'parts': [
        {'text': '$contextStr\n$userPrompt'}
      ]
    });

    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': systemInstruction}
        ]
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 1000,
      }
    });

    final modelCandidates = <String>[
      AppConfig.geminiModel,
      if (AppConfig.geminiModel != 'gemini-3.5-flash') 'gemini-3.5-flash',
      'gemini-flash-latest',
      'gemini-3.8-flash',
      'gemini-2.5-flash-lite',
      'gemini-1.5-flash',
    ];

    for (final model in modelCandidates) {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
      );
      try {
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final candidates = json['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List<dynamic>?;
            if (parts != null && parts.isNotEmpty) {
              final text = parts[0]['text'] as String?;
              if (text != null && text.trim().isNotEmpty) {
                return text.trim();
              }
            }
          }
        }
      } catch (_) {}
    }
    throw StateError('Gemini API call failed for all models');
  }

  /// Generates helpful domain-expert response locally when offline
  String _generateLocalFallback(String query, Map<String, dynamic> context) {
    final lower = query.toLowerCase();
    final loc = context['current_location'] ?? 'Jakarta';
    final aqi = context['aqi'] ?? 72;
    final weather = context['weather'] ?? 'Moderate';

    String reply;
    if (lower.contains('aqi') ||
        lower.contains('air') ||
        lower.contains('udara') ||
        lower.contains('polusi')) {
      reply = '### 🌬️ Kualitas Udara di $loc\n\n'
          '- **Indeks AQI:** $aqi (Moderate)\n'
          '- **Polutan Utama:** PM2.5\n'
          '- **Saran Kesehatan:** Udara cukup aman, namun jika mengendarai sepeda motor atau berjalan di jalan protokol (seperti Sudirman / Gatot Subroto), disarankan mengenakan masker KN95/KF94.';
    } else if (lower.contains('rain') ||
        lower.contains('hujan') ||
        lower.contains('cuaca') ||
        lower.contains('weather')) {
      reply = '### 🌧️ Prakiraan Cuaca & Dampak Perjalanan\n\n'
          '- **Kondisi:** $weather\n'
          '- **Peluang Hujan:** Potensi hujan lokal meningkat pada sore hari (15:00 - 18:30 WIB).\n'
          '- **Titik Rawan Macet/Genangan:** Cawang, MT Haryono, dan underpass Rasuna Said.\n'
          '- **Rekomendasi:** Gunakan transportasi rel seperti MRT atau LRT jika hujan lebat untuk menghindari perlambatan jalan raya 30–50%.';
    } else if (lower.contains('traffic') ||
        lower.contains('macet') ||
        lower.contains('scbd') ||
        lower.contains('rute') ||
        lower.contains('route')) {
      reply = '### 🚦 Panduan Lalu Lintas & Rute Jabodetabek\n\n'
          '- **Jam Sibuk:** 07:00 – 09:30 WIB dan 17:00 – 20:00 WIB.\n'
          '- **Aturan Ganjil-Genap:** Berlaku pada hari kerja di 25 ruas jalan protokol.\n'
          '- **Tips Cepat:** Berangkat 20 menit lebih awal sebelum jam 16:30 dapat memangkas waktu tempuh hingga 30 menit.';
    } else if (lower.contains('jam') ||
        lower.contains('berangkat') ||
        lower.contains('time') ||
        lower.contains('kapan')) {
      reply = '### ⏱️ Rekomendasi Waktu Berangkat\n\n'
          'Berdasarkan data lingkungan saat ini di $loc (AQI $aqi):\n\n'
          '- **Waktu Terbaik:** **15:45 – 16:15 WIB** (sebelum puncak kepadatan sore dan penumpukan emisi kendaraan).\n'
          '- **Alternatif Malam:** **Setelah pukul 19:30 WIB** ketika kepadatan arteri utama mulai terurai.';
    } else {
      reply = '### 👋 Halo! Saya SUPRA Agent 1\n\n'
          'Asisten pintar perjalanan dan lingkungan Anda di $loc.\n\n'
          'Saya siap membantu Anda dengan:\n'
          '• 🌬️ Informasi AQI & kualitas udara real-time\n'
          '• 🌧️ Prakiraan cuaca & titik rawan genangan air\n'
          '• 🚦 Rekomendasi jam berangkat optimal & aturan Ganjil-Genap\n'
          '• 🚇 Alternatif transportasi umum (MRT, LRT, KRL, TransJakarta)';
    }

    if (!hasApiKey) {
      reply +=
          '\n\n*(Catatan: Mode kecerdasan offline aktif. Pasang `GEMINI_API_KEY` di `backend/.env` atau ikon kunci di atas untuk menghubungkan ke live Google AI Studio Gemini)*';
    }

    return reply;
  }

  /// Clears chat history and restarts with default welcome message.
  Future<void> clearHistory() async {
    _messages.clear();
    _initDefaults();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTesting() {
    _messages.clear();
    _initDefaults();
    _customApiKey = null;
    _isLoading = false;
    notifyListeners();
  }
}

