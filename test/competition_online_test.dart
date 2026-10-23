import 'dart:async';
import 'dart:convert';

import 'package:antkeep/online/online_api.dart';
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

  for (final photo in [false, true]) {
    for (final nextUser in ['alice', 'bob']) {
      for (final oldStatus in [200, 401]) {
        test(
          'late ${photo ? 'photo' : 'competition'} $oldStatus preserves $nextUser new session',
          () async {
            final held = Completer<http.Response>();
            final started = Completer<void>();
            var logins = 0;
            final online = controller(MemoryOnlineStore(), (request) async {
              switch (request.url.path) {
                case '/api/public/content':
                  return response(snapshot(), 200);
                case '/api/app/auth/login':
                  final username =
                      jsonDecode(request.body)['username'] as String;
                  return response(
                    jsonEncode({
                      'token': 'session-${++logins}',
                      'user': user(username),
                    }),
                    200,
                  );
                case '/api/app/check-ins/summary':
                  return response(jsonEncode(summary(0)), 200);
                case '/api/app/competitions/held':
                case '/api/app/competition-updates/held/photo':
                  expect(request.headers['Authorization'], 'Bearer session-1');
                  started.complete();
                  return held.future;
                case '/api/app/competitions/expired':
                  return response('{"message":"expired"}', 401);
              }
              return response('{}', 404);
            });
            addTearDown(online.dispose);
            await online.setEnabled(true);
            await online.login('alice', 'password');
            final Future<Object> previous = photo
                ? online.competitionPhoto('held')
                : online.competition('held');
            await started.future;
            // Another expired request clears A, then a new login establishes
            // either B or a refreshed token for A before this response arrives.
            await expectLater(
              online.competition('expired'),
              throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
            );
            expect(online.hasSession, isFalse);
            await online.login(nextUser, 'password');
            expect(online.sessionToken, 'session-2');
            final rejected = expectLater(previous, throwsA(isA<ApiFailure>()));
            held.complete(
              oldStatus == 401
                  ? response('{"message":"obsolete expired session"}', 401)
                  : photo
                  ? http.Response.bytes([0x89, 0x50, 0x4e, 0x47], 200)
                  : response('{"id":"held","entries":[]}', 200),
            );
            await rejected;
            expect(online.user?.id, nextUser);
            expect(online.sessionToken, 'session-2');
            expect(online.checkin?.totalDays, 0);
            expect(online.error, isNull);
          },
        );
      }
    }
  }

  test('current photo 401 still invalidates the matching session', () async {
    final online = controller(MemoryOnlineStore(), (request) async {
      switch (request.url.path) {
        case '/api/public/content':
          return response(snapshot(), 200);
        case '/api/app/auth/login':
          return response(
            jsonEncode({'token': 'current', 'user': user('alice')}),
            200,
          );
        case '/api/app/check-ins/summary':
          return response(jsonEncode(summary(0)), 200);
        case '/api/app/competition-updates/expired/photo':
          return response('{}', 401);
      }
      return response('{}', 404);
    });
    addTearDown(online.dispose);
    await online.setEnabled(true);
    await online.login('alice', 'password');
    await expectLater(
      online.competitionPhoto('expired'),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
    );
    expect(online.hasSession, isFalse);
    expect(online.user, isNull);
    expect(online.checkin, isNull);
    expect(online.error, isNotNull);
  });
}
