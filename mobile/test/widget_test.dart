import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/app.dart';

void main() {
  testWidgets('Signed-out users see the sign-in form', (tester) async {
    await tester.pumpWidget(const SupraApp());
    expect(find.text('Sign in'), findsNWidgets(2));
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
