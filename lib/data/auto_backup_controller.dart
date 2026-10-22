import 'package:flutter/foundation.dart';

import '../app_preferences.dart';
import 'auto_backup_model.dart';

class AutoBackupController extends ChangeNotifier {
  AutoBackupController(this.settings, this.storage, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final AppSettingsStore settings;
  final AutoBackupStorage storage;
  final DateTime Function() now;
  bool loaded = false;
  bool enabled = false;
  bool decided = false;
  bool busy = false;
  DateTime? lastSuccess;
  String? error;
  Future<void>? _loading;

  bool get needsConsent => loaded && storage.supported && !decided;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final values = await settings.readSettings();
      decided = values['auto_backup_consent_v1'] == 'true';
      enabled = decided && values['auto_backup_enabled'] == 'true';
      lastSuccess = DateTime.tryParse(values['auto_backup_last_success'] ?? '');
      error = values['auto_backup_error'];
      if (error?.isEmpty == true) error = null;
      loaded = true;
      notifyListeners();
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (busy) return;
    await settings.writeSettings({
      'auto_backup_consent_v1': 'true',
      'auto_backup_enabled': value.toString(),
    });
    decided = true;
    enabled = value;
    notifyListeners();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> run({bool force = false}) async {
    if (!loaded || !enabled || !storage.supported || busy) return;
    final at = now();
    if (!force && lastSuccess != null && _sameDay(lastSuccess!, at)) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await storage.create(at);
      // Update in-memory only after the ZIP was published successfully.
      lastSuccess = at;
      await settings.writeSettings({
        'auto_backup_last_success': at.toIso8601String(),
        'auto_backup_error': '',
      });
    } catch (failure) {
      error = failure is FormatException
          ? '自动备份未完成：${failure.message}。已有备份仍保留。'
          : '本次自动备份未完成，请检查存储空间，或稍后重试。已有备份仍保留。';
      try {
        await settings.writeSettings({'auto_backup_error': error!});
      } catch (_) {
        /* Keep the in-memory failure visible. */
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<T> withBackup<T>(Future<T> Function() action) async {
    if (busy) throw StateError('正在处理备份，请稍后重试。');
    busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
