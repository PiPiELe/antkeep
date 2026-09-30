import 'dart:convert';
import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_service.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/domain/models.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'online_controller_test.dart' as fixtures;

class TestPaths extends PathProviderPlatform {
  TestPaths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real SQLite records and ZIP media survive login, logout, content updates and restore', () async {
    final root = await Directory.systemTemp.createTemp(
      'antkeep-online-backup-',
    );
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = TestPaths(root.path);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = AppDatabase.instance;
    final media = LocalMediaStore.instance;
    try {
      await media.initialize();
      await db.open();
      await media.restoreFiles({
        'sample.jpg': [1, 2, 3, 4],
      });
      final at = DateTime(2026, 9, 29);
      await db.saveColony(
        Colony(
          id: 'local-colony',
          name: '仅本机蚁群',
          createdAt: at,
          updatedAt: at,
          coverPhotoPath: 'sample.jpg',
        ),
      );
      await db.saveRecord(
        CareRecord(
          id: 'local-record',
          colonyId: 'local-colony',
          type: CareRecordType.values.first,
          occurredAt: at,
          createdAt: at,
          note: 'private-note',
          photos: ['sample.jpg'],
        ),
      );
      final before = await db.snapshot();
      final store = fixtures.MemoryOnlineStore();
      final online = fixtures.controller(store, (request) async {
        switch (request.url.path) {
          case '/api/public/content':
            return fixtures.response(fixtures.snapshot(), 200);
          case '/api/app/auth/login':
            return fixtures.response(
              jsonEncode({
                'token': 'secret-online-token',
                'user': fixtures.user('account-one'),
              }),
              200,
            );
          case '/api/app/check-ins/summary':
            return fixtures.response(jsonEncode(fixtures.summary(3)), 200);
          case '/api/app/auth/logout':
            return fixtures.response('{"ok":true}', 200);
          default:
            fail('Unexpected endpoint ${request.url.path}');
        }
      });
      await online.setEnabled(true);
      await online.login('account-one', 'secret-password');
      final backup = BackupService(db, media);
      final bytes = await backup.createBackupBytes();
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.files.map((f) => f.name).toSet(), {
        'manifest.json',
        'media/sample.jpg',
      });
      final manifestText = utf8.decode(zip.find('manifest.json')!.readBytes()!);
      expect(manifestText, isNot(contains('secret-online-token')));
      expect(manifestText, isNot(contains('account-one')));
      expect(manifestText, isNot(contains('sugar-water')));
      expect((jsonDecode(manifestText) as Map)['data'], before);
      expect(await db.snapshot(), before);
      await online.logout();
      await online.setEnabled(false);
      expect(await db.snapshot(), before);
      expect(await media.readImage('sample.jpg'), [1, 2, 3, 4]);
      await backup.restoreBytes(bytes);
      expect(await db.snapshot(), before);
      expect(store.content, isNotNull);
      online.dispose();
    } finally {
      PathProviderPlatform.instance = previous;
      // The singleton database lives only in this test isolate.
      await root.delete(recursive: true);
    }
  });
}
