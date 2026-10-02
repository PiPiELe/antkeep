import 'package:antkeep/data/local_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var exactGranted = false;
  var grantOnRequest = false;
  final service = LocalNotificationService.instance;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    calls.clear();
    exactGranted = false;
    grantOnRequest = false;
    messenger.setMockMethodCallHandler(
      timezoneChannel,
      (_) async => 'Asia/Shanghai',
    );
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
}
