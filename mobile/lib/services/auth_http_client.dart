import 'dart:async';

import 'package:http/http.dart' as http;

/// Bounds Supabase HTTP calls so a stalled refresh cannot stay pending forever.
/// Auth responses are buffered to include body reads in the same deadline.
class AuthHttpClient extends http.BaseClient {
  AuthHttpClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 5),
  }) : _inner = inner ?? http.Client();
  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abort = Completer<void>();
    final outgoing =
        http.AbortableRequest(
            request.method,
            request.url,
            abortTrigger: abort.future,
          )
          ..headers.addAll(request.headers)
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..persistentConnection = request.persistentConnection;
    try {
      return await (() async {
        outgoing.bodyBytes = await request.finalize().toBytes();
        final response = await http.Response.fromStream(
          await _inner.send(outgoing),
        );
        return http.StreamedResponse(
          Stream.value(response.bodyBytes),
          response.statusCode,
          headers: response.headers,
          reasonPhrase: response.reasonPhrase,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          request: request,
        );
      })().timeout(timeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw http.ClientException(
        'Authentication service timed out. Check your connection.',
        request.url,
      );
    }
  }

  @override
  void close() => _inner.close();
}
