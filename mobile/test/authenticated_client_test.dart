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
