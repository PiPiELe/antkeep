import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_preferences.dart';

class AccountSnapshot {
  AccountSnapshot.fromJson(Map<String, dynamic> json)
    : username = json['user']['username'] as String,
      nickname = json['user']['nickname'] as String,
      serverDate = json['checkIn']['serverDate'] as String,
      checkedInToday = json['checkIn']['checkedInToday'] as bool,
      totalDays = json['checkIn']['totalDays'] as int,
      streakDays = json['checkIn']['streakDays'] as int,
      recentDates = List<String>.from(json['checkIn']['recentDates'] as List);

  final String username;
  final String nickname;
  final String serverDate;
  final bool checkedInToday;
  final int totalDays;
  final int streakDays;
  final List<String> recentDates;
}

/// Sessions stay in memory: passwords and bearer tokens never enter local
/// journal storage, backups, or browser localStorage.
class AccountController extends ChangeNotifier {
  AccountController({
    required this.preferences,
    String baseUrl = const String.fromEnvironment('ANTKEEP_ACCOUNT_BASE_URL'),
    http.Client? client,
  }) : _base = _validatedBase(baseUrl),
       _client = client ?? http.Client() {
    preferences.addListener(_editionChanged);
  }

  final AppPreferences preferences;
  final Uri? _base;
  final http.Client _client;
  String? _token;
  AccountSnapshot? account;
  String? error;
  bool busy = false;
  int _generation = 0;

  bool get configured => _base != null;
  bool get online => preferences.edition == AppEdition.online;
  bool get signedIn => _token != null && account != null;

  Future<void> authenticate({
    required String username,
    required String password,
    String? nickname,
  }) => _run((generation) async {
    final data = await _request(
      'POST',
      nickname == null ? 'login' : 'register',
      body: {
        'username': username.trim(),
        'password': password,
        if (nickname != null) 'nickname': nickname.trim(),
      },
    );
    final snapshot = AccountSnapshot.fromJson(data);
    final token = data['token'] as String;
    if (generation != _generation) return;
    _token = token;
    account = snapshot;
  });

  Future<void> refresh() => _run((generation) async {
    if (!signedIn) return;
    final data = await _request('GET', 'me');
    if (generation == _generation) account = AccountSnapshot.fromJson(data);
  });

  Future<void> checkIn() => _run((generation) async {
    if (!signedIn) return;
    // Always let the server decide the day and whether it is already recorded.
    final data = await _request('POST', 'check-in');
    if (generation == _generation) account = AccountSnapshot.fromJson(data);
  });

  Future<void> updateNickname(String nickname) => _run((generation) async {
    final data = await _request(
      'PATCH',
      'me',
      body: {'nickname': nickname.trim()},
    );
    if (generation == _generation) account = AccountSnapshot.fromJson(data);
  });

  Future<void> logout() => _run((generation) async {
    await _request('POST', 'logout');
    if (generation == _generation) {
      _token = null;
      account = null;
    }
  });

  Future<void> _run(Future<void> Function(int) operation) async {
    if (busy || !online) return;
    if (!configured) {
      error = '账号服务暂未开放，请稍后再试。';
      notifyListeners();
      return;
    }
    final generation = _generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation(generation);
    } on _AccountException catch (failure) {
      if (generation == _generation) {
        error = failure.message;
        if (failure.unauthorized) {
          _token = null;
          account = null;
        }
      }
    } catch (_) {
      if (generation == _generation) error = '连接失败，请检查网络后重试。';
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, _base!.resolve('/api/account/$path'))
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) {
      throw _AccountException(
        signedIn ? '登录已失效，请重新登录。' : '账号或密码不正确。',
        unauthorized: signedIn,
      );
    }
    if (response.statusCode >= 500 ||
        response.statusCode < 200 ||
        response.statusCode >= 300 && response.statusCode < 400) {
      throw const _AccountException('账号服务暂不可用，请稍后重试。');
    }
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw _AccountException(data['message'] as String? ?? '操作未完成，请重试。');
    }
    return data;
  }

  void _editionChanged() {
    if (online) return;
    _generation++;
    _token = null;
    account = null;
    error = null;
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    preferences.removeListener(_editionChanged);
    _client.close();
    super.dispose();
  }

  static Uri? _validatedBase(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    final localDebug =
        kDebugMode &&
        uri.scheme == 'http' &&
        ['localhost', '127.0.0.1', '::1', '10.0.2.2'].contains(uri.host);
    return uri.scheme == 'https' || localDebug ? uri : null;
  }
}

class _AccountException implements Exception {
  const _AccountException(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
}
