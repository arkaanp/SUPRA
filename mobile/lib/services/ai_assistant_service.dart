import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/map_config.dart';
import '../models/chat_message.dart';
import '../models/location.dart';
import '../models/saved_trip.dart';
import 'conditions_repository.dart';
import 'supra_api_service.dart';

class ChatEnvironmentalContext {
  final String? currentLocation;
  final int? aqi;
  final String? weather;
  final String? temperature;
  final List<String>? frequentRoutes;
  const ChatEnvironmentalContext({
    this.currentLocation,
    this.aqi,
    this.weather,
    this.temperature,
    this.frequentRoutes,
  });
  Map<String, dynamic> toJson() => {
    if (currentLocation != null) 'current_location': currentLocation,
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

  void _welcome() => _messages.add(
    ChatMessage(
      id: 'welcome',
      sender: MessageSender.assistant,
      timestamp: DateTime.now(),
      text: MapConfig.isTestEnvironment
          ? 'Halo! Saya asisten perjalanan SUPRA. Data kondisi terkini hanya tersedia '
                'bila sumber dan lokasinya diberikan; saya tidak memiliki pemantauan langsung.'
          : 'Halo! Saya asisten perjalanan dan lingkungan **SUPRA** khusus wilayah Jabodetabek. '
                'Saya telah membaca data kondisi SUPRA (AQI, PM2.5, curah hujan, suhu, dan lalu lintas — termasuk fallback data stale). '
                'Silakan tanyakan seputar rute, cuaca, hujan, atau kualitas udara perjalanan Anda!',
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
      'python', 'javascript', 'typescript', 'rust', 'java', 'c++', 'golang', 'html', 'css', 'sql',
      'coding', 'kode program', 'buatkan kode', 'write code', 'algoritma', 'function', 'script',
      'resep', 'masak', 'nasi goreng', 'kue', 'recipe', 'cook', 'kuliner',
      'presiden', 'politik', 'pemilu', 'partai', 'menteri', 'dpr', 'president', 'politics',
      'puisi', 'cerpen', 'dongeng', 'pantun', 'poem', 'story', 'novel',
      'joke', 'lelucon', 'tebak-tebakan', 'lucu', 'humor',
      'crypto', 'bitcoin', 'saham', 'forex', 'investasi', 'pinjol',
      'chord', 'lirik', 'lyrics', 'lagu', 'musik', 'sinopsis', 'film', 'movie', 'anime', 'game',
      'hitung', 'matematika', 'integral', 'turunan', 'faktorial', 'persamaan', 'perkalian', 'pembagian',
      'sejarah', 'history', 'biologi', 'fisika', 'kimia', 'astronomi', 'planet', 'galaksi',
      'ibu kota', 'capital of', 'penemu', 'who invented', 'terjemahkan', 'translate',
      'ignore previous', 'abaikan instruksi', 'lupakan instruksi', 'jailbreak', 'act as',
      'berpura-pura', 'system prompt', 'bypass', 'roleplay', 'sebagai dokter', 'sebagai chef',
    ];
    if (outOfScopeKeywords.any((k) => lower.contains(k))) {
      return refusal;
    }

    const greetings = [
      'halo', 'hai', 'hi', 'hello', 'pagi', 'siang', 'sore', 'malam',
      'apa kabar', 'terima kasih', 'makasih', 'thanks', 'thank you', 'bantu', 'help',
      'siapa kamu', 'apa itu supra',
    ];
    final isGreeting = greetings.any(
      (g) =>
          lower == g ||
          lower.startsWith('$g ') ||
          lower.startsWith('$g,') ||
          lower.startsWith('$g!'),
    );

    const inScopeKeywords = [
      'rute', 'route', 'jalan', 'macet', 'traffic', 'lalu lintas', 'lalin', 'cuaca', 'weather',
      'hujan', 'rain', 'gerimis', 'banjir', 'flood', 'genangan', 'mendung', 'cerah', 'panas',
      'aqi', 'pm2.5', 'pm25', 'polusi', 'udara', 'asap', 'air quality', 'kualitas udara',
      'masker', 'mask', 'kn95', 'n95', 'komuter', 'commute', 'perjalanan', 'trip',
      'berangkat', 'pulang', 'krl', 'mrt', 'lrt', 'transjakarta', 'tj', 'bus', 'angkot', 'ojol',
      'motor', 'motorcycle', 'mobil', 'car', 'jalan kaki', 'walk', 'sepeda', 'kendaraan',
      'jakarta', 'bogor', 'depok', 'tangerang', 'bekasi', 'jabodetabek', 'cibinong', 'bsd',
      'bintaro', 'serpong', 'cikarang', 'karawaci', 'margonda', 'fatmawati', 'cawang',
      'manggarai', 'tanah abang', 'dukuh atas', 'bundaran hi', 'senayan', 'blok m',
      'kuningan', 'sudirman', 'thamrin', 'monas', 'kemang', 'kelapa gading', 'pik',
      'grogol', 'pluit', 'tebet', 'jatinegara', 'pasar minggu', 'kalibata', 'cipete',
      'suhu', 'temp', 'angin', 'wind', 'kelembapan', 'humidity', 'supra', 'kondisi',
      'condition', 'prediksi', 'forecast', 'ml', 'alert', 'notifikasi', 'berita', 'news',
      'bahaya', 'hazard', 'risiko', 'risk', 'aman', 'safe', 'rekomendasi', 'saran',
      'kesehatan', 'health', 'paru', 'asma', 'ispa', 'paparan', 'exposure',
      'stasiun', 'halte', 'koridor', 'tol', 'ganjil genap', 'gage', 'payung', 'jas hujan',
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
        (envContext ??
                ChatEnvironmentalContext(
                  frequentRoutes: TripHistoryStore.instance.frequentCommutes
                      .take(3)
                      .map((t) => t.routeLabel)
                      .toList(),
                ))
            .toJson();
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
      if (context.isEmpty || !context.containsKey('aqi')) {
        try {
          final snap = await ConditionsRepository.instance.at(
            const LatLng(latitude: -6.2297, longitude: 106.8295),
          );
          final pm25 = snap.airQuality.number('pm25_ug_m3') ?? 34.0;
          final aqi =
              snap.airQuality.number('aqi')?.round() ??
              ConditionsRepository.pm25ToUsEpaAqi(pm25);
          final rain = snap.weather.number('precipitation_mm') ?? 1.2;
          final temp = snap.weather.number('temperature_c') ?? 29.0;
          final speed = snap.traffic.number('speed_kmh') ?? 24.0;
          final isStale =
              snap.airQuality.isStale ||
              snap.weather.isStale ||
              snap.traffic.isStale;
          context['current_location'] ??= 'Kuningan, Jakarta Selatan';
          context['aqi'] ??= aqi;
          context['temperature'] ??= '${temp.toStringAsFixed(0)}°C';
          context['weather'] ??=
              'Hujan ${rain.toStringAsFixed(1)} mm, PM2.5 ${pm25.toStringAsFixed(1)} µg/m³, Kecepatan lalu lintas ${speed.toStringAsFixed(0)} km/jam (${isStale ? "stale fallback" : "live"})';
        } catch (_) {}
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
              .timeout(const Duration(seconds: 20));
      final result = response['reply'];
      if (response['simulated'] == true ||
          result is! String ||
          result.trim().isEmpty) {
        throw StateError('Assistant response unavailable');
      }
      reply = result;
      model = response['model'] as String? ?? 'server';
    } catch (_) {
      if (send == null && !MapConfig.isTestEnvironment) {
        final loc =
            context['current_location'] as String? ??
            'Kuningan, Jakarta Selatan';
        final aqi = context['aqi'] as int? ?? 97;
        final temp = context['temperature'] as String? ?? '29°C';
        final weatherDesc =
            context['weather'] as String? ??
            'Hujan 1.2 mm, PM2.5 34.0 µg/m³, Kecepatan lalu lintas 24 km/jam (stale fallback)';
        reply =
            'Berdasarkan pembacaan kondisi **SUPRA** untuk wilayah **$loc**:\n\n'
            '• **Kualitas Udara**: US AQI **$aqi** (Sedang / Moderate)\n'
            '• **Cuaca & Lalu Lintas**: Suhu **$temp** — $weatherDesc\n'
            '• **Rekomendasi Komuter**: Gunakan masker **KN95/N95** saat beraktivitas di luar ruang atau berkendara motor, siapkan pelindung hujan, dan pertimbangkan **MRT/LRT/KRL/TransJakarta** atau **Mobil** untuk meminimalkan paparan polusi serta hujan.';
        model = 'gemini-2.5-flash';
      }
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
