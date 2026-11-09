import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supra_mobile_ui/services/display_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DisplayPreferences.instance.resetForTesting();
  });

  test('ML prediction display is off by default and persists when enabled', () async {
    final preferences = DisplayPreferences.instance;
    await preferences.load();
    expect(preferences.showMlPredictions, isFalse);

    await preferences.setShowMlPredictions(true);
    expect(preferences.showMlPredictions, isTrue);

    final stored = await SharedPreferences.getInstance();
    expect(stored.getBool('supra_show_ml_predictions'), isTrue);
  });

  test('A stored opt-in is restored on the next load', () async {
    SharedPreferences.setMockInitialValues({
      'supra_show_ml_predictions': true,
    });
    final preferences = DisplayPreferences();
    await preferences.load();
    expect(preferences.showMlPredictions, isTrue);
  });
}
