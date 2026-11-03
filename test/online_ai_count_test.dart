import 'dart:convert';
import 'dart:typed_data';

import 'package:antkeep/online/online_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends selected image only to authenticated count endpoint', () async {
    final api = OnlineApi(
      baseUrl: 'https://example.com',
      clientFactory: () => MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/app/ai/colony-count');
        expect(request.headers['authorization'], 'Bearer session-token');
        expect(request.headers['x-deepseek-api-key'], 'personal-secret');
        expect(request.headers['content-type'], 'application/octet-stream');
        expect(request.bodyBytes, [0xff, 0xd8, 0xff, 0x01]);
        return http.Response('{"workerCount":5,"uncertain":false}', 200);
      }),
    );
    api.setEnabled(true);
    final result = await api.estimateColonyCount(
      Uint8List.fromList([0xff, 0xd8, 0xff, 0x01]),
      token: 'session-token',
      personalKey: 'personal-secret',
    );
    expect(jsonDecode(result)['workerCount'], 5);
  });

  test('rejects oversize image before any network call', () async {
    final api = OnlineApi(baseUrl: 'https://example.com');
    api.setEnabled(true);
    expect(
      api.estimateColonyCount(Uint8List(5 * 1024 * 1024 + 1), token: 'token'),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('omits personal key header when using the server key', () async {
    final api = OnlineApi(
      baseUrl: 'https://example.com',
      clientFactory: () => MockClient((request) async {
        expect(request.headers.containsKey('x-deepseek-api-key'), false);
        return http.Response('{"workerCount":1,"uncertain":false}', 200);
      }),
    );
    api.setEnabled(true);
    await api.estimateColonyCount(Uint8List.fromList([0xff]), token: 'session');
  });
}
