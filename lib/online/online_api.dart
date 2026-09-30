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
}
