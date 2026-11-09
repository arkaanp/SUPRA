import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'trip_screen.dart';
import 'chat_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import '../services/supra_api_service.dart';

/// Main shell with bottom navigation. Mirrors the Flutter frontend from the
/// system architecture diagram: Home, Trip planner, Agent 1 chat, Agent 2
/// notifications, Settings.
class SupraShell extends StatefulWidget {
  const SupraShell({super.key});

  @override
  State<SupraShell> createState() => _SupraShellState();
}

class _SupraShellState extends State<SupraShell> {
  int _index = 0;
  bool _loading = true;
  String? _error;
  final GlobalKey<TripScreenState> _tripKey = GlobalKey<TripScreenState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupraService.instance.loadAccount();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Widget> get _pages => [
    HomeScreen(
      onNavigateToTrip: (trip) {
        setState(() => _index = 1);
        if (trip != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tripKey.currentState?.loadAndShowRoute(
              start: trip.startLocation,
              destination: trip.destination,
              startPoint: trip.startPoint,
              destPoint: trip.destPoint,
              mode: trip.transportMode,
            );
          });
        }
      },
      onNavigateToAlerts: () => setState(() => _index = 3),
    ),
    TripScreen(key: _tripKey),
    ChatScreen(),
    NotificationsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_error != null)
                    MaterialBanner(
                      content: const Text(
                        'Account refresh unavailable. Last-known conditions can still be shown as stale.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              await SupraService.instance.logout();
                            } catch (error) {
                              if (mounted) setState(() => _error = '$error');
                            }
                          },
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: IndexedStack(index: _index, children: _pages),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.route_outlined),
            activeIcon: Icon(Icons.route),
            label: 'Trip',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Assistant',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
