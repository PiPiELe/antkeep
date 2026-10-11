import 'package:antkeep/data/flight_weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'city selection sends only coordinates for forecast and parses daily hint',
    () async {
      final requested = <Uri>[];
      final service = FlightWeatherService(
        client: MockClient((request) async {
          requested.add(request.url);
          if (request.url.host == 'geocoding-api.open-meteo.com') {
            return http.Response(
              '{"results":[{"name":"北京","latitude":39.9,"longitude":116.4,"country":"中国"}]}',
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            '{"daily":{"time":["2026-10-11"],"temperature_2m_max":[25],"precipitation_probability_max":[50],"wind_speed_10m_max":[12]}}',
            200,
          );
        }),
      );
      addTearDown(service.dispose);
      final place = (await service.search('北京')).single;
      final days = await service.forecast(place);
      expect(days.single.worthWatching, isTrue);
      expect(requested[1].queryParameters['latitude'], '39.9');
      expect(requested[1].queryParameters['longitude'], '116.4');
      expect(requested[1].queryParameters.containsKey('observations'), isFalse);
    },
  );
}
