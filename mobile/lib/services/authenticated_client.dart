import 'dart:async';

import 'package:http/http.dart' as http;

class SessionRefreshException implements Exception {
  @override
  String toString() =>
      'Your session could not be refreshed. Check your connection and sign in again.';
}

/// Retrieves the current token for each request, including SSE connections.
/// Restricted to the configured backend so tokens cannot leak to other hosts.
class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient({
    required this.baseUrl,
    required this.accessToken,
    http.Client? inner,
    this.tokenTimeout = const Duration(seconds: 6),
  }) : _inner = inner ?? http.Client();

  final Uri baseUrl;
  final Future<String> Function() accessToken;
  final http.Client _inner;
  final Duration tokenTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != baseUrl.origin) {
      throw StateError('Refusing to send credentials to another origin.');
    }
    final String token;
    try {
      token = await accessToken().timeout(tokenTimeout);
    } on TimeoutException {
      throw SessionRefreshException();
    }
    request.headers['Authorization'] = 'Bearer $token';
    request.followRedirects = false;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
