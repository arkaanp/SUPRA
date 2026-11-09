/// User notification preferences (ERD entity NOTIFICATION_PREFERENCE).
class NotificationPreference {
  factory NotificationPreference.fromJson(Map<String, dynamic> json) =>
      NotificationPreference(
        alertUnhealthyAqi: json['alert_unhealthy_aqi'] as bool,
        alertHeavyRain: json['alert_heavy_rain'] as bool,
        alertSevereTraffic: json['alert_severe_traffic'] as bool,
        alertRelevantNews: json['alert_relevant_news'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'alert_unhealthy_aqi': alertUnhealthyAqi,
    'alert_heavy_rain': alertHeavyRain,
    'alert_severe_traffic': alertSevereTraffic,
    'alert_relevant_news': alertRelevantNews,
  };
  final bool alertUnhealthyAqi;
  final bool alertHeavyRain;
  final bool alertSevereTraffic;
  final bool alertRelevantNews;

  const NotificationPreference({
    this.alertUnhealthyAqi = true,
    this.alertHeavyRain = true,
    this.alertSevereTraffic = true,
    this.alertRelevantNews = true,
  });

  NotificationPreference copyWith({
    bool? alertUnhealthyAqi,
    bool? alertHeavyRain,
    bool? alertSevereTraffic,
    bool? alertRelevantNews,
  }) => NotificationPreference(
    alertUnhealthyAqi: alertUnhealthyAqi ?? this.alertUnhealthyAqi,
    alertHeavyRain: alertHeavyRain ?? this.alertHeavyRain,
    alertSevereTraffic: alertSevereTraffic ?? this.alertSevereTraffic,
    alertRelevantNews: alertRelevantNews ?? this.alertRelevantNews,
  );
}
