import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'online_controller_test.dart'
    show MemoryOnlineStore, controller, response, snapshot, summary, user;

void main() {
  test('competition status reads can overlap and proposals use the signed-in account', () async {
    final holdList = Completer<void>();
    final requests = <http.Request>[];
    final online = controller(MemoryOnlineStore(), (request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/api/public/content':
          return response(snapshot(), 200);
        case '/api/app/auth/login':
          return response(
            jsonEncode({'token': 'session', 'user': user('keeper')}),
            200,
          );
        case '/api/app/check-ins/summary':
          return response(jsonEncode(summary(0)), 200);
        case '/api/app/competitions':
          await holdList.future;
          return response(
            jsonEncode([
              {'id': 'contest-1', 'state': 'ACTIVE'},
            ]),
            200,
          );
        case '/api/app/competitions/contest-1':
          return response(jsonEncode({'id': 'contest-1', 'entries': []}), 200);
        case '/api/app/competitions/disclaimer':
          return response(
            jsonEncode({'id': 'disclaimer-1', 'version': 1, 'content': '比赛声明'}),
            200,
          );
        case '/api/app/competitions/proposals':
          return response(
            jsonEncode({'id': 'contest-2', 'reviewStatus': 'PENDING'}),
            201,
          );
      }
      return response('{}', 404);
    });
    await online.setEnabled(true);
    await online.login('keeper', 'password');
    final listing = online.competitions();
    final detail = online.competition('contest-1');
    holdList.complete();
    expect((await listing).single['id'], 'contest-1');
    expect((await detail)['entries'], isEmpty);
    expect((await online.competitionDisclaimer())['id'], 'disclaimer-1');
    final proposal = await online.proposeCompetition({
      'title': '新后赛',
      'type': 'NEW_QUEEN_GROWTH',
    });
    expect(proposal['reviewStatus'], 'PENDING');
    final submitted = requests.last;
    expect(submitted.method, 'POST');
    expect(submitted.headers['Authorization'], 'Bearer session');
    expect(jsonDecode(submitted.body)['title'], '新后赛');
    online.dispose();
  });
}
