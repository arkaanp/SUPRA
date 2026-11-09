import 'package:flutter/material.dart';

import 'app.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'services/supra_api_service.dart';
import 'services/auth_http_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    httpClient: AuthHttpClient(),
  );
  SupraService.instance.initializeAuth(Supabase.instance.client);
  runApp(const SupraApp());
}
