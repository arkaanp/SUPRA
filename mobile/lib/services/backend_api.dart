import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/display_text.dart';

class ApiException implements Exception {
  const ApiException(this.status, this._message);
  final int status;
  final String _message;
  String get message => apiErrorMessage(_message, status);
  @override
  String toString() => message;
}

/// Typed transport for the existing Axum API; the client supplies bearer auth.
class BackendApi {
  BackendApi({
    required this.client,
    required String baseUrl,
    this.requestTimeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(seconds: 30),
  }) : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final http.Client client;
  final String baseUrl;
  final Duration requestTimeout;
  final Duration uploadTimeout;

  Future<http.Response> _send(http.Request request, Duration timeout) async {
    try {
      return await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        504,
        request.method == 'DELETE' &&
                request.url.path == '/api/notifications/read'
            ? 'Server belum mengonfirmasi penghapusan. Perbarui untuk memeriksa hasilnya sebelum mencoba lagi.'
            : request.url.path == '/api/auth/username-login'
            ? 'Waktu tunggu login habis. Coba lagi.'
            : request.url.path == '/api/agent/chat'
            ? 'Asisten belum merespons. Coba lagi.'
            : request.method == 'GET'
            ? 'Server belum merespons. Coba lagi.'
            : 'Server belum mengonfirmasi penyimpanan. Perbarui untuk memeriksa apakah data tersimpan sebelum mencoba lagi.',
      );
    } on http.ClientException {
      throw const ApiException(
        503,
        'Server tidak dapat dihubungi. Periksa koneksi dan coba lagi.',
      );
    }
  }

  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers['Content-Type'] = 'application/json';
    if (data != null) request.body = jsonEncode(data);
    final response = await _send(request, switch (request.url.path) {
      '/api/agent/chat' => const Duration(seconds: 35),
      '/api/forecast/hourly' => const Duration(seconds: 85),
      _ => requestTimeout,
    });
    if (path == '/api/auth/username-login' && response.statusCode == 429) {
      throw const ApiException(
        429,
        'Terlalu banyak percobaan login. Coba lagi nanti.',
      );
    }
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw ApiException(response.statusCode, 'Respons server tidak valid.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        body is Map && body['error'] is String
            ? body['error'] as String
            : 'Permintaan server gagal (HTTP ${response.statusCode}).',
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
    final response = await _send(request, uploadTimeout);
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw ApiException(response.statusCode, 'Respons server tidak valid.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        body is Map && body['error'] is String
            ? body['error'] as String
            : 'Permintaan server gagal (HTTP ${response.statusCode}).',
      );
    }
    return body;
  }
}
