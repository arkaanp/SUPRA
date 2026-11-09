import 'dart:ui';

import 'package:flutter/material.dart';

import 'config/map_config.dart';
import 'services/supra_api_service.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/supra_shell.dart';
import 'screens/password_recovery_screen.dart';
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
      builder: (context, child) {
        if (child == null || MapConfig.isTestEnvironment) {
          return child ?? const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final maxH = constraints.maxHeight;
            if (!maxW.isFinite || !maxH.isFinite || maxH <= 0) {
              return child;
            }
            // Target 9:16 portrait phone ratio (16:9 phone screen ratio)
            final targetPhoneWidth = maxH * (9.0 / 16.0);
            if (maxW <= targetPhoneWidth + 16) {
              return child;
            }
            final phoneSize = Size(targetPhoneWidth, maxH);
            final mq = MediaQuery.of(context);
            return ColoredBox(
              color: const Color(0xFF0F172A),
              child: Center(
                child: Container(
                  width: targetPhoneWidth,
                  height: maxH,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 28,
                      ),
                    ],
                  ),
                  child: ClipRect(
                    child: MediaQuery(
                      data: mq.copyWith(size: phoneSize),
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      // Listen to auth state changes so the app can switch between the auth
      // flow and the main shell without a navigation package.
      home: ListenableBuilder(
        listenable: SupraService.instance,
        builder: (context, _) {
          final service = SupraService.instance;
          if (service.recoveringPassword) {
            return const PasswordRecoveryScreen(verified: true);
          }
          if (!service.isLoggedIn) {
            return const LoginScreen();
          }
          return SupraShell(key: ValueKey(service.currentUser!.id));
        },
      ),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/recovery': (_) => const PasswordRecoveryScreen(),
      },
    );
  }
}
