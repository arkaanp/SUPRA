import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Typed transport for the existing Axum API; the client supplies bearer auth.
class BackendApi {
  BackendApi({required this.client, required String baseUrl})
    : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final http.Client client;
  final String baseUrl;

  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers['Content-Type'] = 'application/json';
    if (data != null) request.body = jsonEncode(data);
    final response = await (() async => http.Response.fromStream(
      await client.send(request),
    ))().timeout(const Duration(seconds: 15));
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        response.statusCode,
        'The backend returned an invalid response.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        body is Map && body['error'] is String
            ? body['error'] as String
            : 'Backend request failed (HTTP ${response.statusCode}).',
      );
    }
    return body;
  }

  Future<dynamic> uploadBytes(
    String path,
    List<int> bytes, {
    String? fileName,
  }) async {
    final request = http.Request('POST', Uri.parse('$baseUrl$path'));
    request.headers['Content-Type'] = 'application/octet-stream';
    if (fileName != null && fileName.isNotEmpty) {
      request.headers['x-file-name'] = fileName;
    }
    request.bodyBytes = bytes;
    final response = await (() async => http.Response.fromStream(
      await client.send(request),
    ))().timeout(const Duration(seconds: 30));
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        response.statusCode,
        'The backend returned an invalid response.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        body is Map && body['error'] is String
            ? body['error'] as String
            : 'Backend request failed (HTTP ${response.statusCode}).',
      );
    }
    return body;
  }
}
