import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/cloud_status.dart';
import 'app_logger.dart';

class CloudControlApiException implements Exception {
  const CloudControlApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

/// Talks to the cloud compositor worker's session control API (see
/// cloud/worker/src/server.ts, cloud/README.md). Defaults to
/// localhost:4100, which reaches the host machine directly from the iOS
/// Simulator. For a physical device, pass the host machine's LAN IP
/// instead — same caveat as [AuthApiClient], now true for this second,
/// separate service.
class CloudControlApiClient {
  CloudControlApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? 'http://localhost:4100';

  final http.Client _client;
  final String _baseUrl;

  /// Creates a session and returns its server-issued id. Sends no team
  /// names or output destinations — the worker decides all of that
  /// server-side (see cloud/README.md's "Swapping in real destinations
  /// later" for why: nothing in this app has real ones to supply yet).
  Future<String> startSession(
    String token, {
    Map<String, dynamic>? scoreboard,
    String target = 'recording',
    String title = 'CreasePoint Live',
    String privacy = 'private',
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/sessions'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'target': target,
              'title': title,
              'privacy': privacy,
              'scoreboard': ?scoreboard,
            }),
          )
          .timeout(const Duration(seconds: 100));
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Failed to reach $_baseUrl/sessions',
        name: 'CloudControlApiClient',
        error: e,
        stackTrace: stackTrace,
      );
      throw const CloudControlApiException(
        "Couldn't reach the cloud worker. Is it running?",
      );
    }

    if (response.statusCode != 201) {
      throw _apiExceptionFor(response);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['sessionId'] as String;
  }

  Future<void> updateScoreboard(
    String token,
    String sessionId,
    Map<String, dynamic> scoreboard,
  ) async {
    final response = await _client
        .patch(
          Uri.parse('$_baseUrl/sessions/$sessionId/scoreboard'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(scoreboard),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw _apiExceptionFor(response);
  }

  Future<void> stopSession(String token, String sessionId) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl/sessions/$sessionId/stop'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Failed to reach $_baseUrl/sessions/$sessionId/stop',
        name: 'CloudControlApiClient',
        error: e,
        stackTrace: stackTrace,
      );
      throw const CloudControlApiException(
        "Couldn't reach the cloud worker. Is it running?",
      );
    }

    if (response.statusCode != 200) {
      throw _apiExceptionFor(response);
    }
  }

  Future<CloudStatus> fetchSessionStatus(String token, String sessionId) async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$_baseUrl/sessions/$sessionId/status'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Failed to reach $_baseUrl/sessions/$sessionId/status',
        name: 'CloudControlApiClient',
        error: e,
        stackTrace: stackTrace,
      );
      throw const CloudControlApiException(
        "Couldn't reach the cloud worker. Is it running?",
      );
    }

    if (response.statusCode != 200) {
      throw _apiExceptionFor(response);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return CloudStatus.fromJson(decoded);
  }

  CloudControlApiException _apiExceptionFor(http.Response response) {
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>;
      return CloudControlApiException(
        error['message'] as String,
        statusCode: response.statusCode,
        code: error['code'] as String?,
      );
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Unparseable error body (status ${response.statusCode}): ${response.body}',
        name: 'CloudControlApiClient',
        error: e,
        stackTrace: stackTrace,
      );
      return CloudControlApiException(
        'Something went wrong (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
  }
}
