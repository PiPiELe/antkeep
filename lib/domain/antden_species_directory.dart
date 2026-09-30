import 'dart:convert';

import 'package:flutter/services.dart';

/// Read-only public species index imported from AntDen.
///
/// It deliberately contains only identity, category, and the public detail
/// URL. Detailed text and images remain on the source site and are requested
/// only after the keeper opens a non-bundled species.
class AntDenSpeciesReference {
  const AntDenSpeciesReference({
    required this.name,
    required this.scientificName,
    required this.displayName,
    required this.category,
    required this.sourceUrl,
  });

  final String name;
  final String scientificName;
  final String displayName;
  final String category;
  final Uri sourceUrl;

  bool matches(String query) {
    final keyword = query.trim().toLowerCase();
    return keyword.isEmpty ||
        [
          name,
          scientificName,
          displayName,
          category,
        ].any((value) => value.toLowerCase().contains(keyword));
  }
}

class AntDenSpeciesDirectory {
  AntDenSpeciesDirectory._();

  static const _assetPath = 'docs/data/antden-species-import.json';
  static const _maxEntries = 1000;
  static final Future<List<AntDenSpeciesReference>> _cached = _load();

  static Future<List<AntDenSpeciesReference>> load() => _cached;

  static Future<List<AntDenSpeciesReference>> _load() async {
    final raw = jsonDecode(await rootBundle.loadString(_assetPath));
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('无效的物种目录');
    }
    final accepted = raw['accepted'];
    if (accepted is! List<dynamic> || accepted.length > _maxEntries) {
      throw const FormatException('无效的物种目录条目');
    }
    final result = <AntDenSpeciesReference>[];
    final urls = <Uri>{};
    for (final value in accepted) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('无效的物种目录条目');
      }
      final sourceUrl = Uri.tryParse(_text(value['sourceUrl'], 200));
      if (sourceUrl == null ||
          sourceUrl.scheme != 'https' ||
          sourceUrl.host != 'antden.net' ||
          sourceUrl.userInfo.isNotEmpty ||
          sourceUrl.hasPort ||
          sourceUrl.query.isNotEmpty ||
          sourceUrl.fragment.isNotEmpty ||
          !RegExp(r'^/antShow/[1-9][0-9]*$').hasMatch(sourceUrl.path) ||
          !urls.add(sourceUrl)) {
        throw const FormatException('无效的物种资料地址');
      }
      result.add(
        AntDenSpeciesReference(
          name: _text(value['name'], 120),
          scientificName: _text(value['scientificName'], 160),
          displayName: _text(value['displayName'], 160),
          category: _text(value['category'], 80),
          sourceUrl: sourceUrl,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  static String _text(dynamic value, int maxLength) {
    if (value is! String || value.trim().isEmpty || value.length > maxLength) {
      throw const FormatException('无效的物种目录字段');
    }
    return value;
  }
}
