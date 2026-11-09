import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supra_mobile_ui/services/authenticated_client.dart';

void main() {
  test('Uses the current token for buffered and streamed requests', () async {
    var token = 'first-token';
    final seen = <String>[];
    final client = AuthenticatedClient(
      baseUrl: Uri.parse('http://localhost:3000'),
      accessToken: () async => token,
      inner: MockClient((request) async {
        seen.add(request.headers['Authorization']!);
        expect(request.followRedirects, isFalse);
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    await client.post(Uri.parse('http://localhost:3000/api/users'));
    token = 'refreshed-token';
    final request = http.Request(
      'GET',
      Uri.parse('http://localhost:3000/api/trips'),
    );
    await (await client.send(request)).stream.drain<void>();
    expect(seen, ['Bearer first-token', 'Bearer refreshed-token']);
  });

  test('Stalled session refresh fails before sending a write, and retry can recover', () async {
    var sent = 0;
    var refreshing = true;
    final pending = Completer<String>();
    final client = AuthenticatedClient(
      baseUrl: Uri.parse('http://localhost:3000'),
      tokenTimeout: const Duration(milliseconds: 10),
      accessToken: () =>
          refreshing ? pending.future : Future.value('new-token'),
      inner: MockClient((request) async {
        sent++;
        expect(request.headers['Authorization'], 'Bearer new-token');
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.post(Uri.parse('http://localhost:3000/api/trips')),
      throwsA(isA<SessionRefreshException>()),
    );
    pending.complete('late-token');
    await Future<void>.delayed(Duration.zero);
    expect(sent, 0); // Late auth completion must not create a trip.
    refreshing = false;
    await client.post(Uri.parse('http://localhost:3000/api/trips'));
    expect(sent, 1);
  });

  test('Refuses unauthenticated requests and other origins', () async {
    var sent = false;
    final client = AuthenticatedClient(
      baseUrl: Uri.parse('http://localhost:3000'),
      accessToken: () async => throw StateError('Signed out'),
      inner: MockClient((_) async {
        sent = true;
        return http.Response('', 200);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.get(Uri.parse('http://localhost:3000/api/users')),
      throwsStateError,
    );
    await expectLater(
      client.get(Uri.parse('https://attacker.example/api')),
      throwsStateError,
    );
    expect(sent, isFalse);
  });
}
