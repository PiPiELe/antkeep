import 'dart:convert';

class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.revision]);
  final int major, minor, patch;
  final String? revision;

  factory AppVersion.parse(String value) {
    final match = RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\.([0-9]+))?$',
    ).firstMatch(value);
    if (match == null) throw const FormatException('版本号必须为三段或四段数字');
    try {
      for (final part in value.split('.')) {
        if (int.parse(part) > 2147483647) {
          throw const FormatException('版本号超出支持范围');
        }
      }
      return AppVersion(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        match.group(4),
      );
    } on FormatException {
      throw const FormatException('版本号超出支持范围');
    }
  }

  // Formal releases have three parts; optimization updates add a revision.
  factory AppVersion.parseInstalled(String value) => AppVersion.parse(value);

  @override
  int compareTo(AppVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (int.parse(revision ?? '0'), int.parse(other.revision ?? '0')),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  String toString() =>
      '$major.$minor.$patch${revision == null ? '' : '.$revision'}';
}

class AppUpdateApk {
  const AppUpdateApk({
    required this.filename,
    required this.sizeBytes,
    this.sha256,
  });

  final String filename;
  final int sizeBytes;
  final String? sha256;

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
        sizeBytes <= 0 ||
        sizeBytes > 128 * 1024 * 1024) {
      return null;
    }
    final digest = value['sha256'];
    return AppUpdateApk(
      filename: filename,
      sizeBytes: sizeBytes,
      sha256: digest is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digest)
          ? digest.toLowerCase()
          : null,
    );
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
