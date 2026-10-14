import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update.dart';
import 'online_api.dart';

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    required this.api,
    required this.currentVersion,
    required this.supportsUpdates,
    this.sessionToken,
    this.onRequiredUpdate,
    Future<bool> Function(Uri)? openUrl,
  }) : _openUrl =
           openUrl ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  final OnlineApi api;
  final Future<String> Function() currentVersion;
  final bool Function() supportsUpdates;
  final String? Function()? sessionToken;
  final Future<void> Function()? onRequiredUpdate;
  final Future<bool> Function(Uri) _openUrl;
  bool online = false, checking = false;
  String? error;
  AppUpdatePolicy? policy;
  AppUpdateAvailability availability = AppUpdateAvailability.none;
  bool _optionalPromptShown = false;
  bool _recheckRequested = false;
  int _generation = 0;

  Future<bool> setOnline(bool value) async {
    final generation = ++_generation;
    online = value;
    api.cancel();
    // Both editions can check updates; online sessions receive their audience rules.
    api.setEnabled(true);
    checking = false;
    _recheckRequested = false;
    error = null;
    policy = null;
    availability = AppUpdateAvailability.none;
    await check();
    return _current(generation) &&
        availability == AppUpdateAvailability.required;
  }

  bool _current(int generation) => generation == _generation;

  Future<void> check({bool manual = false}) async {
    if (checking) {
      _recheckRequested = true;
      return;
    }
    if (!supportsUpdates()) {
      availability = AppUpdateAvailability.none;
      error = manual ? '当前平台暂不支持应用更新检查。' : null;
      notifyListeners();
      return;
    }
    final generation = _generation;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final token = online ? sessionToken?.call() : null;
      final raw = await api.request(
        '/api/public/app-update/android',
        token: token,
      );
      final candidate = AppUpdatePolicy.decode(raw);
      final installed = AppVersion.parseInstalled(await currentVersion());
      if (!_current(generation)) return;
      if (online && token != sessionToken?.call()) {
        _recheckRequested = true;
        return;
      }
      if (policy?.latestVersion.toString() !=
              candidate.latestVersion.toString() ||
          policy?.minimumVersion?.toString() !=
              candidate.minimumVersion?.toString() ||
          policy?.downloadUrl != candidate.downloadUrl) {
        _optionalPromptShown = false;
      }
      policy = candidate;
      availability =
          online &&
              candidate.minimumVersion != null &&
              installed.compareTo(candidate.minimumVersion!) < 0
          ? AppUpdateAvailability.required
          : installed.compareTo(candidate.latestVersion) < 0
          ? AppUpdateAvailability.optional
          : AppUpdateAvailability.none;
      if (availability == AppUpdateAvailability.required) {
        await onRequiredUpdate?.call();
      }
    } on ApiFailure catch (failure) {
      if (_current(generation) && failure.status == 404) {
        policy = null;
        availability = AppUpdateAvailability.none;
      } else if (_current(generation) && manual) {
        error = failure.message;
      }
    } on FormatException {
      if (_current(generation) && manual) {
        error = '更新策略格式无效，已忽略。';
      }
    } catch (_) {
      if (_current(generation) && manual) {
        error = '无法检查更新，请稍后重试。';
      }
    } finally {
      if (_current(generation)) {
        checking = false;
        notifyListeners();
        if (_recheckRequested) {
          _recheckRequested = false;
          unawaited(check());
        }
      }
    }
  }

  bool takeOptionalPrompt() {
    if (availability != AppUpdateAvailability.optional ||
        _optionalPromptShown) {
      return false;
    }
    _optionalPromptShown = true;
    return true;
  }

  Future<bool> openDownload() async {
    final url = policy?.downloadUrl;
    if (url == null) return false;
    try {
      final opened = await _openUrl(url);
      if (!opened) error = '无法打开下载页面，请稍后重试。';
      notifyListeners();
      return opened;
    } catch (_) {
      error = '无法打开下载页面，请稍后重试。';
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    api.setEnabled(false);
    super.dispose();
  }
}
