import 'dart:io';

import 'package:antkeep/online/app_update.dart';
import 'package:antkeep/online/app_update_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory cache;
  setUp(
    () async =>
        cache = await Directory.systemTemp.createTemp('antkeep-update-test-'),
  );
  tearDown(() async => cache.delete(recursive: true));

  AppUpdatePolicy policy(List<int> bytes, {int? size, String? digest}) =>
      AppUpdatePolicy(
        version: 1,
        latestVersion: const AppVersion(1, 1, 0),
        minimumVersion: null,
        downloadUrl: Uri.parse('https://downloads.example.test/update.apk'),
        releaseNotes: '更新',
        apk: AppUpdateApk(
          filename: 'AntKeep.apk',
          sizeBytes: size ?? bytes.length,
          sha256: digest ?? sha256.convert(bytes).toString(),
        ),
      );

  test('verified APK downloads to private cache and opens installer', () async {
    final bytes = List<int>.generate(4096, (index) => index % 256);
    var requests = 0;
    final installed = <String>[];
    final progress = <int>[];
    final downloader = AppUpdateDownloader(
      clientFactory: () => MockClient((_) async {
        requests++;
        return http.Response.bytes(bytes, 200);
      }),
      cacheDirectory: () async => cache,
      installApk: (file) async => installed.add(file),
    );
    await downloader.downloadAndInstall(
      policy(bytes),
      (received, _) => progress.add(received),
    );
    expect(progress.last, bytes.length);
    expect(await File(installed.single).readAsBytes(), bytes);
    await downloader.downloadAndInstall(policy(bytes), (_, _) {});
    expect(requests, 1);
    expect(installed, hasLength(2));
  });

  test('wrong digest or truncated body never opens installer', () async {
    final bytes = List<int>.filled(32, 7);
    var installed = false;
    final downloader = AppUpdateDownloader(
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes(bytes, 200)),
      cacheDirectory: () async => cache,
      installApk: (_) async => installed = true,
    );
    await expectLater(
      downloader.downloadAndInstall(policy(bytes, digest: '0' * 64), (_, _) {}),
      throwsA(isA<AppUpdateDownloadException>()),
    );
    await expectLater(
      downloader.downloadAndInstall(policy(bytes, size: 64), (_, _) {}),
      throwsA(isA<AppUpdateDownloadException>()),
    );
    expect(installed, isFalse);
    expect(
      await Directory('${cache.path}/antkeep_updates').list().toList(),
      isEmpty,
    );
  });

  test('cached APK preserves install permission guidance on retry', () async {
    final bytes = List<int>.filled(32, 7);
    var requests = 0;
    final downloader = AppUpdateDownloader(
      clientFactory: () => MockClient((_) async {
        requests++;
        return http.Response.bytes(bytes, 200);
      }),
      cacheDirectory: () async => cache,
      installApk: (_) async =>
          throw PlatformException(code: 'install_permission'),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
        downloader.downloadAndInstall(policy(bytes), (_, _) {}),
        throwsA(
          isA<AppUpdateDownloadException>().having(
            (error) => error.message,
            'message',
            contains('系统设置'),
          ),
        ),
      );
    }
    expect(requests, 1);
  });
}
