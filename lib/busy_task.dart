import 'package:flutter/material.dart';

Future<T> runBusyTask<T>(
  BuildContext context,
  Future<T> Function() action, {
  required String message,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  navigator.push(route);
  try {
    return await action();
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
}
