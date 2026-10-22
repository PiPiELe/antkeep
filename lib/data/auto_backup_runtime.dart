import 'app_database.dart';
import 'auto_backup_controller.dart';
import 'auto_backup_store.dart';

final autoBackupController = AutoBackupController(
  AppDatabase.instance,
  createAutoBackupStorage(),
);
