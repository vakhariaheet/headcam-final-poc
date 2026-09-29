import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import 'app_logger.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;

  /// The backend's machine-readable error code (e.g. `INVALID_CREDENTIALS`,
  /// `EMAIL_ALREADY_EXISTS`) — see backend/src/errors/ApiError.ts.
  final String? code;

  @override
  String toString() => message;
}

class AuthResult {
  const AuthResult({required this.token, required this.user});
  final String token;
  final AppUser user;
}

class SignupChallenge {
  const SignupChallenge({
    required this.verificationToken,
    required this.email,
    required this.expiresInSeconds,
    this.developmentCode,
  });

  factory SignupChallenge.fromJson(Map<String, dynamic> json) => SignupChallenge(
    verificationToken: json['verificationToken'] as String,
    email: json['email'] as String,
    expiresInSeconds: json['expiresInSeconds'] as int,
    developmentCode: json['developmentCode'] as String?,
  );

  final String verificationToken;
  final String email;
  final int expiresInSeconds;
  final String? developmentCode;
}

/// Talks to backend/'s auth API (see backend/README.md). Defaults to
/// localhost:4000, which reaches the host machine directly from the iOS
/// Simulator. For a physical device, pass the host machine's LAN IP
/// instead (the simulator-only localhost shortcut doesn't apply there).
class AuthApiClient {
  AuthApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? 'http://localhost:4000';

  final http.Client _client;
  final String _baseUrl;

  Future<SignupChallenge> signUp({
    required String email,
    required String password,
    required String firstName,
    String? lastName,
  }) {
    return _post('/api/v1/auth/signup', {
      'email': email,
      'password': password,
      'firstName': firstName,
      if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
    }).then(SignupChallenge.fromJson);
  }

  Future<AuthResult> logIn({required String email, required String password}) {
    return _postAuth('/api/v1/auth/login', {
      'email': email,
      'password': password,
    });
  }

  Future<AuthResult> verifyEmail({
    required String verificationToken,
    required String code,
  }) {
    return _postAuth('/api/v1/auth/verify-email', {
      'verificationToken': verificationToken,
      'code': code,
    });
  }

  Future<SignupChallenge> resendVerification(String verificationToken) {
    return _post('/api/v1/auth/resend-verification', {
      'verificationToken': verificationToken,
    }).then(SignupChallenge.fromJson);
  }

  Future<AppUser> fetchMe(String token) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/v1/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw _apiExceptionFor(response);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AppUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<AuthResult> _postAuth(String path, Map<String, dynamic> body) async {
    final decoded = await _post(path, body);
    return AuthResult(
      token: decoded['token'] as String,
      user: AppUser.fromJson(decoded['user'] as Map<String, dynamic>),
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Failed to reach $_baseUrl$path',
        name: 'AuthApiClient',
        error: e,
        stackTrace: stackTrace,
      );
      throw const AuthApiException(
        "Couldn't reach the server. Is the backend running?",
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _apiExceptionFor(response);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  AuthApiException _apiExceptionFor(http.Response response) {
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>;
      return AuthApiException(
        error['message'] as String,
        statusCode: response.statusCode,
        code: error['code'] as String?,
      );
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Unparseable error body (status ${response.statusCode}): ${response.body}',
        name: 'AuthApiClient',
        error: e,
        stackTrace: stackTrace,
      );
      return AuthApiException(
        'Something went wrong (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
  }
}
