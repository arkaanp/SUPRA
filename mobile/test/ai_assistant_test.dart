import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supra_mobile_ui/screens/chat_screen.dart';
import 'package:supra_mobile_ui/services/ai_assistant_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Only backend is called, with no invented environmental context',
    () async {
      final service = AiAssistantService(
        send: (message, history, context) async {
          expect(message, 'Current AQI?');
          expect(history, isEmpty);
          expect(context, isEmpty);
          return {
            'reply': 'Current measurements unavailable',
            'model': 'configured-model',
            'simulated': false,
          };
        },
      );
      await service.sendMessage('Current AQI?');
      expect(service.messages.last.text, 'Current measurements unavailable');
      expect(service.messages.last.model, 'configured-model');
      expect(service.isLoading, false);
    },
  );
  test('Environmental context is sent to Gemini only as labelled, untrusted data', () async {
    final context = ChatEnvironmentalContext(
      currentLocation: '-6.2297, 106.8295',
      aqi: 88,
      weather: 'Rain',
      temperature: '29°C',
      conditionsStatus: 'weather=stale; air=available; traffic=unavailable',
      conditionsSource: 'open_meteo, openaq, tomtom',
      conditionsObservedAt: '2026-11-09T04:00:00Z',
      conditionsStale: true,
    );
    final json = context.toJson();
    expect(json['aqi'], 88);
    expect(json['weather'], 'Rain');
    expect(json['conditions_stale'], isTrue);
    expect(json['conditions_observed_at'], '2026-11-09T04:00:00Z');
    final service = AiAssistantService(
      send: (message, history, received) async {
        expect(received['aqi'], 88);
        expect(received['conditions_stale'], isTrue);
        return {
          'reply': 'Last-known reading is stale; verify before travelling.',
          'model': 'configured-model',
          'simulated': false,
        };
      },
    );
    await service.sendMessage('Is the air safe?', envContext: context);
    expect(service.messages.last.text, contains('stale'));
  });

  test(
    'Failure and simulated replies never become invented offline advice',
    () async {
      for (final fail in [true, false]) {
        final service = AiAssistantService(
          send: (_, _, _) async {
            if (fail) throw StateError('503');
            return {'reply': 'AQI 72', 'simulated': true};
          },
        );
        await service.sendMessage('Weather today?');
        expect(service.messages.last.model, 'unavailable');
        expect(service.messages.last.text, isNot(contains('72')));
        expect(service.isLoading, false);
      }
    },
  );
  test(
    'Late replies cannot leak into a different account or cleared session',
    () async {
      final result = Completer<Map<String, dynamic>>();
      final service = AiAssistantService(send: (_, _, _) => result.future);
      service.bindUser('alice');
      final request = service.sendMessage('private');
      service.bindUser('bob');
      result.complete({'reply': 'Alice private answer', 'simulated': false});
      await request;
      expect(service.messages.length, 1);
      expect(service.isLoading, false);
    },
  );
  test('Legacy stored API key is removed rather than used', () async {
    SharedPreferences.setMockInitialValues({
      'supra_gemini_api_key': 'old-secret',
    });
    final service = AiAssistantService();
    service.bindUser('alice');
    await Future<void>.delayed(Duration.zero);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'supra_gemini_api_key',
      ),
      false,
    );
  });
  testWidgets('Assistant has no key prompt or fictional context pill', (
    tester,
  ) async {
    AiAssistantService.instance.resetForTesting();
    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    expect(find.byIcon(Icons.key_rounded), findsNothing);
    expect(find.textContaining('No live conditions attached'), findsOneWidget);
    expect(find.textContaining('AQI 72'), findsNothing);
  });
}
