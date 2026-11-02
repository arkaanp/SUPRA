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
        return 'Low';
      case NotificationSeverity.moderate:
        return 'Moderate';
      case NotificationSeverity.high:
        return 'High';
      case NotificationSeverity.critical:
        return 'Critical';
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
      );
  final String id;
  final String userId;
  final String title;
  final String messageBody;
  final NotificationSeverity severity;
  final DateTime sentAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.messageBody,
    required this.severity,
    required this.sentAt,
    this.isRead = false,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    userId: userId,
    title: title,
    messageBody: messageBody,
    severity: severity,
    sentAt: sentAt,
    isRead: isRead ?? this.isRead,
  );

  String get timeLabel =>
      '${sentAt.hour.toString().padLeft(2, '0')}:${sentAt.minute.toString().padLeft(2, '0')}';
}
