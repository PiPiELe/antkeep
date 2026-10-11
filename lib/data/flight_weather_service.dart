import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherPlace {
  const WeatherPlace(this.name, this.latitude, this.longitude, this.region);
  final String name;
  final double latitude;
  final double longitude;
  final String region;

  String get label => region.isEmpty ? name : '$name · $region';
}

class FlightWeatherDay {
  const FlightWeatherDay(
    this.date,
    this.maxTemp,
    this.rainChance,
    this.windMax,
  );
  final DateTime date;
  final double? maxTemp;
  final int? rainChance;
  final double? windMax;

  // A weather reading prompt, not a biological flight prediction.
  bool get worthWatching =>
      maxTemp != null &&
      maxTemp! >= 20 &&
      rainChance != null &&
      rainChance! >= 40 &&
      windMax != null &&
      windMax! <= 20;
}

class FlightWeatherService {
  FlightWeatherService({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;

  Future<List<WeatherPlace>> search(String name) async {
    if (name.trim().length < 2) throw const FormatException('请输入至少两个字的城市名。');
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': name.trim(),
      'count': '8',
      'language': 'zh',
      'format': 'json',
    });
    final data = await _get(uri);
    final results = data['results'];
    if (results == null) return const [];
    if (results is! List) throw const FormatException('城市搜索结果无效。');
    return results.map((item) {
      final row = item as Map<String, dynamic>;
      return WeatherPlace(
        row['name'] as String,
        (row['latitude'] as num).toDouble(),
        (row['longitude'] as num).toDouble(),
        [
          row['admin1'],
          row['country'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
      );
    }).toList();
  }

  Future<List<FlightWeatherDay>> forecast(WeatherPlace place) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': place.latitude.toString(),
      'longitude': place.longitude.toString(),
      'daily':
          'temperature_2m_max,precipitation_probability_max,wind_speed_10m_max',
      'timezone': 'auto',
      'forecast_days': '7',
    });
    final data = await _get(uri);
    final daily = data['daily'];
    if (daily is! Map<String, dynamic>) {
      throw const FormatException('天气预报格式无效。');
    }
    final dates = daily['time'];
    final temps = daily['temperature_2m_max'];
    final rains = daily['precipitation_probability_max'];
    final winds = daily['wind_speed_10m_max'];
    if (dates is! List ||
        temps is! List ||
        rains is! List ||
        winds is! List ||
        dates.length != temps.length ||
        dates.length != rains.length ||
        dates.length != winds.length) {
      throw const FormatException('天气预报数据不完整。');
    }
    return List.generate(
      dates.length,
      (i) => FlightWeatherDay(
        DateTime.parse(dates[i] as String),
        (temps[i] as num?)?.toDouble(),
        (rains[i] as num?)?.round(),
        (winds[i] as num?)?.toDouble(),
      ),
    );
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('天气服务暂不可用（${response.statusCode}）');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic> || body['error'] == true) {
      throw const FormatException('天气服务返回了无效数据。');
    }
    return body;
  }

  void dispose() => _client.close();
}
