import 'package:flutter/material.dart';

import '../services/supra_api_service.dart';
import '../widgets/current_conditions_panel.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final service = SupraService.instance;
    return RefreshIndicator(
      onRefresh: () async {
        try {
          await service.loadAccount();
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$error')));
          }
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Welcome, ${service.currentUser?.fullName ?? 'rider'}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const CurrentConditionsPanel(),
          const SizedBox(height: 16),
          Text('${service.trips.length} saved trips'),
          Text(
            '${service.notifications.where((n) => !n.isRead).length} unread alerts (latest 100)',
          ),
          const SizedBox(height: 16),
          const Text(
            'Recent trips',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (service.trips.isEmpty)
            const ListTile(title: Text('No saved trips yet.')),
          for (final trip in service.trips.take(5))
            ListTile(
              title: Text(trip.name),
              subtitle: Text('${trip.startLocation} → ${trip.destination}'),
            ),
        ],
      ),
    );
  }
}
