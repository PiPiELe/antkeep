import 'online_api.dart';
import 'online_controller.dart';
import 'online_store.dart';

const onlineBaseUrl = String.fromEnvironment('ANTKEEP_API_BASE_URL');
final onlineController = OnlineController(
  api: OnlineApi(baseUrl: onlineBaseUrl),
  store: PlatformOnlineStore(onlineBaseUrl),
);
