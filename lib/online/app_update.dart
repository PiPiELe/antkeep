import 'dart:convert';

class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);
  final int major, minor, patch;

  factory AppVersion.parse(String value) {
    final match = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
        .firstMatch(value);
    if (match == null) throw const FormatException('版本号必须为三段数字');
    try {
      return AppVersion(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    } on FormatException {
      throw const FormatException('版本号超出支持范围');
    }
  }

  @override
  int compareTo(AppVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  String toString() => '$major.$minor.$patch';
}

class AppUpdateApk {
  const AppUpdateApk({required this.filename, required this.sizeBytes});

  final String filename;
  final int sizeBytes;

  // Older publications may only have a download URL. Invalid optional metadata
  // must not prevent the user from seeing an otherwise valid update.
  static AppUpdateApk? decode(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final filename = value['filename'];
    final sizeBytes = value['sizeBytes'];
    if (filename is! String ||
        filename.trim().isEmpty ||
        filename.length > 255 ||
        sizeBytes is! int ||
        sizeBytes <= 0) {
      return null;
    }
    return AppUpdateApk(filename: filename, sizeBytes: sizeBytes);
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class AppUpdatePolicy {
  const AppUpdatePolicy({
    required this.version,
    required this.latestVersion,
    required this.minimumVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    this.apk,
  });
  final int version;
  final AppVersion latestVersion;
  final AppVersion? minimumVersion;
  final Uri downloadUrl;
  final String releaseNotes;
  final AppUpdateApk? apk;

  factory AppUpdatePolicy.decode(String source) {
    if (utf8.encode(source).length > 16384) {
      throw const FormatException('更新策略过大');
    }
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data['enabled'] != true ||
        data['version'] is! int ||
        (data['version'] as int) < 1) {
      throw const FormatException('更新策略无效');
    }
    final latest = AppVersion.parse(data['latestVersion'] as String);
    final minimum = data['minimumVersion'] == null
        ? null
        : AppVersion.parse(data['minimumVersion'] as String);
    if (minimum != null && minimum.compareTo(latest) > 0) {
      throw const FormatException('最低版本无效');
    }
    final uri = Uri.tryParse(data['downloadUrl'] as String);
    final notes = data['releaseNotes'];
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        notes is! String ||
        notes.trim().isEmpty ||
        notes.length > 4000) {
      throw const FormatException('更新策略字段无效');
    }
    return AppUpdatePolicy(
      version: data['version'] as int,
      latestVersion: latest,
      minimumVersion: minimum,
      downloadUrl: uri,
      releaseNotes: notes,
      apk: AppUpdateApk.decode(data['apk']),
    );
  }
}

enum AppUpdateAvailability { none, optional, required }
