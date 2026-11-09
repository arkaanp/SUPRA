import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/app.dart';
import 'package:supra_mobile_ui/screens/login_screen.dart';

void main() {
  testWidgets(
    'Password stays editable after repeated failed logins and visibility changes',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: LoginScreen(
            signIn: (email, password) async {
              attempts++;
              throw StateError('Invalid credentials');
            },
          ),
        ),
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'person@example.com');
      for (var i = 0; i < 3; i++) {
        await tester.enterText(fields.last, 'wrong-$i');
        await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
        await tester.pumpAndSettle();
        await tester.enterText(fields.last, 'corrected-$i');
        expect(
          tester.widget<TextField>(fields.last).controller!.text,
          'corrected-$i',
        );
        await tester.tap(find.byType(IconButton).last);
        await tester.pump();
        await tester.enterText(fields.last, '');
        expect(tester.widget<TextField>(fields.last).controller!.text, isEmpty);
      }
      expect(attempts, 3);
    },
  );
}
