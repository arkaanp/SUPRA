import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/map_config.dart';
import '../models/chat_message.dart';
import '../models/trip.dart';
import 'supra_api_service.dart';

class ChatEnvironmentalContext {
  final String? currentLocation;
  final int? aqi;
  final String? weather;
  final String? temperature;
  final List<String>? frequentRoutes;
  final List<double>? point;
  final Map<String, dynamic>? selectedRoute;
  const ChatEnvironmentalContext({
    this.currentLocation,
    this.aqi,
    this.weather,
    this.temperature,
    this.frequentRoutes,
    this.point,
    this.selectedRoute,
  });
  Map<String, dynamic> toJson() => {
    if (currentLocation != null) 'current_location': currentLocation,
    if (point != null) 'point': point,
    if (selectedRoute != null) 'selected_route': selectedRoute,
    if (aqi != null) 'aqi': aqi,
    if (weather != null) 'weather': weather,
    if (temperature != null) 'temperature': temperature,
    if (frequentRoutes?.isNotEmpty == true) 'frequent_routes': frequentRoutes,
  };
}

/// Gemini credentials and provider calls belong exclusively to Axum.
/// Chat is session-scoped; ambiguous legacy device-global history is not loaded.
class AiAssistantService extends ChangeNotifier {
  static final instance = AiAssistantService();
  AiAssistantService({this.send}) {
    _welcome();
  }
  final Future<Map<String, dynamic>> Function(
    String message,
    List<Map<String, dynamic>> history,
    Map<String, dynamic> context,
  )?
  send;
  final List<ChatMessage> _messages = [];
  String? _userId;
  int _generation = 0;
  bool _isLoading = false;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;

