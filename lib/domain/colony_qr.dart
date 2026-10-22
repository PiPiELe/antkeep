/// Versioned local reference. It contains no husbandry data and is never opened
/// as an external URL. Stable colony IDs survive a full backup/restore.
class ColonyQr {
  static final _id = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');

  static String encode(String id) {
    if (!_id.hasMatch(id)) throw const FormatException('蚁群编号无效');
    return 'antkeep://colony/v1/$id';
  }

  static String? decode(String value) {
    if (value.length > 180) return null;
    try {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme != 'antkeep' ||
          uri.host != 'colony' ||
          uri.hasPort ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.pathSegments.length != 2 ||
          uri.pathSegments.first != 'v1') {
        return null;
      }
      final id = uri.pathSegments.last;
      return _id.hasMatch(id) && encode(id) == value ? id : null;
    } on FormatException {
      return null;
    }
  }
}
