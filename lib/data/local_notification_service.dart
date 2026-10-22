import '../domain/care_task.dart';
import '../domain/models.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  LocalNotificationService._();
  static final instance = LocalNotificationService._();

  static const _dailyCareReminderId = 1001;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  var _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final androidGranted = await android?.requestNotificationsPermission();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: false,
      sound: true,
    );
    return androidGranted ?? iosGranted ?? true;
  }

  /// Returns false when Android must fall back to an inexact reminder.
  Future<bool> scheduleDailyCareReminder(
    int minuteOfDay, {
    bool requestExactPermission = false,
  }) async {
    if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) {
      throw ArgumentError.value(minuteOfDay, 'minuteOfDay');
    }
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    var exact =
        android == null ||
        (await android.canScheduleExactNotifications() ?? false);
    if (!exact && requestExactPermission) {
      exact = await android.requestExactAlarmsPermission() ?? false;
    }
    await _plugin.zonedSchedule(
      id: _dailyCareReminderId,
      title: '蚁记养护提醒',
      body: '打开蚁记，看看今天的蚁群和待办吧。',
      scheduledDate: _nextOccurrence(minuteOfDay),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'care_reminders',
          '养护提醒',
          channelDescription: '每天一次的本地养护提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return exact;
  }

  Future<void> cancelDailyCareReminder() async {
    await initialize();
    await _plugin.cancel(id: _dailyCareReminderId);
  }

  /// Leave room below iOS's pending-notification limit for the daily reminder.
  /// Past deadlines stay visible in the task list without replaying notifications.
  Future<void> syncFoodReminders(
    List<CareTask> tasks,
    List<Colony> colonies,
  ) async {
    await initialize();
    final now = DateTime.now();
    final active = {
      for (final c in colonies)
        if (!c.archived) c.id: c,
    };
    final due =
        tasks
            .where(
              (t) =>
                  t.removalHours != null &&
                  t.removalDueAt != null &&
                  active.containsKey(t.colonyId),
            )
            .toList()
          ..sort((a, b) {
            final time = a.removalDueAt!.compareTo(b.removalDueAt!);
            return time == 0 ? a.id.compareTo(b.id) : time;
          });
    final pending = await _plugin.pendingNotificationRequests();
    final managed = pending
        .where((n) => n.payload?.startsWith('food-removal:') == true)
        .toList();
    String payload(CareTask t) =>
        'food-removal:${t.id}:${t.removalDueAt!.toIso8601String()}';
    final candidates = due
        .where(
          (t) =>
              t.removalDueAt!.isAfter(now) ||
              managed.any((n) => n.payload == payload(t)),
        )
        .take(50)
        .toList();
    final wanted = candidates.map(payload).toSet();
    for (final item in managed) {
      if (!wanted.contains(item.payload)) await _plugin.cancel(id: item.id);
    }
    final used = pending.map((n) => n.id).toSet();
    for (final task in candidates) {
      if (managed.any((n) => n.payload == payload(task))) continue;
      var id = 20000;
      while (used.contains(id)) {
        id++;
      }
      used.add(id);
      await _plugin.zonedSchedule(
        id: id,
        title: '${active[task.colonyId]!.name} · ${task.type.label}撤食',
        body: '已到设定的撤食时间，处理后可在养护待办中标记已撤食。',
        payload: payload(task),
        scheduledDate: tz.TZDateTime.from(task.removalDueAt!, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'food_removal',
            '撤食提醒',
            channelDescription: '各类食物独立的本地撤食提醒',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  tz.TZDateTime _nextOccurrence(int minuteOfDay) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
