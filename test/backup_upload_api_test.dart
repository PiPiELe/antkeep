import 'dart:async';
import 'dart:convert';

import 'package:antkeep/online/online_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('streams a bounded private backup with the logged-in token', () async {
    final original = utf8.encode('test-backup-zip');
    final api = OnlineApi(
      baseUrl: 'https://api.example.test',
      clientFactory: () => MockClient((request) async {
        expect(request.url.path, '/api/app/backups');
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer session-token');
        expect(request.followRedirects, isFalse);
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data; boundary='),
        );
        expect(utf8.decode(request.bodyBytes), contains('test-backup-zip'));
        expect(request.bodyBytes.length, lessThan(original.length + 256));
        return http.Response('{"id":"receipt"}', 201);
      }),
    )..setEnabled(true);
    expect(
      await api.uploadBackup(
        Stream<List<int>>.fromIterable([
          original.sublist(0, 4),
          original.sublist(4),
        ]),
        original.length,
        token: 'session-token',
      ),
      '{"id":"receipt"}',
    );
  });

  test('rejects backups larger than the server limit before sending', () async {
    final api = OnlineApi(baseUrl: 'https://api.example.test')
      ..setEnabled(true);
    expect(
      () => api.uploadBackup(
        const Stream<List<int>>.empty(),
        512 * 1024 * 1024 + 1,
        token: 'session-token',
      ),
      throwsA(isA<ApiFailure>()),
    );
  });
}
