class LocalBackupEntry {
  const LocalBackupEntry(this.name, this.createdAt, this.bytes);
  final String name;
  final DateTime createdAt;
  final int bytes;
}

abstract class AutoBackupStorage {
  bool get supported;
  Future<List<LocalBackupEntry>> list();
  Future<void> create(DateTime now);
  Future<bool> export(LocalBackupEntry entry);
  Future<void> restore(LocalBackupEntry entry, {required bool incremental});
}
