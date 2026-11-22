import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:supra_mobile_ui/app.dart';

void main() {
  testWidgets('Signed-out users see the sign-in form', (tester) async {
    await tester.pumpWidget(const SupraApp());
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsNWidgets(2));
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    final context = tester.element(find.byType(Scaffold).first);
    expect(Localizations.localeOf(context), const Locale('id', 'ID'));
    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Batal');
  });
}
