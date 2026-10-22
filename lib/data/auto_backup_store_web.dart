import 'auto_backup_model.dart';

AutoBackupStorage createAutoBackupStorage() => _UnsupportedStore();

class _UnsupportedStore implements AutoBackupStorage {
  @override
  bool get supported => false;
  @override
  Future<List<LocalBackupEntry>> list() async => [];
  @override
  Future<void> create(DateTime now) async =>
      throw UnsupportedError('请在手机 App 中使用自动备份');
  @override
  Future<bool> export(LocalBackupEntry entry) async => false;
  @override
  Future<void> restore(
    LocalBackupEntry entry, {
    required bool incremental,
  }) async => throw UnsupportedError('请在手机 App 中恢复');
}
