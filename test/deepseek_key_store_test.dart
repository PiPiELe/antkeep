import 'package:antkeep/online/deepseek_key_store.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'isolates keys by service origin and account and deletes only one',
    () async {
      final previous = FlutterSecureStoragePlatform.instance;
      final memory = TestFlutterSecureStoragePlatform({});
      FlutterSecureStoragePlatform.instance = memory;
      try {
        final first = PlatformDeepSeekKeyStore('https://one.example');
        final second = PlatformDeepSeekKeyStore('https://two.example');
        await first.write('alice', 'alice-secret');
        await first.write('bob', 'bob-secret');
        await second.write('alice', 'other-service-secret');
        expect(await first.read('alice'), 'alice-secret');
        expect(await first.read('bob'), 'bob-secret');
        expect(await second.read('alice'), 'other-service-secret');
        await first.delete('alice');
        expect(await first.read('alice'), isNull);
        expect(await first.read('bob'), 'bob-secret');
        expect(await second.read('alice'), 'other-service-secret');
      } finally {
        FlutterSecureStoragePlatform.instance = previous;
      }
    },
  );
}
