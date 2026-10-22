import 'dart:async';

import 'app_database.dart';
import 'local_notification_service.dart';

/// Serialize reconciliation so an older refresh cannot restore a cancelled alarm.
class FoodReminderCoordinator {
  FoodReminderCoordinator._();
  static final instance = FoodReminderCoordinator._();
  StreamSubscription<void>? _tasks;
  StreamSubscription<void>? _colonies;
  bool _running = false;
  bool _again = false;

  void start() {
    _tasks ??= AppDatabase.instance.careTaskChanges.listen((_) => refresh());
    _colonies ??= AppDatabase.instance.memorialChanges.listen((_) => refresh());
    refresh();
  }

  void stop() {
    _tasks?.cancel();
    _colonies?.cancel();
    _tasks = null;
    _colonies = null;
  }

  Future<void> refresh() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    do {
      _again = false;
      try {
        await LocalNotificationService.instance.syncFoodReminders(
          await AppDatabase.instance.listCareTasks(),
          await AppDatabase.instance.listColonies(),
        );
      } catch (_) {
        // Local timers remain available without a working notification service.
      }
    } while (_again);
    _running = false;
  }
}
