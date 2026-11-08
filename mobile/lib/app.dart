import 'dart:ui';

import 'package:flutter/material.dart';

import 'services/supra_api_service.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/supra_shell.dart';
import 'theme/app_theme.dart';

/// Enables drag scrolling across touch, stylus, mouse, and trackpad devices.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// Root widget of the Supra mobile app.
///
/// Wires the Supabase-authenticated [SupraService] into navigation. When the
/// user is logged in we show the bottom-nav shell; otherwise we route through
/// login/register. The root remains mounted for session expiry and sign-out.
class SupraApp extends StatelessWidget {
  const SupraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supra',
      debugShowCheckedModeBanner: false,
      theme: SupraTheme.light(),
      scrollBehavior: const AppScrollBehavior(),
      // Listen to auth state changes so the app can switch between the auth
      // flow and the main shell without a navigation package.
      home: ListenableBuilder(
        listenable: SupraService.instance,
        builder: (context, _) {
          final service = SupraService.instance;
          if (!service.isLoggedIn) {
            return const LoginScreen();
          }
          return SupraShell(key: ValueKey(service.currentUser!.id));
        },
      ),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
      },
    );
  }
}
