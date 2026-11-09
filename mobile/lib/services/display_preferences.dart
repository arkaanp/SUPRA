import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-controlled display options that never change the underlying data.
/// Enabling ML predictions only asks the UI to show model output when the
/// backend actually provides it; it never fabricates missing future values.
class DisplayPreferences extends ChangeNotifier {
  static final instance = DisplayPreferences();
  static const _mlKey = 'supra_show_ml_predictions';

  bool _showMlPredictions = false;
  bool _loaded = false;

  bool get showMlPredictions => _showMlPredictions;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showMlPredictions = prefs.getBool(_mlKey) ?? false;
    } catch (_) {
      /* A missing preference store keeps the safe default. */
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> setShowMlPredictions(bool value) async {
    if (_showMlPredictions == value) return;
    _showMlPredictions = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_mlKey, value);
    } catch (_) {
      /* The in-memory choice still applies for this session. */
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _showMlPredictions = false;
    _loaded = true;
    notifyListeners();
  }
}
