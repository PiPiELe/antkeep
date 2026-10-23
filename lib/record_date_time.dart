import 'package:flutter/material.dart';

Future<DateTime?> pickRecordDate(
  BuildContext context,
  DateTime current, {
  required bool hasSpecificTime,
}) async {
  final date = await showDatePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime.now(),
    initialDate: current,
  );
  if (date == null) return null;
  return DateTime(
    date.year,
    date.month,
    date.day,
    hasSpecificTime ? current.hour : 0,
    hasSpecificTime ? current.minute : 0,
  );
}

Future<DateTime?> pickRecordTime(
  BuildContext context,
  DateTime current, {
  required bool hasSpecificTime,
}) async {
  final time = await showTimePicker(
    context: context,
    initialTime: hasSpecificTime
        ? TimeOfDay.fromDateTime(current)
        : TimeOfDay.now(),
  );
  if (time == null) return null;
  return DateTime(
    current.year,
    current.month,
    current.day,
    time.hour,
    time.minute,
  );
}
