import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class OnlineApi {
  OnlineApi({required this.baseUrl, http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final String baseUrl;
  final http.Client Function() _clientFactory;
  final Set<http.Client> _active = {};
  bool enabled = false;

  void setEnabled(bool value) {
    enabled = value;
    if (!value) cancel();
  }

  void cancel() {
    for (final client in _active.toList()) {
      client.close();
    }
    _active.clear();
  }

  Future<String> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
  }) async {
    if (!enabled) throw const ApiFailure('当前为离线模式。');
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/') ||
        (base.scheme != 'https' &&
            !(kDebugMode &&
                base.scheme == 'http' &&
                ['localhost', '127.0.0.1', '10.0.2.2'].contains(base.host)))) {
      throw const ApiFailure('在线服务尚未配置；本地功能可正常使用。');
    }
    final client = _clientFactory();
    _active.add(client);
    try {
      final request = http.Request(method, base.resolve(path));
      request.headers['Accept'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      // Disable redirects to prevent forwarding credentials to a different service.
      request.followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 262144) throw const ApiFailure('服务器响应过大。');
      }
      final text = utf8.decode(bytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = '请求失败，请稍后重试。';
        try {
          final payload = jsonDecode(text) as Map<String, dynamic>;
          if (payload['message'] is String) {
            message = payload['message'] as String;
          }
        } catch (_) {
          /* Non-JSON gateway error. */
        }
        throw ApiFailure(message, status: response.statusCode);
      }
      return text;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure('无法连接服务，请检查网络后重试。');
    } finally {
      _active.remove(client);
      client.close();
    }
  }

  Future<Uint8List> requestImage(String path, {required String token}) async {
    if (!enabled) throw const ApiFailure('当前为离线模式。');
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/') ||
        (base.scheme != 'https' &&
            !(kDebugMode &&
                base.scheme == 'http' &&
                ['localhost', '127.0.0.1', '10.0.2.2'].contains(base.host)))) {
      throw const ApiFailure('在线服务尚未配置；本地功能可正常使用。');
    }
    final client = _clientFactory();
    _active.add(client);
    try {
      final request = http.Request('GET', base.resolve(path));
      request.headers['Authorization'] = 'Bearer $token';
      request.followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 262144) throw const ApiFailure('图片超过读取上限。');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiFailure('读取比赛照片失败，请重试。', status: response.statusCode);
      }
      final image = Uint8List.fromList(bytes);
      final jpeg =
          image.length >= 3 &&
          image[0] == 0xff &&
          image[1] == 0xd8 &&
          image[2] == 0xff;
      final png =
          image.length >= 4 &&
          image[0] == 0x89 &&
          image[1] == 0x50 &&
          image[2] == 0x4e &&
          image[3] == 0x47;
      if (!jpeg && !png) throw const ApiFailure('比赛照片格式不受支持。');
      return image;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure('无法读取比赛照片，请检查网络后重试。');
    } finally {
      _active.remove(client);
      client.close();
    }
  }

  Future<String> uploadBackup(
    Stream<List<int>> bytes,
    int length, {
    required String token,
  }) async {
    if (!enabled) throw const ApiFailure('当前为离线模式。');
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/') ||
        (base.scheme != 'https' &&
            !(kDebugMode &&
                base.scheme == 'http' &&
                ['localhost', '127.0.0.1', '10.0.2.2'].contains(base.host)))) {
      throw const ApiFailure('在线服务尚未配置；本地功能可正常使用。');
    }
    if (length <= 0 || length > 512 * 1024 * 1024) {
      throw const ApiFailure('备份超过 512 MB 上传上限。');
    }
    final client = _clientFactory();
    _active.add(client);
    try {
      final request = http.StreamedRequest(
        'POST',
        base.resolve('/api/app/backups'),
      );
      final boundary =
          'antkeep-backup-${DateTime.now().microsecondsSinceEpoch}';
      final prefix = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="antkeep-backup.zip"\r\n'
        'Content-Type: application/zip\r\n\r\n',
      );
      final suffix = utf8.encode('\r\n--$boundary--\r\n');
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Content-Type'] =
          'multipart/form-data; boundary=$boundary';
      request.headers['Accept'] = 'application/json';
      request.contentLength = prefix.length + length + suffix.length;
      request.followRedirects = false;
      final responseFuture = client.send(request);
      request.sink.add(prefix);
      await request.sink.addStream(bytes).timeout(const Duration(minutes: 10));
      request.sink.add(suffix);
      await request.sink.close();
      final response = await responseFuture.timeout(
        const Duration(minutes: 10),
      );
      final result = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        result.addAll(chunk);
        if (result.length > 262144) throw const ApiFailure('服务器响应过大。');
      }
      final body = utf8.decode(result);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = '备份上传失败，请稍后重试。';
        try {
          final payload = jsonDecode(body) as Map<String, dynamic>;
          if (payload['message'] is String) {
            message = payload['message'] as String;
          }
        } catch (_) {
          /* Non-JSON gateway error. */
        }
        throw ApiFailure(message, status: response.statusCode);
      }
      return body;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure('无法上传备份，请检查网络后重试。');
    } finally {
      _active.remove(client);
      client.close();
    }
  }
}
