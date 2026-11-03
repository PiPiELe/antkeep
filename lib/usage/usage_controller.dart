import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../online/online_api.dart';

abstract class UsageStore {
  Future<bool?> readConsent();
  Future<void> writeConsent(bool value);
  Future<String?> readId();
  Future<void> writeId(String value);
  Future<String?> readReportedDate();
  Future<void> writeReportedDate(String value);
}

/// Kept outside the husbandry database and exported ZIP backups.
class PreferencesUsageStore implements UsageStore {
  PreferencesUsageStore(String origin) : _prefix = 'antkeep_usage_v1:$origin';
  final String _prefix;
  late final _preferences = SharedPreferencesAsync();
  @override
  Future<bool?> readConsent() => _preferences.getBool('$_prefix:consent');
  @override
  Future<void> writeConsent(bool value) =>
      _preferences.setBool('$_prefix:consent', value);
  @override
  Future<String?> readId() => _preferences.getString('$_prefix:id');
  @override
  Future<void> writeId(String value) =>
      _preferences.setString('$_prefix:id', value);
  @override
  Future<String?> readReportedDate() => _preferences.getString('$_prefix:date');
  @override
  Future<void> writeReportedDate(String value) =>
      _preferences.setString('$_prefix:date', value);
}

/// A separate, anonymous transport; never reads login state or husbandry data.
class UsageController extends ChangeNotifier {
  UsageController({
    required this.api,
    required this.store,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final OnlineApi api;
  final UsageStore store;
  final DateTime Function() _now;
  bool loaded = false, saving = false;
  bool? consent;
  bool _foreground = false, _sending = false, _disposed = false;
  int _generation = 0;
  String? _reportedDate;
  DateTime? _retryAfter;
  Timer? _timer;
  bool get configured => api.baseUrl.isNotEmpty;
  bool get needsConsent => configured && loaded && consent == null;
  bool get enabled => consent == true;

  static String beijingDate(DateTime time) => time
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .substring(0, 10);

  Future<void> load() async {
    try {
      final savedConsent = await store.readConsent();
      final savedDate = await store.readReportedDate();
      if (_disposed) return;
      consent = savedConsent;
      _reportedDate = savedDate;
      loaded = true;
      api.setEnabled(enabled);
      _schedule();
      notifyListeners();
      unawaited(report());
    } catch (_) {
      // Preferences failures never block the app or grant consent.
    }
  }

  Future<void> setConsent(bool value) async {
    if (saving || _disposed) return;
    saving = true;
    // Revocation cancels the request before waiting for disk persistence.
    if (!value) {
      consent = false;
      _generation++;
      api.setEnabled(false);
      _schedule();
    }
    notifyListeners();
    try {
      await store.writeConsent(value);
      if (_disposed) return;
      consent = value;
      loaded = true;
      _generation++;
      api.setEnabled(value);
      _schedule();
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
    unawaited(report());
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_disposed && _foreground && loaded && enabled && configured) {
      _timer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(report()),
      );
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    _schedule();
    if (!value) {
      _generation++;
      api.cancel();
      return;
    }
    unawaited(report());
  }

  Future<void> report() async {
    final now = _now();
    if (_disposed ||
        !loaded ||
        !enabled ||
        !configured ||
        !_foreground ||
        _sending ||
        _reportedDate == beijingDate(now) ||
        (_retryAfter != null && now.isBefore(_retryAfter!))) {
      return;
    }
    _sending = true;
    final generation = _generation;
    _retryAfter = now.add(const Duration(minutes: 5));
    try {
      var id = await store.readId();
      if (_disposed || !enabled || !_foreground || generation != _generation) {
        return;
      }
      if (id == null) {
        id = const Uuid().v4();
        await store.writeId(id);
      }
      if (_disposed || !enabled || !_foreground || generation != _generation) {
        return;
      }
      final response = await api.request(
        '/api/public/usage',
        method: 'POST',
        body: {'installationId': id},
      );
      if (_disposed || !enabled || generation != _generation) return;
      final date = (jsonDecode(response) as Map<String, dynamic>)['date'];
      if (date is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
        return;
      }
      _reportedDate = date;
      _retryAfter = null;
      await store.writeReportedDate(date);
    } catch (_) {
      // No errors, offline queue or retry loop; retry later while in foreground.
    } finally {
      _sending = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    api.setEnabled(false);
    super.dispose();
  }
}
