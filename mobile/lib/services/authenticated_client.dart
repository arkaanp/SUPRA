import 'package:http/http.dart' as http;

/// Retrieves the current token for each request, including SSE connections.
/// Restricted to the configured backend so tokens cannot leak to other hosts.
class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient({
    required this.baseUrl,
    required this.accessToken,
    http.Client? inner,
  }) : _inner = inner ?? http.Client();

  final Uri baseUrl;
  final Future<String> Function() accessToken;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != baseUrl.origin) {
      throw StateError('Refusing to send credentials to another origin.');
    }
    request.headers['Authorization'] = 'Bearer ${await accessToken()}';
    request.followRedirects = false;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
