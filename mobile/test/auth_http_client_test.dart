import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supra_mobile_ui/services/auth_http_client.dart';

void main() {
  test(
    'Auth deadline aborts stalled transport; a later attempt can succeed',
    () async {
      var stalled = true;
      Future<void>? aborted;
      final client = AuthHttpClient(
        timeout: const Duration(milliseconds: 10),
        inner: MockClient.streaming((request, body) async {
          if (stalled) {
            aborted = (request as http.Abortable).abortTrigger;
            return Completer<http.StreamedResponse>().future;
          }
          return http.StreamedResponse(Stream.value([123, 125]), 200);
        }),
      );
      addTearDown(client.close);
      final url = Uri.parse('https://test.supabase.co/auth/v1/token');
      await expectLater(client.post(url), throwsA(isA<http.ClientException>()));
      await aborted;
      stalled = false;
      expect((await client.post(url)).body, '{}');
    },
  );

  test('Auth deadline includes stalled body reads', () async {
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final client = AuthHttpClient(
      timeout: const Duration(milliseconds: 10),
      inner: MockClient.streaming(
        (_, _) async => http.StreamedResponse(body.stream, 200),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.get(Uri.parse('https://test.supabase.co/auth/v1/token')),
      throwsA(isA<http.ClientException>()),
    );
  });
}
