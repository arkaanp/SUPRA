import 'package:flutter/material.dart';

import 'package:supra_mobile_ui/models/notification_preference.dart';
import 'package:supra_mobile_ui/services/supra_api_service.dart';
import 'package:supra_mobile_ui/theme/app_theme.dart';

/// Settings: profile + notification preferences (ERD entity
/// NOTIFICATION_PREFERENCE) that drive Agent 2 alert rules.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late NotificationPreference _prefs;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefs = SupraService.instance.preferences;
  }

  Future<void> _logout() async {
    try {
      await SupraService.instance.logout();
      // The persistent root auth gate displays sign-in on session changes.
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not sign out: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SupraService.instance.currentUser;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Settings',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 24),
        // Profile.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profile',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: SupraTheme.brand.withValues(alpha: 0.15),
                      child: Text(
                        user?.initials ?? '?',
                        style: const TextStyle(
                          color: SupraTheme.brand,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.fullName ?? 'User',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Saved locations are not supported by the backend yet.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Notification preferences.
        const Text(
          'Alert preferences (automatic alerts coming soon)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Unhealthy AQI alerts'),
          subtitle: const Text('Notify when AQI reaches unhealthy levels'),
          value: _prefs.alertUnhealthyAqi,
          onChanged: _saving ? null : (v) => _update(alertUnhealthyAqi: v),
        ),
        SwitchListTile(
          title: const Text('Heavy rain alerts'),
          subtitle: const Text(
            'Notify when rain probability is high on your route',
          ),
          value: _prefs.alertHeavyRain,
          onChanged: _saving ? null : (v) => _update(alertHeavyRain: v),
        ),
        SwitchListTile(
          title: const Text('Severe traffic alerts'),
          subtitle: const Text('Notify when traffic density hits heavy levels'),
          value: _prefs.alertSevereTraffic,
          onChanged: _saving ? null : (v) => _update(alertSevereTraffic: v),
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: _logout,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade50,
            foregroundColor: Colors.red,
          ),
          child: const Text('Sign out'),
        ),
      ],
    );
  }

  Future<void> _update({
    bool? alertUnhealthyAqi,
    bool? alertHeavyRain,
    bool? alertSevereTraffic,
  }) async {
    final next = _prefs.copyWith(
      alertUnhealthyAqi: alertUnhealthyAqi,
      alertHeavyRain: alertHeavyRain,
      alertSevereTraffic: alertSevereTraffic,
    );
    setState(() => _saving = true);
    try {
      await SupraService.instance.updatePreferences(next);
      if (mounted) setState(() => _prefs = SupraService.instance.preferences);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
