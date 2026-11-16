import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:supra_mobile_ui/services/geocoding_service.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Real HTTP lookup distinguishes no match, bad coordinates and provider outage', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = IOClient(_RealHttp().createHttpClient(null));
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    var calls = 0;
    server.listen((request) async {
      calls++;
      expect(request.uri.path, '/search');
      if (request.uri.queryParameters['q'] == 'outage-xyz') {
        request.response.statusCode = 429;
      } else if (request.uri.queryParameters['q'] == 'malformed-xyz') {
        request.response.write(
          '[{"name":"Invalid place","lat":"not-latitude","lon":106.8}]',
        );
      } else {
        request.response.write('[]');
      }
      await request.response.close();
    });
    final service = GeocodingService(
      client: client,
      useNetwork: true,
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    expect(await service.searchPlaces('unknown-xyz', remote: false), isEmpty);
    expect(calls, 0); // Typing does not hit public Nominatim.
    expect(await service.searchPlaces('unknown-xyz'), isEmpty);
    expect(await service.searchPlaces('malformed-xyz'), isEmpty);
    await expectLater(service.searchPlaces('outage-xyz'), throwsStateError);
    expect(calls, 3);
  });
}