  Map<String, dynamic>? _selectedRoute;
  List<double>? _selectedPoint;
  String? _locationName;
  Map<String, dynamic>? get selectedRoute => _selectedRoute;
  Trip? get _activeTrip {
    final candidates = SupraService.instance.activeTrips
        .where(
          (t) =>
              !t.plannedDeparture.isAfter(
                DateTime.now().add(const Duration(minutes: 30)),
              ) &&
              t.startPoint != null &&
              t.destPoint != null,
        )
        .toList();
    candidates.sort(
      (a, b) => (b.confirmedAt ?? b.plannedDeparture).compareTo(
        a.confirmedAt ?? a.plannedDeparture,
      ),
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  String? get selectionLabel => _selectedRoute != null
      ? '${_selectedRoute!['origin_name']} → ${_selectedRoute!['destination_name']} · ${_selectedRoute!['mode']}'
      : _activeTrip != null
      ? '${_activeTrip!.startLocation} → ${_activeTrip!.destination} · ${_activeTrip!.transportMode}'
      : _locationName;
  void selectRoute(Map<String, dynamic>? route) {
    _selectedRoute = route;
    notifyListeners();
  }

  void selectLocation(String name, List<double> point) {
    _locationName = name;
    _selectedPoint = point;
    notifyListeners();
  }

  void _welcome() => _messages.add(
    ChatMessage(
      id: 'welcome',
      sender: MessageSender.assistant,
      timestamp: DateTime.now(),
      text: 'Halo! Saya asisten perjalanan SUPRA. Pilih lokasi di Beranda atau rute di Perjalanan; saya akan membaca sumber kondisi dan prediksi server saat Anda bertanya.',
    ),
  );

  static String? checkScopeGuardrail(String message) {
    final lower = message.trim().toLowerCase();
    const refusal =
        'Maaf, saya adalah asisten perjalanan dan lingkungan **SUPRA** khusus wilayah Jabodetabek. '
        'Saya hanya dapat membantu menjawab pertanyaan seputar:\n'
        '• **Kondisi Cuaca & Curah Hujan** (potensi hujan/genangan di koridor perjalanan)\n'
        '• **Kualitas Udara (AQI & PM2.5)** serta rekomendasi pelindung kesehatan (masker KN95/N95)\n'
        '• **Kondisi Lalu Lintas & Rekomendasi Rute/Moda Transportasi** (Mobil, Motor, KRL/MRT/LRT/TransJakarta, Jalan Kaki)\n\n'
        'Silakan tanyakan kondisi rute, cuaca, atau kualitas udara perjalanan Anda di Jabodetabek!';

    const outOfScopeKeywords = [
      'python',
      'javascript',
      'typescript',
      'rust',
      'java',
      'c++',
      'golang',
      'html',
      'css',
      'sql',
      'coding',
      'kode program',
      'buatkan kode',
      'write code',
      'algoritma',
      'function',
      'script',
      'resep',
      'masak',
      'nasi goreng',
      'kue',
      'recipe',
      'cook',
      'kuliner',
      'presiden',
      'politik',
      'pemilu',
      'partai',
      'menteri',
      'dpr',
      'president',
      'politics',
      'puisi',
      'cerpen',
      'dongeng',
      'pantun',
      'poem',
      'story',
      'novel',
      'joke',
      'lelucon',
      'tebak-tebakan',
      'lucu',
      'humor',
      'crypto',
      'bitcoin',
      'saham',
      'forex',
      'investasi',
      'pinjol',
      'chord',
      'lirik',
      'lyrics',
      'lagu',
      'musik',
      'sinopsis',
      'film',
      'movie',
      'anime',
      'game',
      'hitung',
      'matematika',
      'integral',
      'turunan',
      'faktorial',
      'persamaan',
      'perkalian',
      'pembagian',
      'sejarah',
      'history',
      'biologi',
      'fisika',
      'kimia',
      'astronomi',
      'planet',
      'galaksi',
      'ibu kota',
      'capital of',
      'penemu',
      'who invented',
      'terjemahkan',
      'translate',
      'ignore previous',
      'abaikan instruksi',
      'lupakan instruksi',
      'jailbreak',
      'act as',
      'berpura-pura',
      'system prompt',
      'bypass',
      'roleplay',
      'sebagai dokter',
      'sebagai chef',
    ];
    if (outOfScopeKeywords.any((k) => lower.contains(k))) {
      return refusal;
    }

    const greetings = [
      'halo',
      'hai',
      'hi',
      'hello',
      'pagi',
      'siang',
      'sore',
      'malam',
      'apa kabar',
      'terima kasih',
      'makasih',
      'thanks',
      'thank you',
      'bantu',
      'help',
      'siapa kamu',
      'apa itu supra',
    ];
    final isGreeting = greetings.any(
      (g) =>
          lower == g ||
          lower.startsWith('$g ') ||
          lower.startsWith('$g,') ||
          lower.startsWith('$g!'),
    );

    const inScopeKeywords = [
      'rute',
      'route',
      'jalan',
      'macet',
      'traffic',
      'lalu lintas',
      'lalin',
      'cuaca',
      'weather',
      'hujan',
      'rain',
      'gerimis',
      'banjir',
      'flood',
      'genangan',
      'mendung',
      'cerah',
      'panas',
      'aqi',
      'pm2.5',
      'pm25',
      'polusi',
      'udara',
      'asap',
      'air quality',
      'kualitas udara',
      'masker',
      'mask',
      'kn95',
      'n95',
      'komuter',
      'commute',
      'perjalanan',
      'trip',
      'berangkat',
      'pulang',
      'krl',
      'mrt',
      'lrt',
      'transjakarta',
      'tj',
      'bus',
      'angkot',
      'ojol',
      'motor',
      'motorcycle',
      'mobil',
      'car',
      'jalan kaki',
      'walk',
      'sepeda',
      'kendaraan',
      'jakarta',
      'bogor',
      'depok',
      'tangerang',
      'bekasi',
      'jabodetabek',
      'cibinong',
      'bsd',
      'bintaro',
      'serpong',
      'cikarang',
      'karawaci',
      'margonda',
      'fatmawati',
      'cawang',
      'manggarai',
      'tanah abang',
      'dukuh atas',
      'bundaran hi',
      'senayan',
      'blok m',
      'kuningan',
      'sudirman',
      'thamrin',
      'monas',
      'kemang',
      'kelapa gading',
      'pik',
      'grogol',
      'pluit',
      'tebet',
      'jatinegara',
      'pasar minggu',
      'kalibata',
      'cipete',
      'suhu',
      'temp',
      'angin',
      'wind',
      'kelembapan',
      'humidity',
      'supra',
      'kondisi',
      'condition',
      'prediksi',
      'forecast',
      'ml',
      'alert',
      'notifikasi',
      'berita',
      'news',
      'bahaya',
      'hazard',
      'risiko',
      'risk',
      'aman',
      'safe',
      'rekomendasi',
      'saran',
      'kesehatan',
      'health',
      'paru',
      'asma',
      'ispa',
      'paparan',
      'exposure',
      'stasiun',
      'halte',
      'koridor',
      'tol',
      'ganjil genap',
      'gage',
      'payung',
      'jas hujan',
    ];
    final hasInScope = inScopeKeywords.any((k) => lower.contains(k));
    if (!hasInScope && !isGreeting) {
      return refusal;
    }
    return null;
  }

  void bindUser(String? userId) {
    if (_userId == userId) return;
    _userId = userId;
    _generation++;
    _isLoading = false;
    _messages.clear();
    _selectedRoute = null;
    _selectedPoint = null;
    _locationName = null;
    _welcome();
    // Remove the old client-side credential; never migrate it into requests.
    SharedPreferences.getInstance()
        .then((p) => p.remove('supra_gemini_api_key'))
        .catchError((_) => false);
    notifyListeners();
  }

  Future<void> sendMessage(
    String text, {
    ChatEnvironmentalContext? envContext,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;
    final generation = _generation;
    final history = _messages
        .where((m) => m.model != 'unavailable' && m.id != 'welcome')
        .toList()
        .reversed
        .take(6)
        .toList()
        .reversed
        .map(
          (m) => <String, dynamic>{
            'role': m.sender == MessageSender.user ? 'user' : 'model',
            'content': m.text,
          },
        )
        .toList();
    final context =
        envContext?.toJson() ??
        <String, dynamic>{
          if (_selectedRoute != null) 'selected_route': _selectedRoute,
          if (_selectedRoute == null && _activeTrip != null)
            'trip_id': _activeTrip!.id,
          if (_selectedPoint != null) 'point': _selectedPoint,
          if (_locationName != null) 'current_location': _locationName,
        };
    _messages.add(
      ChatMessage(
        id: 'user_${DateTime.now().microsecondsSinceEpoch}',
        sender: MessageSender.user,
        text: trimmed,
        timestamp: DateTime.now(),
      ),
    );
    final id = 'reply_${DateTime.now().microsecondsSinceEpoch}';
    _messages.add(
      ChatMessage(
        id: id,
        sender: MessageSender.assistant,
        text: '',
        timestamp: DateTime.now(),
        isStreaming: true,
        statusText: 'Menghubungi asisten...',
      ),
    );
    _isLoading = true;
    notifyListeners();

    if (send == null && !MapConfig.isTestEnvironment) {
      final scopeRefusal = checkScopeGuardrail(trimmed);
      if (scopeRefusal != null) {
        final index = _messages.indexWhere((m) => m.id == id);
        if (index >= 0) {
          _messages[index] = ChatMessage(
            id: id,
            sender: MessageSender.assistant,
            text: scopeRefusal,
            timestamp: DateTime.now(),
            model: 'supra-guardrail',
            isError: false,
          );
        }
        _isLoading = false;
        notifyListeners();
        return;
      }
    }

    var reply =
        'Asisten tidak tersedia. Periksa koneksi atau konfigurasi server. '
        'Tidak ada data kondisi terkini yang disubstitusi.';
    var model = 'unavailable';
    try {
      final response =
          await (send?.call(trimmed, history, context) ??
                  SupraService.instance.sendAgentChat(
                    message: trimmed,
                    history: history,
                    context: context,
                  ))
              .timeout(const Duration(seconds: 40));
      final result = response['reply'];
      if (response['simulated'] == true ||
          result is! String ||
          result.trim().isEmpty) {
        throw StateError('Jawaban asisten tidak tersedia');
      }
      reply = result;
      model = response['model'] as String? ?? 'server';
    } catch (_) {
      // Keep transport/provider failures explicit; never impersonate a Gemini reply.
    } finally {
      if (generation == _generation) {
        final index = _messages.indexWhere((m) => m.id == id);
        if (index >= 0) {
          _messages[index] = ChatMessage(
            id: id,
            sender: MessageSender.assistant,
            text: reply,
            timestamp: DateTime.now(),
            model: model,
            isError: model == 'unavailable',
          );
        }
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> clearHistory() async {
    _generation++;
    _isLoading = false;
    _messages.clear();
    _welcome();
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    clearHistory();
  }
}
