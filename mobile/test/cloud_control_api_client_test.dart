import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/services/cloud_control_api_client.dart';

void main() {
  group('CloudControlApiClient', () {
    test(
      'startSession sends the bearer token and returns the sessionId',
      () async {
        final client = MockClient((request) async {
          expect(request.url.path, '/sessions');
          expect(request.headers['Authorization'], 'Bearer tok_1');
          return http.Response(
            jsonEncode({'sessionId': 's1', 'status': 'LIVE'}),
            201,
          );
        });

        final api = CloudControlApiClient(
          client: client,
          baseUrl: 'http://test',
        );
        final sessionId = await api.startSession('tok_1');

        expect(sessionId, 's1');
      },
    );

    test('startSession throws CloudControlApiException with the server message and code on failure', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'AT_CAPACITY',
              'message': 'This worker instance is at capacity',
            },
          }),
          503,
        );
      });

      final api = CloudControlApiClient(client: client, baseUrl: 'http://test');

      await expectLater(
        () => api.startSession('tok_1'),
        throwsA(
          isA<CloudControlApiException>()
              .having(
                (e) => e.message,
                'message',
                'This worker instance is at capacity',
              )
              .having((e) => e.code, 'code', 'AT_CAPACITY'),
        ),
      );
    });

    test(
      'startSession throws a friendly message when the worker is unreachable',
      () async {
        final client = MockClient((request) async {
          throw Exception('connection refused');
        });

        final api = CloudControlApiClient(
          client: client,
          baseUrl: 'http://test',
        );

        await expectLater(
          () => api.startSession('tok_1'),
          throwsA(isA<CloudControlApiException>()),
        );
      },
    );

    test('stopSession posts to the session-scoped stop route', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/sessions/s1/stop');
        expect(request.method, 'POST');
        return http.Response(
          jsonEncode({'sessionId': 's1', 'status': 'TERMINATED'}),
          200,
        );
      });

      final api = CloudControlApiClient(client: client, baseUrl: 'http://test');
      await api.stopSession('tok_1', 's1');
    });

    test('stopSession throws on a 403 from someone else\'s session', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'FORBIDDEN', 'message': 'Not your session'},
          }),
          403,
        );
      });

      final api = CloudControlApiClient(client: client, baseUrl: 'http://test');

      await expectLater(
        () => api.stopSession('tok_1', 's1'),
        throwsA(
          isA<CloudControlApiException>().having(
            (e) => e.code,
            'code',
            'FORBIDDEN',
          ),
        ),
      );
    });

    test('fetchSessionStatus parses the real status enum', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/sessions/s1/status');
        return http.Response(
          jsonEncode({'sessionId': 's1', 'status': 'LIVE'}),
          200,
        );
      });

      final api = CloudControlApiClient(client: client, baseUrl: 'http://test');
      final status = await api.fetchSessionStatus('tok_1', 's1');

      expect(status.status, 'LIVE');
      expect(status.isLive, isTrue);
    });
  });
}
