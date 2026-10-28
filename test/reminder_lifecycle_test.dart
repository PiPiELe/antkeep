import 'package:antkeep/data/local_notification_service.dart';
import 'package:antkeep/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('returning to the app reconciles an enabled daily reminder', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final calls = <MethodCall>[];
    var timezone = 'Asia/Shanghai';
    final messenger = tester.binding.defaultBinaryMessenger;
    const timezoneChannel = MethodChannel('flutter_timezone');
    const notificationChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    messenger.setMockMethodCallHandler(timezoneChannel, (_) async => timezone);
    messenger.setMockMethodCallHandler(notificationChannel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'canScheduleExactNotifications') return true;
      return null;
    });
    final wasEnabled = themeController.careRemindersEnabled;
    final previousMinute = themeController.careReminderMinuteOfDay;
    addTearDown(() {
      themeController.careRemindersEnabled = wasEnabled;
      themeController.careReminderMinuteOfDay = previousMinute;
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(timezoneChannel, null);
      messenger.setMockMethodCallHandler(notificationChannel, null);
    });
    themeController.careRemindersEnabled = true;
    themeController.careReminderMinuteOfDay = 450;
    await LocalNotificationService.instance.scheduleDailyCareReminder(450);
    await tester.pumpWidget(const AntKeepApp());
    await tester.pumpAndSettle();
    calls.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    timezone = 'America/New_York';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final schedule = calls.singleWhere(
      (call) => call.method == 'zonedSchedule',
    );
    expect(schedule.arguments['timeZoneName'], 'America/New_York');
    expect(calls.any((c) => c.method.contains('request')), isFalse);

    calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);

    themeController.careRemindersEnabled = false;
    timezone = 'Asia/Tokyo';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
