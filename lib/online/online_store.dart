import 'package:shared_preferences/shared_preferences.dart';

abstract class OnlineStore {
  Future<String?> readContent();
  Future<void> writeContent(String content);
}

/// Separate from AppDatabase, local media and the husbandry ZIP backup.
class PlatformOnlineStore implements OnlineStore {
  PlatformOnlineStore(this.origin);

  final String origin;

  late final _preferences = SharedPreferencesAsync();
  String get _contentKey => 'antkeep_public_content_v1:$origin';

  @override
  Future<String?> readContent() => _preferences.getString(_contentKey);
  @override
  Future<void> writeContent(String content) =>
      _preferences.setString(_contentKey, content);
}
