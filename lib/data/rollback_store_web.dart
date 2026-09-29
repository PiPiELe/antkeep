import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class RollbackStore {
  RollbackStore._();
  static final instance = RollbackStore._();
  static const _key = 'antkeep:restore-rollback';

  Future<void> save(Uint8List bytes) async {
    web.window.localStorage.setItem(_key, base64Encode(bytes));
  }

  Future<Uint8List?> read() async {
    final encoded = web.window.localStorage.getItem(_key);
    return encoded == null ? null : Uint8List.fromList(base64Decode(encoded));
  }

  Future<bool> exists() async => web.window.localStorage.getItem(_key) != null;
}
