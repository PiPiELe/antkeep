import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class OnlineStore {
  Future<String?> readToken();
  Future<void> writeToken(String? token);
  Future<String?> readContent();
  Future<void> writeContent(String content);
}

/// Separate from AppDatabase, local media and the husbandry ZIP backup.
class PlatformOnlineStore implements OnlineStore {
  PlatformOnlineStore(this.origin);
  final String origin;
  String? _webToken;
  final _secure = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  late final _preferences = SharedPreferencesAsync();
  String get _tokenKey => 'antkeep_session_v1:$origin';
  String get _contentKey => 'antkeep_public_content_v1:$origin';
  @override
  Future<String?> readToken() async =>
      kIsWeb ? _webToken : _secure.read(key: _tokenKey);
  @override
  Future<void> writeToken(String? token) async {
    if (kIsWeb) {
      _webToken = token;
      return;
    }
    if (token == null) {
      await _secure.delete(key: _tokenKey);
    } else {
      await _secure.write(key: _tokenKey, value: token);
    }
  }

  @override
  Future<String?> readContent() => _preferences.getString(_contentKey);
  @override
  Future<void> writeContent(String content) =>
      _preferences.setString(_contentKey, content);
}
