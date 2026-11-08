import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_assistant_service.dart';
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
    if (text.trim().isEmpty) return;

    _textController.clear();
    _scrollToBottom();

    // Get current environmental state for location context
    const ctx = ChatEnvironmentalContext(
      currentLocation: 'Kuningan, Jakarta',
      aqi: 72,
      weather: 'Moderate',
      temperature: '31°C',
    );

    await AiAssistantService.instance.sendMessage(text, envContext: ctx);
    _scrollToBottom();
  }

  void _showApiKeyDialog(BuildContext context) {
    final service = AiAssistantService.instance;
    final textCtrl = TextEditingController(text: service.customApiKey ?? '');
    bool isTesting = false;
    String? testResult;
    bool testSuccess = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final effectiveKey = service.effectiveApiKey;
          final hasKey = service.hasApiKey;

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: SupraTheme.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.key_rounded,
                    color: SupraTheme.brand,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Google Gemini API Key',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agent 1 menggunakan model Gemini dari Google AI Studio untuk analisis cuaca & kualitas udara Jabodetabek.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: SupraTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Key status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: hasKey
                          ? SupraTheme.aqiGood.withValues(alpha: 0.1)
                          : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasKey
                            ? SupraTheme.aqiGood.withValues(alpha: 0.3)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasKey ? Icons.check_circle : Icons.info_outline,
                          size: 16,
                          color: hasKey
                              ? SupraTheme.aqiGood
                              : const Color(0xFFD97706),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hasKey
                                ? 'Status: Terhubung (${effectiveKey?.substring(0, 6)}...)'
                                : 'Status: Kunci belum dipasang (Mode Offline Aktif)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: hasKey
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Masukkan Gemini API Key:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: textCtrl,
                    decoration: InputDecoration(
                      hintText: 'AIzaSy...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste, size: 18),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null) {
                            textCtrl.text = data!.text!.trim();
                          }
                        },
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Anda juga bisa memasang kunci di backend/.env (GEMINI_API_KEY) atau di mobile/config/local.json.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: SupraTheme.textSecondary,
                    ),
                  ),
                  if (testResult != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: testSuccess
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            testSuccess ? Icons.check : Icons.error_outline,
                            size: 14,
                            color: testSuccess
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              testResult!,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: testSuccess
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Batal'),
              ),
              if (textCtrl.text.trim().isNotEmpty)
                TextButton(
                  onPressed: isTesting
                      ? null
                      : () async {
                          setDialogState(() {
                            isTesting = true;
                            testResult = 'Menghubungi Google AI Studio...';
                          });
                          final ok = await service.testApiKey(textCtrl.text);
                          setDialogState(() {
                            isTesting = false;
                            testSuccess = ok;
                            testResult = ok
                                ? 'Koneksi ke Gemini berhasil!'
                                : 'Koneksi gagal. Periksa kembali API key.';
                          });
                        },
                  child: isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Tes Kunci'),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SupraTheme.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                onPressed: () async {
                  await service.setCustomApiKey(textCtrl.text);
                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Pengaturan API Key disimpan'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        },
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
                child: Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 20,
                ),
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
                          color: Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Agent 1 • Commute & Eco Advisor',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: SupraTheme.textSecondary,
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
            icon: const Icon(Icons.key_rounded, size: 20),
            tooltip: 'Gemini API Key',
            color: SupraTheme.brand,
            onPressed: () => _showApiKeyDialog(context),
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
                bottom: BorderSide(
                  color: const Color(0xFFE2E8F0),
                  width: 1,
                ),
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
                    'Kuningan, Jakarta • AQI 72 • 31°C',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: SupraTheme.onSurface,
                    ),
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
                    'Live Context',
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
                    return ChatBubble(
                      key: ValueKey(msg.id),
                      message: msg,
                    );
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
