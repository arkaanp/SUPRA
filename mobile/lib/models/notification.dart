import 'package:flutter/material.dart';

/// Severity of a proactive notification (Agent 2 output).
enum NotificationSeverity { low, moderate, high, critical }

extension NotificationSeverityExtensions on NotificationSeverity {
  Color color() {
    switch (this) {
      case NotificationSeverity.low:
        return const Color(0xFF3B82F6);
      case NotificationSeverity.moderate:
        return const Color(0xFFF59E0B);
      case NotificationSeverity.high:
      case NotificationSeverity.critical:
        return const Color(0xFFEF4444);
    }
  }

  String label() {
    switch (this) {
      case NotificationSeverity.low:
        return 'Rendah';
      case NotificationSeverity.moderate:
        return 'Sedang';
      case NotificationSeverity.high:
        return 'Tinggi';
      case NotificationSeverity.critical:
        return 'Kritis';
    }
  }
}

/// A proactive alert delivered to the user (ERD entity NOTIFICATION).
class AppNotification {
  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String,
        messageBody: json['message_body'] as String,
        severity: switch (json['severity']) {
          'low' => NotificationSeverity.low,
          'medium' => NotificationSeverity.moderate,
          'high' => NotificationSeverity.high,
          'critical' => NotificationSeverity.critical,
          _ => throw const FormatException('Unknown notification severity'),
        },
        sentAt: DateTime.parse(json['sent_at'] as String).toLocal(),
        isRead: json['is_read'] as bool,
        sourceUrl: json['source_url'] as String?,
        rule: json['context'] is Map
            ? (json['context'] as Map)['rule'] as String?
            : null,
        expiresAt: DateTime.tryParse(
          (json['context'] is Map
                      ? (json['context'] as Map)['expires_at']
                      : null)
                  as String? ??
              '',
        ),
      );
  final String id;
  final String userId;
  final String title;
  final String messageBody;
  final NotificationSeverity severity;
  final DateTime sentAt;
  final bool isRead;
  final String? sourceUrl;
  final String? rule;
  final DateTime? expiresAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.messageBody,
    required this.severity,
    required this.sentAt,
    this.isRead = false,
    this.sourceUrl,
    this.rule,
    this.expiresAt,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    userId: userId,
    title: title,
    messageBody: messageBody,
    severity: severity,
    sentAt: sentAt,
    isRead: isRead ?? this.isRead,
    sourceUrl: sourceUrl,
    rule: rule,
    expiresAt: expiresAt,
  );

  String get displayTitle => _localizedAlertText(title);

  String get displayBody {
    final url = sourceUrl?.trim();
    if (url == null || url.isEmpty) return _localizedAlertText(messageBody);
    // Older saved publisher alerts include the same structured URL as a footer.
    var body = messageBody.trimRight();
    for (final label in ['Source', 'Sumber']) {
      final footer = '\n$label: $url';
      if (body.endsWith(footer)) {
        body = body.substring(0, body.length - footer.length);
      }
    }
    return _localizedAlertText(body);
  }

  bool get isNews => sourceUrl?.trim().isNotEmpty == true;
  bool meetsNewsMinimum(String minimum) {
    if (!isNews) return true;
    final rank = const {
      'low': 0,
      'medium': 1,
      'high': 2,
      'critical': 3,
    }[minimum];
    return rank != null && severity.index >= rank;
  }

  String get timeLabel =>
      '${sentAt.hour.toString().padLeft(2, '0')}:${sentAt.minute.toString().padLeft(2, '0')}';
}

// Previously saved app-generated messages remain readable after this update.
// Publisher titles, place names and article content keep their original text.
String _localizedAlertText(String text) {
  const phrases = {
    'Elevated PM2.5 near your trip': 'PM2.5 meningkat di dekat perjalanan Anda',
    'Rain near your trip': 'Hujan di dekat perjalanan Anda',
    'Road disruption near your trip': 'Gangguan jalan di dekat perjalanan Anda',
    'Nearby station PM2.5: ': 'PM2.5 stasiun terdekat: ',
    'This is an instantaneous station sample, not AQI or route-wide exposure. Consider reducing outdoor exposure.': 'Data ini merupakan pengamatan sesaat di stasiun, bukan AQI atau paparan seluruh rute. Pertimbangkan mengurangi paparan luar ruangan.',
    'Precipitation ': 'Curah hujan ',
    ' mm in the provider interval. Carry rain protection; wet surfaces may affect outdoor legs. Source is a model estimate, not a verified flood report.': ' mm sesuai interval penyedia. Bawa pelindung hujan dan waspadai permukaan licin. Sumber merupakan perkiraan model, bukan laporan banjir terverifikasi.',
    'Provider reports a nearby road fragment closed.':
        'Penyedia melaporkan penutupan ruas jalan terdekat.',
    'Nearby road speed is below half its free-flow speed. This is not a route-wide delay prediction.': 'Kecepatan jalan terdekat kurang dari separuh kecepatan saat lancar. Data ini bukan prediksi keterlambatan seluruh rute.',
    'Relevant to your saved trip (': 'Relevan dengan perjalanan tersimpan (',
    'Jabodetabek commuter news': 'Berita perjalanan Jabodetabek',
    'Publisher report near ': 'Berita di sekitar ',
    '(area-level relevance). Check the article for current status.':
        '(relevansi tingkat wilayah). Periksa artikel untuk kondisi terkini.',
    '(area match; check article for current status).':
        '(sesuai wilayah; periksa artikel untuk kondisi terkini).',
    'Published: ': 'Terbit: ',
    'Published ': 'Terbit ',
    'Expires: ': 'Berlaku hingga: ',
    'Expires ': 'Berlaku hingga ',
    'Source: ': 'Sumber: ',
    ' · checked ': ' · diperiksa ',
  };
  for (final entry in phrases.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text;
}
