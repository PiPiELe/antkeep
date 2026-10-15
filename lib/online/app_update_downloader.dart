import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app_update.dart';

class AppUpdateDownloadException implements Exception {
  const AppUpdateDownloadException(this.message);
  final String message;
}

class AppUpdateDownloader {
  AppUpdateDownloader({
    http.Client Function()? clientFactory,
    Future<Directory> Function()? cacheDirectory,
    Future<void> Function(String)? installApk,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _cacheDirectory = cacheDirectory ?? getTemporaryDirectory,
       _installApk = installApk ?? _openInstaller;

  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _cacheDirectory;
  final Future<void> Function(String) _installApk;

  static Future<void> _openInstaller(String filePath) async {
    await const MethodChannel('com.pipiele.antkeep/app_update')
        .invokeMethod<void>('installApk', {'path': filePath});
  }

  Future<void> downloadAndInstall(
    AppUpdatePolicy policy,
    void Function(int received, int total) onProgress,
  ) async {
    final apk = policy.apk;
    if (apk?.sha256 == null) {
      throw const AppUpdateDownloadException('当前更新没有可校验的安装包。');
    }
    final directory = Directory(
      path.join((await _cacheDirectory()).path, 'antkeep_updates'),
    );
    await directory.create(recursive: true);
    final target = File(path.join(directory.path, '${apk!.sha256}.apk'));
    if (await target.exists()) {
      if (await _matches(target, apk)) {
        onProgress(apk.sizeBytes, apk.sizeBytes);
        await _installVerifiedApk(target.path);
        return;
      }
      await target.delete();
    }

    final client = _clientFactory();
    final temporary = File(path.join(directory.path, '${apk.sha256}.part'));
    try {
      final request = http.Request('GET', policy.downloadUrl)
        ..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const AppUpdateDownloadException('安装包下载失败，请稍后重试。');
      }
      if (response.contentLength != null &&
          response.contentLength != apk.sizeBytes) {
        throw const AppUpdateDownloadException('安装包大小与发布信息不一致，请稍后重试。');
      }
      final digest = _DigestCollector();
      final hasher = sha256.startChunkedConversion(digest);
      var received = 0;
      final output = temporary.openWrite();
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          received += chunk.length;
          if (received > apk.sizeBytes) {
            throw const AppUpdateDownloadException('安装包超过发布大小，下载已停止。');
          }
          hasher.add(chunk);
          output.add(chunk);
          onProgress(received, apk.sizeBytes);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      hasher.close();
      if (received != apk.sizeBytes || digest.value?.toString() != apk.sha256) {
        throw const AppUpdateDownloadException('安装包校验失败，请重新下载。');
      }
      await temporary.rename(target.path);
      await _installVerifiedApk(target.path);
    } on AppUpdateDownloadException {
      rethrow;
    } catch (_) {
      throw const AppUpdateDownloadException('下载失败，请检查网络和存储空间后重试。');
    } finally {
      client.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _installVerifiedApk(String filePath) async {
    try {
      await _installApk(filePath);
    } on PlatformException catch (error) {
      if (error.code == 'install_permission') {
        throw const AppUpdateDownloadException('请在系统设置允许蚁记安装应用，返回后点“立即更新”。');
      }
      throw const AppUpdateDownloadException('无法打开系统安装器，请稍后重试。');
    }
  }

  Future<bool> _matches(File file, AppUpdateApk apk) async {
    if (await file.length() != apk.sizeBytes) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == apk.sha256;
  }
}

class _DigestCollector implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
