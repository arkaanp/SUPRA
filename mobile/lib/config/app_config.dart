/// Values supplied by --dart-define-from-file=config/local.json.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const apiBaseUrl = String.fromEnvironment(
    'SUPRA_API_URL',
    defaultValue: 'http://localhost:3000',
  );

  static void validate() {
    final url = Uri.tryParse(supabaseUrl);
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        supabasePublishableKey.isEmpty) {
      throw StateError(
        'Supply SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY with '
        '--dart-define-from-file=config/local.json.',
      );
    }
    // Build-time defines are public in a mobile/web binary, never server secrets.
    if (supabasePublishableKey.startsWith('sb_secret_')) {
      throw StateError('Use the Supabase publishable key, not a secret key.');
    }
    final api = Uri.tryParse(apiBaseUrl);
    if (api == null ||
        !{'http', 'https'}.contains(api.scheme) ||
        api.host.isEmpty ||
        api.userInfo.isNotEmpty ||
        api.hasQuery ||
        api.hasFragment) {
      throw StateError('SUPRA_API_URL must be an HTTP(S) backend URL.');
    }
  }
}
