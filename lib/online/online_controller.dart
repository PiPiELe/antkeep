import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import 'content.dart';
import 'online_api.dart';
import 'online_store.dart';

class OnlineUser {
  OnlineUser.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      username = json['username'] as String;
  final String id, username;
}

class CheckinSummary {
  CheckinSummary.fromJson(Map<String, dynamic> json)
    : date = json['date'] as String,
      checkedInToday = json['checkedInToday'] as bool,
      consecutiveDays = json['consecutiveDays'] as int,
      totalDays = json['totalDays'] as int;
  final String date;
  final bool checkedInToday;
  final int consecutiveDays, totalDays;
}

class OnlineController extends ChangeNotifier {
  OnlineController({required this.api, required this.store});
  final OnlineApi api;
  final OnlineStore store;
  bool enabled = false, busy = false, refreshing = false;
  OnlineUser? user;
  CheckinSummary? checkin;
  String? error, contentNotice;
  String? _token;
  bool get hasSession => _token != null;
  PublicContent _cached = PublicContent.bundled;
  PublicContent get content => enabled ? _cached : PublicContent.bundled;
  AppAnnouncement? pendingAnnouncement;
  int _generation = 0;

  Future<void> setEnabled(bool value) async {
    if (enabled == value) return;
    enabled = value;
    final generation = ++_generation;
    api.setEnabled(value);
    busy = value;
    refreshing = false;
    user = null;
    checkin = null;
    pendingAnnouncement = null;
    error = null;
    notifyListeners();
    if (!value) {
      _token = null;
      return;
    }
    await _loadContent(generation);
    if (_current(generation)) {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _loadContent(int generation) async {
    try {
      final cached = await store.readContent();
      if (!_current(generation)) return;
      if (cached != null) _cached = PublicContent.decode(cached);
    } catch (_) {
      /* Invalid cached data never replaces bundled content. */
    }
    if (_current(generation)) {
      notifyListeners();
      await refreshContent();
    }
  }

  bool _current(int generation) => enabled && generation == _generation;

  Future<void> refreshContent() async {
    if (!enabled || refreshing) return;
    final generation = _generation;
    refreshing = true;
    contentNotice = null;
    notifyListeners();
    try {
      final raw = await api.request('/api/public/content');
      final candidate = PublicContent.decode(raw);
      if (!_current(generation)) return;
      if (candidate.version < _cached.version) {
        throw const FormatException('内容版本回退');
      }
      // Persist validated snapshots only; existing husbandry data is never touched.
      await store.writeContent(raw);
      if (!_current(generation)) return;
      _cached = candidate;
      contentNotice = '已更新至资料版本 ${candidate.version}';
      final announcement = candidate.announcement;
      String? seenAnnouncement;
      try {
        seenAnnouncement = await store.readSeenAnnouncement();
      } catch (_) {
        // Do not repeat a notice when its local read state is unavailable.
        seenAnnouncement = announcement?.id;
      }
      if (!_current(generation)) return;
      pendingAnnouncement =
          announcement != null && seenAnnouncement != announcement.id
          ? announcement
          : null;
    } catch (_) {
      if (_current(generation)) {
        contentNotice = _cached.version == 0
            ? '暂时无法更新，正在使用内置资料。'
            : '暂时无法更新，正在使用已缓存资料。';
      }
    } finally {
      if (_current(generation)) {
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> acknowledgeAnnouncement(String id) async {
    if (pendingAnnouncement?.id != id) return;
    pendingAnnouncement = null;
    notifyListeners();
    await store.writeSeenAnnouncement(id);
  }

  Future<void> login(
    String username,
    String password, {
    bool register = false,
  }) async {
    if (!enabled || busy) return;
    final generation = _generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final credentials = {'username': username, 'password': password};
      if (register) {
        await api.request(
          '/api/app/auth/register',
          method: 'POST',
          body: credentials,
        );
        if (!_current(generation)) return;
      }
      final payload = jsonDecode(
        await api.request(
          '/api/app/auth/login',
          method: 'POST',
          body: credentials,
        ),
      ) as Map<String, dynamic>;
      if (!_current(generation)) return;
      final token = payload['token'] as String;
      final nextUser = OnlineUser.fromJson(
        payload['user'] as Map<String, dynamic>,
      );
      _token = token;
      user = nextUser;
      checkin = null;
      await _summary(generation);
    } catch (e) {
      if (_current(generation)) await _failure(e);
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    if (!enabled || busy) return;
    final token = _token;
    final generation = ++_generation;
    api.cancel();
    refreshing = false;
    busy = true;
    user = null;
    checkin = null;
    _token = null;
    error = null;
    notifyListeners();
    try {
      if (_current(generation) && token != null) {
        try {
          await api.request(
            '/api/app/auth/logout',
            method: 'POST',
            token: token,
          );
        } catch (_) {
          if (_current(generation)) error = '已在本机退出；服务器会话未确认撤销，将按原有效期失效。';
        }
      }
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshCheckin({bool submit = false}) async {
    if (!enabled || busy || user == null) return;
    final generation = _generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _summary(generation, submit: submit);
    } catch (e) {
      if (_current(generation)) await _failure(e);
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>> inventoryPushStatus() =>
      _authenticatedRequest('/api/app/inventory-pushes/status');

  Future<Map<String, dynamic>> pushInventory(List<InventoryItem> items) {
    if (items.isEmpty || items.length > 200) {
      throw const ApiFailure('请选择 1–200 条物品数据。');
    }
    return _authenticatedRequest(
      '/api/app/inventory-pushes',
      body: {'items': items.map((item) => item.toMap()).toList()},
    );
  }

  Future<List<Map<String, dynamic>>> competitions() async {
    return (await _competitionRequest('/api/app/competitions') as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> competition(String id) async =>
      await _competitionRequest('/api/app/competitions/$id')
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> competitionDisclaimer() async =>
      await _competitionRequest('/api/app/competitions/disclaimer')
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> proposeCompetition(
    Map<String, dynamic> proposal,
  ) async => await _competitionRequest(
    '/api/app/competitions/proposals',
    body: proposal,
  ) as Map<String, dynamic>;

  Future<Map<String, dynamic>> enterCompetition(
    String id,
    Map<String, dynamic> snapshot,
  ) async => await _competitionRequest(
    '/api/app/competitions/$id/entries',
    body: snapshot,
  ) as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateCompetition(
    String entryId,
    Map<String, dynamic> snapshot,
  ) async => await _competitionRequest(
    '/api/app/competition-entries/$entryId/updates',
    body: snapshot,
  ) as Map<String, dynamic>;

  Future<Object> _competitionRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final sessionUser = user;
    final token = _token;
    if (!enabled || sessionUser == null || token == null) {
      throw const ApiFailure('请切换在线版并登录后使用。');
    }
    final generation = _generation;
    try {
      final raw = await api.request(
        path,
        method: body == null ? 'GET' : 'POST',
        token: token,
        body: body,
      );
      if (!_current(generation) || user?.id != sessionUser.id) {
        throw const ApiFailure('在线状态已改变，请重新登录后查看比赛。');
      }
      return jsonDecode(raw) as Object;
    } catch (error) {
      if (_current(generation) && error is ApiFailure && error.status == 401) {
        await _failure(error);
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _authenticatedRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async =>
      jsonDecode(await _authenticatedRaw(path, body: body))
          as Map<String, dynamic>;

  Future<String> _authenticatedRaw(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!enabled || user == null || _token == null) {
      throw const ApiFailure('请切换在线版并登录后使用。');
    }
    if (busy) throw const ApiFailure('正在处理请求，请稍后再试。');
    final generation = _generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final raw = await api.request(
        path,
        method: body == null ? 'GET' : 'POST',
        token: _token,
        body: body,
      );
      if (!_current(generation)) {
        throw const ApiFailure('在线状态已改变，请重新登录后查询推送结果。');
      }
      return raw;
    } catch (e) {
      if (_current(generation)) await _failure(e);
      rethrow;
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _summary(int generation, {bool submit = false}) async {
    final raw = await api.request(
      submit ? '/api/app/check-ins' : '/api/app/check-ins/summary',
      method: submit ? 'POST' : 'GET',
      token: _token,
    );
    if (_current(generation)) {
      checkin = CheckinSummary.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    }
  }

  Future<void> _failure(Object e) async {
    if (e is ApiFailure && e.status == 401) {
      user = null;
      checkin = null;
      _token = null;
    }
    error = e is ApiFailure ? e.message : '在线状态读取或保存失败，请重试。';
  }

  @override
  void dispose() {
    ++_generation;
    api.setEnabled(false);
    super.dispose();
  }
}
