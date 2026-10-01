import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update.dart';
import 'online_api.dart';

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    required this.api,
    required this.currentVersion,
    required this.supportsUpdates,
    Future<bool> Function(Uri)? openUrl,
  }) : _openUrl =
           openUrl ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  final OnlineApi api;
  final Future<String> Function() currentVersion;
  final bool Function() supportsUpdates;
  final Future<bool> Function(Uri) _openUrl;
  bool online = false, checking = false;
  String? error;
  AppUpdatePolicy? policy;
  AppUpdateAvailability availability = AppUpdateAvailability.none;
  bool _optionalPromptShown = false;
  int _generation = 0;

  Future<bool> setOnline(bool value) async {
    final generation = ++_generation;
    online = value;
    api.cancel();
    // Update checks are anonymous and available in both editions.
    api.setEnabled(true);
    checking = false;
    error = null;
    policy = null;
    availability = AppUpdateAvailability.none;
    await check();
    return _current(generation) &&
        availability == AppUpdateAvailability.required;
  }

  bool _current(int generation) => generation == _generation;

  Future<void> check({bool manual = false}) async {
    if (checking) return;
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
      final raw = await api.request('/api/public/app-update/android');
      final candidate = AppUpdatePolicy.decode(raw);
      final installed = AppVersion.parse(await currentVersion());
      if (!_current(generation)) return;
      policy = candidate;
      availability =
          online &&
              candidate.minimumVersion != null &&
              installed.compareTo(candidate.minimumVersion!) < 0
          ? AppUpdateAvailability.required
          : installed.compareTo(candidate.latestVersion) < 0
          ? AppUpdateAvailability.optional
          : AppUpdateAvailability.none;
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
