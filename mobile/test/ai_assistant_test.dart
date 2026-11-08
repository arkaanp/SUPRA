import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supra_mobile_ui/models/chat_message.dart';
import 'package:supra_mobile_ui/screens/chat_screen.dart';
import 'package:supra_mobile_ui/services/ai_assistant_service.dart';
import 'package:supra_mobile_ui/widgets/chat_bubble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AiAssistantService.instance.resetForTesting();
  });

  group('ChatMessage model tests', () {
    test('ChatMessage serializes and deserializes correctly', () {
      final now = DateTime.now();
      final msg = ChatMessage(
        id: 'msg_101',
        sender: MessageSender.user,
        text: 'Bagaimana rute ke SCBD?',
        timestamp: now,
        isStreaming: false,
        model: 'gemini-1.5-flash',
      );

      final json = msg.toJson();
      expect(json['id'], 'msg_101');
      expect(json['sender'], 'user');
      expect(json['text'], 'Bagaimana rute ke SCBD?');
      expect(json['model'], 'gemini-1.5-flash');

      final deserialized = ChatMessage.fromJson(json);
      expect(deserialized.id, msg.id);
      expect(deserialized.sender, MessageSender.user);
      expect(deserialized.text, msg.text);
      expect(deserialized.model, 'gemini-1.5-flash');
    });

    test('ChatMessage copyWith preserves or updates fields', () {
      final msg = ChatMessage(
        id: 'msg_1',
        sender: MessageSender.assistant,
        text: 'Thinking...',
        timestamp: DateTime.now(),
        isStreaming: true,
        statusText: 'Loading...',
      );

      final updated = msg.copyWith(
        text: 'Here is your forecast.',
        isStreaming: false,
        statusText: null,
      );

      expect(updated.id, 'msg_1');
      expect(updated.sender, MessageSender.assistant);
      expect(updated.text, 'Here is your forecast.');
      expect(updated.isStreaming, isFalse);
    });
  });

  group('AiAssistantService tests', () {
    test('Initializes with welcoming message', () {
      final service = AiAssistantService.instance;
      expect(service.messages, isNotEmpty);
      expect(service.messages.first.sender, MessageSender.assistant);
      expect(service.messages.first.text, contains('SUPRA Agent 1'));
    });

    test('Sending message adds user message and generates response', () async {
      final service = AiAssistantService.instance;
      final initialCount = service.messages.length;

      await service.sendMessage(
        'Bagaimana kualitas udara hari ini?',
        envContext: const ChatEnvironmentalContext(
          currentLocation: 'Kuningan, Jakarta',
          aqi: 72,
          weather: 'Moderate',
          temperature: '31°C',
        ),
      );

      // User message + Assistant reply added
      expect(service.messages.length, initialCount + 2);
      expect(service.messages[initialCount].sender, MessageSender.user);
      expect(service.messages[initialCount].text, 'Bagaimana kualitas udara hari ini?');

      final assistantMsg = service.messages[initialCount + 1];
      expect(assistantMsg.sender, MessageSender.assistant);
      expect(assistantMsg.isStreaming, isFalse);
      expect(assistantMsg.text, contains('Kualitas Udara'));
    });

    test('Saving and retrieving custom API key', () async {
      final service = AiAssistantService.instance;
      expect(service.hasApiKey, isFalse);

      await service.setCustomApiKey('AIzaSyTestKey123456');
      expect(service.customApiKey, 'AIzaSyTestKey123456');
      expect(service.effectiveApiKey, 'AIzaSyTestKey123456');
      expect(service.hasApiKey, isTrue);

      await service.setCustomApiKey(null);
      expect(service.customApiKey, isNull);
    });

    test('clearHistory resets to initial welcome message', () async {
      final service = AiAssistantService.instance;
      await service.sendMessage('Pertanyaan pertama');
      expect(service.messages.length, greaterThan(1));

      await service.clearHistory();
      expect(service.messages.length, 1);
      expect(service.messages.first.text, contains('SUPRA Agent 1'));
    });
  });

  group('ChatBubble widget tests', () {
    testWidgets('Renders user message bubble properly', (tester) async {
      final msg = ChatMessage(
        id: 'u1',
        sender: MessageSender.user,
        text: 'Halo asisten!',
        timestamp: DateTime(2026, 11, 8, 14, 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(message: msg),
          ),
        ),
      );

      expect(find.text('Halo asisten!'), findsOneWidget);
      expect(find.text('14:30'), findsOneWidget);
    });

    testWidgets('Renders assistant message with avatar and formatted text', (tester) async {
      final msg = ChatMessage(
        id: 'a1',
        sender: MessageSender.assistant,
        text: '### 🌬️ Rekomendasi\n- **Gunakan masker** saat berkendara',
        timestamp: DateTime(2026, 11, 8, 14, 31),
        model: 'gemini-1.5-flash',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(message: msg),
          ),
        ),
      );

      expect(find.text('🌬️ Rekomendasi'), findsOneWidget);
      expect(find.textContaining('Gunakan masker'), findsOneWidget);
      expect(find.text('gemini-1.5-flash'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('Renders streaming progress indicator', (tester) async {
      final msg = ChatMessage(
        id: 'a2',
        sender: MessageSender.assistant,
        text: '',
        timestamp: DateTime.now(),
        isStreaming: true,
        statusText: 'Menganalisis rute...',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(message: msg),
          ),
        ),
      );

      expect(find.text('Menganalisis rute...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('ChatScreen UI widget tests', () {
    testWidgets('Renders ChatScreen AppBar, Context Pill, and quick action chips', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChatScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // AppBar items
      expect(find.text('SUPRA Assistant'), findsOneWidget);
      expect(find.text('Agent 1 • Commute & Eco Advisor'), findsOneWidget);
      expect(find.byIcon(Icons.key_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);

      // Context pill
      expect(find.text('Live Context'), findsOneWidget);
      expect(find.textContaining('Kuningan, Jakarta'), findsOneWidget);

      // Quick prompt chips
      expect(find.text('🌤️ Kualitas udara hari ini'), findsOneWidget);
      expect(find.text('🚗 Jam terbaik berangkat ke SCBD'), findsOneWidget);

      // Text input field
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Tapping key button opens Google Gemini API key dialog', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChatScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.key_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Google Gemini API Key'), findsOneWidget);
      expect(find.text('Masukkan Gemini API Key:'), findsOneWidget);
      expect(find.text('Simpan'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);

      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.text('Google Gemini API Key'), findsNothing);
    });

    testWidgets('Tapping quick prompt chip sends query and displays assistant reply', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChatScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('🌤️ Kualitas udara hari ini'));
      await tester.pump();
      await tester.pumpAndSettle();

      // User prompt bubble is displayed
      expect(
        find.widgetWithText(ChatBubble, '🌤️ Kualitas udara hari ini'),
        findsOneWidget,
      );
      // Assistant replied with air quality information
      expect(find.textContaining('Kualitas Udara'), findsWidgets);
    });
  });
}
