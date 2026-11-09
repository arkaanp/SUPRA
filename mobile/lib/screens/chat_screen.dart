import 'package:flutter/material.dart';

import '../services/ai_assistant_service.dart';
import '../services/conditions_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_bubble.dart';

/// The Agent 1 Conversational Trip-Forecast & Eco Assistant screen.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<String> _quickPrompts = const [
    '🌤️ Kualitas udara hari ini',
    '🚗 Jam terbaik berangkat ke SCBD',
    '🌧️ Apakah sore ini akan hujan di Jakarta?',
    '😷 Apakah saya perlu pakai masker hari ini?',
    '🚇 Rekomendasi rute menghindari genangan air',
  ];

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend([String? textToSend]) async {
    final text = textToSend ?? _textController.text;
    if (text.trim().isEmpty || AiAssistantService.instance.isLoading) return;

    _textController.clear();
    _scrollToBottom();

    await AiAssistantService.instance.sendMessage(
      text,
      envContext: _currentEnvironmentalContext(),
    );
    _scrollToBottom();
  }

  /// Shares the last resolved condition snapshot with the server-side Gemini
  /// call. Values remain user-supplied context, never verified live facts, and
  /// stale readings stay labelled as stale.
  ChatEnvironmentalContext? _currentEnvironmentalContext() {
    final snapshot = ConditionsRepository.instance.latest;
    if (snapshot == null) return null;
    final air = snapshot.airQuality;
    final weather = snapshot.weather;
    final aqi = air.data?['aqi_standard'] == 'US EPA'
        ? air.number('aqi')?.round()
        : null;
    final code = weather.number('weather_code')?.toInt();
    final description = weather.data?['description'] as String?;
    final weatherText = description ?? switch (code ?? -1) {
      0 => 'Clear',
      1 || 2 => 'Partly cloudy',
      3 => 'Cloudy',
      45 || 48 => 'Fog',
      >= 51 && <= 57 => 'Drizzle',
      >= 61 && <= 67 || >= 80 && <= 82 => 'Rain',
      >= 95 && <= 99 => 'Thunderstorm',
      _ => null,
    };
    final temperature = weather.number('temperature_c');
    return ChatEnvironmentalContext(
      currentLocation:
          '${snapshot.latitude.toStringAsFixed(4)}, ${snapshot.longitude.toStringAsFixed(4)}',
      aqi: aqi,
      weather: weatherText,
      temperature: temperature == null
          ? null
          : '${temperature.toStringAsFixed(0)}°C',
      conditionsStatus: [
        'weather=${weather.status}',
        'air=${air.status}',
        'traffic=${snapshot.traffic.status}',
      ].join('; '),
      conditionsSource: [
        weather.source,
        air.source,
        snapshot.traffic.source,
      ].join(', '),
      conditionsObservedAt: weather.validAt?.toUtc().toIso8601String(),
      conditionsStale:
          weather.isStale || air.isStale || snapshot.traffic.isStale,
    );
  }

  void _showConnectionInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SUPRA Assistant'),
        content: const Text(
          'Gemini is configured on the SUPRA server. No client API key is needed. '
          'The latest resolved location conditions, including stale values, are sent as '
          'untrusted context when available. This assistant only answers Greater Jakarta '
          'commute, route, air quality, weather, traffic, alert, and packing questions; '
          'unrelated requests are declined. Future ML predictions are never invented.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _confirmClearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Hapus Riwayat Chat?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Seluruh pesan dalam sesi ini akan dihapus dan kembali ke percakapan awal.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              AiAssistantService.instance.clearHistory();
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assistantService = AiAssistantService.instance;
    final envContext = _currentEnvironmentalContext();
    final contextLabel = envContext == null
        ? 'No live conditions attached'
        : [
            if (envContext.aqi != null) 'AQI ${envContext.aqi}',
            if (envContext.weather != null) envContext.weather!,
            if (envContext.temperature != null) envContext.temperature!,
            if (envContext.conditionsStale == true) 'STALE',
          ].join(' · ');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [SupraTheme.brand, Color(0xFF0D9488)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SUPRA Assistant',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: SupraTheme.onSurface,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6.5,
                        height: 6.5,
                        decoration: const BoxDecoration(
                          color: Colors.blueGrey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Flexible(
                        child: Text(
                          'Agent 1 • Commute & Eco Advisor',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: SupraTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Key Configuration Button
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'Assistant connection',
            color: SupraTheme.brand,
            onPressed: () => _showConnectionInfo(context),
          ),
          // Clear Chat History Button
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            tooltip: 'Hapus Chat',
            color: SupraTheme.textSecondary,
            onPressed: _confirmClearChat,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Context Pill Header: Shows current location, AQI and weather shared with AI
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: const Color(0xFFE2E8F0), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  size: 13,
                  color: SupraTheme.brand,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    contextLabel.isEmpty
                        ? 'Conditions attached (no numeric values)'
                        : contextLabel,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: SupraTheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: SupraTheme.brand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Server AI',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: SupraTheme.brand,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Messages List View
          Expanded(
            child: ListenableBuilder(
              listenable: assistantService,
              builder: (context, _) {
                final messages = assistantService.messages;

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return ChatBubble(key: ValueKey(msg.id), message: msg);
                  },
                );
              },
            ),
          ),

          // Quick Prompt Carousel (Chips)
          Container(
            height: 38,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _quickPrompts.length,
              separatorBuilder: (context, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final prompt = _quickPrompts[index];
                return ActionChip(
                  label: Text(
                    prompt,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: SupraTheme.onSurface,
                    ),
                  ),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onPressed: assistantService.isLoading
                      ? null
                      : () => _handleSend(prompt),
                );
              },
            ),
          ),

          // Input Bar at the bottom
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  offset: const Offset(0, -2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleSend(),
                        decoration: const InputDecoration(
                          hintText: 'Tanya rute, cuaca, atau polusi udara...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: SupraTheme.textSecondary,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ListenableBuilder(
                    listenable: assistantService,
                    builder: (context, _) {
                      final isLoading = assistantService.isLoading;
                      return Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isLoading
                              ? SupraTheme.brand.withValues(alpha: 0.5)
                              : SupraTheme.brand,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                          onPressed: isLoading ? null : () => _handleSend(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
