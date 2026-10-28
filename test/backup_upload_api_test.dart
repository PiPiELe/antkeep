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
        expect(utf8.decode(request.bodyBytes), contains('application/zip'));
        expect(request.contentLength, request.bodyBytes.length);
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

  test('connection failures finish without reading the backup and allow retry', () async {
    final failedClient = _ConnectionFailureClient();
    var connections = 0;
    var backupRead = false;
    final api = OnlineApi(
      baseUrl: 'https://api.example.test',
      clientFactory: () => connections++ == 0
          ? failedClient
          : MockClient((_) async => http.Response('{"id":"retry"}', 201)),
    )..setEnabled(true);
    final source = StreamController<List<int>>(
      onListen: () => backupRead = true,
    );
    try {
      await expectLater(
        api
            .uploadBackup(source.stream, 3, token: 'session-token')
            .timeout(const Duration(seconds: 2)),
        throwsA(isA<ApiFailure>()),
      );
      expect(backupRead, isFalse);
      expect(failedClient.closed, isTrue);
      expect(
        await api.uploadBackup(
          Stream.value([1, 2, 3]),
          3,
          token: 'session-token',
        ),
        '{"id":"retry"}',
      );
    } finally {
      api.setEnabled(false);
      // No subscriber is attached when connecting fails, so do not await close.
      unawaited(source.close());
    }
  });

  test('backup read errors finish the upload and close the client', () async {
    final client = _BodyReadingClient();
    final api = OnlineApi(
      baseUrl: 'https://api.example.test',
      clientFactory: () => client,
    )..setEnabled(true);
    Stream<List<int>> brokenBackup() async* {
      yield [1, 2];
      throw StateError('backup file is no longer readable');
    }

    await expectLater(
      api
          .uploadBackup(brokenBackup(), 3, token: 'session-token')
          .timeout(const Duration(seconds: 2)),
      throwsA(isA<ApiFailure>()),
    );
    expect(client.closed, isTrue);
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

class _ConnectionFailureClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // IOClient finalizes the request before opening its socket, and may fail
    // before ever subscribing to the finalized body.
    request.finalize();
    throw http.ClientException('connection refused', request.url);
  }

  @override
  void close() => closed = true;
}

class _BodyReadingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 201);
  }

  @override
  void close() => closed = true;
}
