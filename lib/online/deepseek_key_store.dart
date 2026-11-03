import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Personal DeepSeek keys stay on the device, outside husbandry data and backups.
abstract class DeepSeekKeyStore {
  Future<String?> read(String userId);
  Future<void> write(String userId, String key);
  Future<void> delete(String userId);
}

class PlatformDeepSeekKeyStore implements DeepSeekKeyStore {
  PlatformDeepSeekKeyStore(this.origin, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final String origin;
  final FlutterSecureStorage _storage;

  String _name(String userId) => 'antkeep_deepseek_key_v1:$origin:$userId';

  @override
  Future<String?> read(String userId) => _storage.read(key: _name(userId));

  @override
  Future<void> write(String userId, String key) =>
      _storage.write(key: _name(userId), value: key);

  @override
  Future<void> delete(String userId) => _storage.delete(key: _name(userId));
}
