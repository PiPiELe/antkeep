import 'package:shared_preferences/shared_preferences.dart';

abstract class OnlineStore {
  Future<String?> readContent();
  Future<void> writeContent(String content);
  Future<String?> readSeenAnnouncement();
  Future<void> writeSeenAnnouncement(String id);
}

/// Separate from AppDatabase, local media and the husbandry ZIP backup.
class PlatformOnlineStore implements OnlineStore {
  PlatformOnlineStore(this.origin);

  final String origin;

  late final _preferences = SharedPreferencesAsync();
  String get _contentKey => 'antkeep_public_content_v1:$origin';
  String get _announcementKey => 'antkeep_seen_announcement_v1:$origin';

  @override
  Future<String?> readContent() => _preferences.getString(_contentKey);
  @override
  Future<void> writeContent(String content) =>
      _preferences.setString(_contentKey, content);

  @override
  Future<String?> readSeenAnnouncement() =>
      _preferences.getString(_announcementKey);
  @override
  Future<void> writeSeenAnnouncement(String id) =>
      _preferences.setString(_announcementKey, id);
}
