import 'dart:convert';

import 'package:http/http.dart' as http;

class YouTubeApiClient {
  YouTubeApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'BACKEND_BASE_URL',
            defaultValue: 'http://localhost:4000',
          );
  final http.Client _client;
  final String _baseUrl;
  Future<Map<String, dynamic>> request(
    String method,
    String path,
    String token,
  ) async {
    final request = http.Request(
      method,
      Uri.parse('$_baseUrl/api/v1/youtube/$path'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    final response = await http.Response.fromStream(await _client.send(request))
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(
        (body['error'] as Map<String, dynamic>?)?['message'] ??
            'YouTube connection failed.',
      );
    }
    return body;
  }
}
