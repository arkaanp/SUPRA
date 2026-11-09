import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supra_mobile_ui/screens/chat_screen.dart';
import 'package:supra_mobile_ui/screens/home_screen.dart';
import 'package:supra_mobile_ui/screens/notifications_screen.dart';
import 'package:supra_mobile_ui/screens/trip_screen.dart';
import 'package:supra_mobile_ui/services/ai_assistant_service.dart';
import 'package:supra_mobile_ui/services/display_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DisplayPreferences.instance.resetForTesting();
    AiAssistantService.instance.resetForTesting();
  });

  Future<void> pumpAt16By9(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('Home has no render overflow at 16:9', (tester) async {
    await pumpAt16By9(tester, const HomeScreen());
  });

  testWidgets('Assistant has no render overflow at 16:9', (tester) async {
    await pumpAt16By9(tester, const ChatScreen());
  });

  testWidgets('Alerts has no render overflow at 16:9', (tester) async {
    await pumpAt16By9(tester, const NotificationsScreen());
  });

  testWidgets('Trip planner has no render overflow at 16:9', (tester) async {
    await pumpAt16By9(tester, const TripScreen());
  });
}
