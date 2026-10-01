import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_controller.dart';
import 'online_api.dart';
import 'online_controller.dart';
import 'online_store.dart';

const onlineBaseUrl = String.fromEnvironment('ANTKEEP_API_BASE_URL');
final onlineController = OnlineController(
  api: OnlineApi(baseUrl: onlineBaseUrl),
  store: PlatformOnlineStore(onlineBaseUrl),
);
final appUpdateController = AppUpdateController(
  api: OnlineApi(baseUrl: onlineBaseUrl),
  currentVersion: () async => (await PackageInfo.fromPlatform()).version,
  supportsUpdates: () => defaultTargetPlatform == TargetPlatform.android,
);

Future<void> setOnlineMode(bool value) async {
  if (!value) {
    await appUpdateController.setOnline(false);
    await onlineController.setEnabled(false);
    return;
  }
  final required = await appUpdateController.setOnline(true);
  if (!appUpdateController.online) return;
  await onlineController.setEnabled(!required);
}
