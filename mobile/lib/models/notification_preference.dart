/// User notification preferences (ERD entity NOTIFICATION_PREFERENCE).
class NotificationPreference {
  factory NotificationPreference.fromJson(Map<String, dynamic> json) =>
      NotificationPreference(
        alertUnhealthyAqi: json['alert_unhealthy_aqi'] as bool,
        alertHeavyRain: json['alert_heavy_rain'] as bool,
        alertSevereTraffic: json['alert_severe_traffic'] as bool,
      );

  Map<String, dynamic> toJson() => {
    'alert_unhealthy_aqi': alertUnhealthyAqi,
    'alert_heavy_rain': alertHeavyRain,
    'alert_severe_traffic': alertSevereTraffic,
  };
  final bool alertUnhealthyAqi;
  final bool alertHeavyRain;
  final bool alertSevereTraffic;

  const NotificationPreference({
    this.alertUnhealthyAqi = true,
    this.alertHeavyRain = true,
    this.alertSevereTraffic = true,
  });

  NotificationPreference copyWith({
    bool? alertUnhealthyAqi,
    bool? alertHeavyRain,
    bool? alertSevereTraffic,
  }) => NotificationPreference(
    alertUnhealthyAqi: alertUnhealthyAqi ?? this.alertUnhealthyAqi,
    alertHeavyRain: alertHeavyRain ?? this.alertHeavyRain,
    alertSevereTraffic: alertSevereTraffic ?? this.alertSevereTraffic,
  );
}
