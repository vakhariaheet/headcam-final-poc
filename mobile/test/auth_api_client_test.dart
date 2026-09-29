import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/services/auth_api_client.dart';

void main() {
  group('AuthApiClient', () {
    test('signUp returns an email verification challenge on 201', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/signup');
        return http.Response(
          jsonEncode({
            'verificationToken': 'verify_abc123',
            'email': 'a@b.com',
            'expiresInSeconds': 600,
            'developmentCode': '123456',
          }),
          201,
        );
      });

      final api = AuthApiClient(client: client, baseUrl: 'http://test');
      final challenge = await api.signUp(
        email: 'a@b.com',
        password: 'password1',
        firstName: 'A',
      );

      expect(challenge.verificationToken, 'verify_abc123');
      expect(challenge.email, 'a@b.com');
      expect(challenge.expiresInSeconds, 600);
      expect(challenge.developmentCode, '123456');
    });

    test('verifyEmail returns the authenticated user and session', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/verify-email');
        expect(jsonDecode(request.body), {
          'verificationToken': 'verify_abc123',
          'code': '123456',
        });
        return http.Response(
          jsonEncode({
            'token': 'session_1',
            'user': {
              'id': 'u1',
              'email': 'a@b.com',
              'firstName': 'A',
              'lastName': 'B',
              'role': 'UMPIRE',
            },
          }),
          200,
        );
      });
      final api = AuthApiClient(client: client, baseUrl: 'http://test');
      final result = await api.verifyEmail(
        verificationToken: 'verify_abc123',
        code: '123456',
      );
      expect(result.token, 'session_1');
      expect(result.user.displayName, 'A B');
    });

    test(
      'login throws AuthApiException with the server message and code on 401',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'INVALID_CREDENTIALS',
                'message': 'Invalid email or password',
              },
            }),
            401,
          );
        });

        final api = AuthApiClient(client: client, baseUrl: 'http://test');

        await expectLater(
          () => api.logIn(email: 'a@b.com', password: 'wrong'),
          throwsA(
            isA<AuthApiException>()
                .having(
                  (e) => e.message,
                  'message',
                  'Invalid email or password',
                )
                .having((e) => e.code, 'code', 'INVALID_CREDENTIALS'),
          ),
        );
      },
    );

    test(
      'signUp throws a friendly message when the server is unreachable',
      () async {
        final client = MockClient((request) async {
          throw Exception('connection refused');
        });

        final api = AuthApiClient(client: client, baseUrl: 'http://test');

        await expectLater(
          () => api.signUp(
            email: 'a@b.com',
            password: 'password1',
            firstName: 'A',
          ),
          throwsA(isA<AuthApiException>()),
        );
      },
    );

    test('fetchMe sends the bearer token and parses the user', () async {
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer tok_1');
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'u1',
              'email': 'a@b.com',
              'firstName': 'A',
              'lastName': null,
              'role': 'UMPIRE',
            },
          }),
          200,
        );
      });

      final api = AuthApiClient(client: client, baseUrl: 'http://test');
      final user = await api.fetchMe('tok_1');

      expect(user.displayName, 'A');
    });
  });
}
