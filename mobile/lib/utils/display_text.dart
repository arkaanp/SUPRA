/// Indonesian display labels. Wire values stay unchanged for API compatibility.
String placeKindLabel(String kind) => switch (kind) {
  'home' => 'Rumah',
  'work' => 'Kantor',
  'school' => 'Sekolah',
  'custom' => 'Lainnya',
  _ => kind,
};

String travelModeLabel(String mode) => switch (mode) {
  'car' => 'Mobil',
  'motorcycle' => 'Motor',
  'walk' => 'Jalan kaki',
  'public_transit' => 'Transportasi umum',
  _ => mode,
};

String signalStatusLabel(String status) => switch (status) {
  'available' => 'Tersedia',
  'stale' => 'Data lama',
  'unavailable' => 'Tidak tersedia',
  _ => status,
};

String signalKindLabel(String? kind) => switch (kind) {
  'station_observation' => 'Pengamatan stasiun',
  'provider_forecast' => 'Prakiraan penyedia',
  'provider_live_estimate' => 'Perkiraan terkini penyedia',
  'model_estimate' => 'Perkiraan model',
  'calculated_index' => 'Indeks hasil perhitungan',
  _ => '',
};

String formatWib(DateTime time) {
  final local = time.toUtc().add(const Duration(hours: 7));
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${local.day} ${months[local.month - 1]} ${local.year}, '
      '${local.hour.toString().padLeft(2, '0')}.${local.minute.toString().padLeft(2, '0')} WIB';
}

/// Known service errors are translated without changing their HTTP status/code.
String apiErrorMessage(String message, int status) {
  const messages = {
    'Invalid username or password': 'Username atau password salah.',
    'Invalid login credentials': 'Username atau password salah.',
    'Resource not found': 'Data tidak ditemukan.',
    'Method not allowed': 'Tindakan ini tidak didukung.',
    'Service not ready': 'Layanan belum siap. Coba lagi sebentar.',
    'Resource already exists': 'Data sudah ada.',
    'Internal server error': 'Terjadi kesalahan pada server. Coba lagi.',
    'Too many login attempts. Try again later.':
        'Terlalu banyak percobaan login. Coba lagi nanti.',
    'Request violates a database constraint':
        'Data belum memenuhi ketentuan penyimpanan.',
    'Username is already in use.': 'Username sudah digunakan.',
    'User already registered': 'Username sudah digunakan.',
    'Same password': 'Password baru harus berbeda dari password saat ini.',
    'New password should be different from the old password.':
        'Password baru harus berbeda dari password saat ini.',
    'The forecast worker is unreachable. Coba perbarui.':
        'Layanan prakiraan tidak dapat dihubungi. Coba perbarui.',
    'Open-Meteo has rate-limited forecast inputs. Try again later.':
        'Batas permintaan prakiraan Open-Meteo tercapai. Coba lagi nanti.',
    'Recent hourly weather or air-quality data is incomplete.':
        'Data cuaca atau kualitas udara per jam belum lengkap.',
    'The forecast model needs retraining.':
        'Model prakiraan perlu dilatih ulang.',
    'Open-Meteo inputs and the MET Norway fallback are unavailable.':
        'Data Open-Meteo dan sumber cadangan MET Norway tidak tersedia.',
    'The forecast worker is busy. Coba perbarui.':
        'Layanan prakiraan sedang sibuk. Coba perbarui.',
    'Weather inputs are unavailable from Open-Meteo.':
        'Data cuaca Open-Meteo tidak tersedia.',
    'Air-quality inputs are unavailable from Open-Meteo.':
        'Data kualitas udara Open-Meteo tidak tersedia.',
    'The forecast worker could not generate a forecast.':
        'Layanan belum dapat menghasilkan prakiraan.',
  };
  if (messages.containsKey(message)) return messages[message]!;
  // Messages already produced by the Indonesian client remain readable.
  if (RegExp(
    r'\b(tidak|gagal|belum|kembali|koneksi|terlalu|coba|masukkan|gunakan|harus|sudah|berubah)\b',
    caseSensitive: false,
  ).hasMatch(message)) {
    return message;
  }
  return switch (status) {
    400 || 422 => 'Data yang dikirim tidak valid. Periksa isian Anda.',
    401 => 'Sesi tidak valid. Login kembali.',
    403 => 'Akses ditolak.',
    404 => 'Data tidak ditemukan.',
    409 => 'Data sudah ada atau telah berubah. Coba perbarui.',
    429 => 'Batas permintaan tercapai. Coba lagi nanti.',
    _ => 'Layanan tidak tersedia. Coba lagi.',
  };
}

String displayError(Object error) {
  final text = error.toString();
  for (final prefix in ['Bad state: ', 'Exception: ', 'FormatException: ']) {
    if (text.startsWith(prefix)) return text.substring(prefix.length);
  }
  if (text.startsWith('AuthException') || text.startsWith('AuthApiException')) {
    if (text.contains('Invalid login credentials')) {
      return 'Username atau password salah.';
    }
    return 'Autentikasi gagal. Periksa koneksi dan login kembali.';
  }
  return text;
}
