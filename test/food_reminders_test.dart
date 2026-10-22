import 'package:antkeep/data/local_notification_service.dart';
import 'package:antkeep/domain/care_task.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pending = <int, Map<String, Object?>>{};
  final calls = <MethodCall>[];
  final now = DateTime.now();
  final colonies = [
    Colony(id: 'c', name: '小黑', createdAt: now, updatedAt: now),
  ];
  CareTask task(String id, int hours) => CareTask(
    id: id,
    colonyId: 'c',
    type: CareTaskType.protein,
    intervalDays: 3,
    nextDueOn: DateTime(now.year, now.month, now.day + 3),
    lastFedAt: now,
    removalHours: hours,
    removalDueAt: now.add(Duration(hours: hours)),
  );
  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (_) async => 'Asia/Shanghai',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        calls.add(call);
        if (call.method == 'initialize') return true;
        if (call.method == 'pendingNotificationRequests') {
          return pending.values.toList();
        }
        if (call.method == 'zonedSchedule') {
          final data = Map<String, Object?>.from(call.arguments as Map);
          pending[data['id'] as int] = {
            'id': data['id'],
            'title': data['title'],
            'body': data['body'],
            'payload': data['payload'],
          };
        }
        if (call.method == 'cancel') {
          pending.remove((call.arguments as Map)['id']);
        }
        return null;
      },
    );
  });
  setUp(() {
    pending.clear();
    calls.clear();
  });
  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('food alarms reconcile without duplicating, cancelling daily reminders or requesting permissions', () async {
    pending[1001] = {'id': 1001, 'title': '每日', 'body': '每日', 'payload': null};
    final service = LocalNotificationService.instance;
    await service.syncFoodReminders([task('p', 8), task('s', 24)], colonies);
    expect(pending.length, 3);
    expect(calls.where((c) => c.method == 'zonedSchedule').length, 2);
    await service.syncFoodReminders([task('p', 8), task('s', 24)], colonies);
    expect(calls.where((c) => c.method == 'zonedSchedule').length, 2);
    await service.syncFoodReminders([task('s', 24)], colonies);
    expect(pending.length, 2);
    expect(pending[1001], isNotNull);
    await service.syncFoodReminders([], colonies);
    expect(pending.keys, [1001]);
    expect(
      calls.where((c) => c.method.toLowerCase().contains('permission')),
      isEmpty,
    );
  });

  test('changed deadline replaces old alarm and archived/deleted colonies cancel food alarms', () async {
    final service = LocalNotificationService.instance;
    await service.syncFoodReminders([task('p', 8)], colonies);
    final firstPayload = pending.values.single['payload'];
    await service.syncFoodReminders([task('p', 12)], colonies);
    expect(pending.length, 1);
    expect(pending.values.single['payload'], isNot(firstPayload));
    await service.syncFoodReminders(
      [task('p', 12)],
      [
        Colony.fromMap({...colonies.single.toMap(), 'archived': 1}),
      ],
    );
    expect(pending, isEmpty);
    await service.syncFoodReminders([task('p', 12)], []);
    expect(pending, isEmpty);
  });

  test('overdue reminders are not replayed and nearest 50 future reminders are scheduled', () async {
    final service = LocalNotificationService.instance;
    final past = CareTask.fromMap({
      ...task('past', 1).toMap(),
      'last_fed_at': now.subtract(const Duration(days: 2)).toIso8601String(),
      'removal_due_at': now.subtract(const Duration(days: 1)).toIso8601String(),
    });
    await service.syncFoodReminders([
      past,
      for (var i = 60; i > 0; i--) task('p$i', i),
    ], colonies);
    expect(pending.length, 50);
    expect(
      pending.values.any((v) => (v['payload'] as String).contains(':past:')),
      isFalse,
    );
    expect(
      pending.values.any((v) => (v['payload'] as String).contains(':p60:')),
      isFalse,
    );
    expect(
      pending.values.any((v) => (v['payload'] as String).contains(':p1:')),
      isTrue,
    );
  });
}
