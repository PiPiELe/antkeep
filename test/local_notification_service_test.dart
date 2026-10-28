import 'dart:async';

import 'package:antkeep/data/local_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var exactGranted = false;
  var grantOnRequest = false;
  var timezone = 'Asia/Shanghai';
  var failNextSchedule = false;
  var dailyScheduled = false;
  Completer<void>? scheduleBlock;
  Completer<void>? scheduleStarted;
  final service = LocalNotificationService.instance;

  setUpAll(tz_data.initializeTimeZones);

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    calls.clear();
    exactGranted = false;
    grantOnRequest = false;
    timezone = 'Asia/Shanghai';
    failNextSchedule = false;
    dailyScheduled = false;
    scheduleBlock = null;
    scheduleStarted = null;
    messenger.setMockMethodCallHandler(timezoneChannel, (_) async => timezone);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'requestNotificationsPermission':
          return true;
        case 'canScheduleExactNotifications':
          return exactGranted;
        case 'requestExactAlarmsPermission':
          exactGranted = grantOnRequest;
          return exactGranted;
        case 'zonedSchedule':
          if (failNextSchedule) {
            failNextSchedule = false;
            throw PlatformException(code: 'schedule_failed');
          }
          scheduleStarted?.complete();
          await scheduleBlock?.future;
          dailyScheduled = true;
          return null;
        case 'cancel':
          dailyScheduled = false;
          return null;
        default:
          throw UnsupportedError(call.method);
      }
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
  });

  bool requestedPermission() =>
      calls.any((call) => call.method == 'requestExactAlarmsPermission');

  String scheduledMode() =>
      calls
              .lastWhere((call) => call.method == 'zonedSchedule')
              .arguments['platformSpecifics']['scheduleMode']
          as String;

  test('enabling requests notification and exact alarm access', () async {
    grantOnRequest = true;
    expect(await service.requestPermission(), isTrue);
    expect(
      await service.scheduleDailyCareReminder(
        450,
        requestExactPermission: true,
      ),
      isTrue,
    );
    expect(requestedPermission(), isTrue);
    expect(scheduledMode(), 'exactAllowWhileIdle');
    final methods = calls.map((call) => call.method).toList();
    expect(
      methods.indexOf('requestNotificationsPermission'),
      lessThan(methods.indexOf('requestExactAlarmsPermission')),
    );
  });

  test('denied alarm access still schedules an ordinary reminder', () async {
    expect(
      await service.scheduleDailyCareReminder(
        450,
        requestExactPermission: true,
      ),
      isFalse,
    );
    expect(requestedPermission(), isTrue);
    expect(scheduledMode(), 'inexactAllowWhileIdle');
  });

  test(
    'existing authorization uses precise scheduling without a prompt',
    () async {
      exactGranted = true;
      expect(
        await service.scheduleDailyCareReminder(
          450,
          requestExactPermission: true,
        ),
        isTrue,
      );
      expect(requestedPermission(), isFalse);
      expect(scheduledMode(), 'exactAllowWhileIdle');
    },
  );

  test(
    'startup rechecks revoked permission and falls back without a prompt',
    () async {
      exactGranted = true;
      expect(await service.scheduleDailyCareReminder(450), isTrue);
      exactGranted = false;
      calls.clear();
      expect(await service.scheduleDailyCareReminder(450), isFalse);
      expect(requestedPermission(), isFalse);
      expect(scheduledMode(), 'inexactAllowWhileIdle');
    },
  );

  test('iOS schedules without requesting Android alarm access', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterLocalNotificationsPlatform.instance =
        IOSFlutterLocalNotificationsPlugin();
    expect(
      await service.scheduleDailyCareReminder(
        450,
        requestExactPermission: true,
      ),
      isTrue,
    );
    expect(requestedPermission(), isFalse);
    expect(
      calls.any((call) => call.method == 'canScheduleExactNotifications'),
      isFalse,
    );
    expect(calls.any((call) => call.method == 'zonedSchedule'), isTrue);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'resume updates the $platform daily zone only when it changes',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        FlutterLocalNotificationsPlatform.instance =
            platform == TargetPlatform.iOS
            ? IOSFlutterLocalNotificationsPlugin()
            : AndroidFlutterLocalNotificationsPlugin();
        await service.scheduleDailyCareReminder(450);
        calls.clear();
        timezone = 'America/New_York';

        await service.refreshDailyCareReminder(450);
        final scheduled = calls.singleWhere((c) => c.method == 'zonedSchedule');
        expect(scheduled.arguments['timeZoneName'], 'America/New_York');
        expect(
          DateTime.parse(scheduled.arguments['scheduledDateTime'] as String)
              .hour,
          7,
        );
        expect(
          calls.any((c) => c.method.toLowerCase().contains('request')),
          isFalse,
        );

        calls.clear();
        await service.refreshDailyCareReminder(450);
        expect(calls, isEmpty);
      },
    );
  }

  test('failed timezone rescheduling is retried on the next resume', () async {
    await service.scheduleDailyCareReminder(450);
    timezone = 'America/New_York';
    failNextSchedule = true;
    await expectLater(
      service.refreshDailyCareReminder(450),
      throwsA(isA<PlatformException>()),
    );
    calls.clear();
    await service.refreshDailyCareReminder(450);
    expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(1));
  });

  test('disabling wins over an in-flight timezone refresh', () async {
    await service.scheduleDailyCareReminder(450);
    timezone = 'America/New_York';
    calls.clear();
    scheduleBlock = Completer<void>();
    scheduleStarted = Completer<void>();
    final refresh = service.refreshDailyCareReminder(450);
    await scheduleStarted!.future;
    final cancelled = service.cancelDailyCareReminder();
    // Give cancellation time to finish first if operations are not serialized.
    await Future<void>.delayed(Duration.zero);
    scheduleBlock!.complete();
    await Future.wait([refresh, cancelled]);
    expect(dailyScheduled, isFalse);
    expect(calls.last.method, 'cancel');
  });

  for (final transition in [
    (month: 3, day: 7, elapsedHours: 23),
    (month: 10, day: 31, elapsedHours: 25),
  ]) {
    test(
      'daily wall time survives DST transition in month ${transition.month}',
      () {
        final location = tz.getLocation('America/New_York');
        final today = tz.TZDateTime(
          location,
          2026,
          transition.month,
          transition.day,
          7,
          30,
        );
        final next = LocalNotificationService.nextDailyCareReminderTime(
          450,
          now: tz.TZDateTime(
            location,
            2026,
            transition.month,
            transition.day,
            12,
          ),
        );
        expect(
          next,
          tz.TZDateTime(
            location,
            2026,
            transition.month,
            transition.day + 1,
            7,
            30,
          ),
        );
        expect(
          next.difference(today),
          Duration(hours: transition.elapsedHours),
        );
      },
    );
  }
}
