import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/hat_status.dart';

class DeviceApiException implements Exception {
  const DeviceApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

/// The backend's hat registry and firmware releases
/// (`/api/v1/devices`, `/api/v1/firmware-releases`).
class DeviceApiClient {
  DeviceApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'BACKEND_BASE_URL',
            defaultValue: 'http://localhost:4000',
          );

  final http.Client _client;
  final String _baseUrl;

  static const _timeout = Duration(seconds: 15);

  /// Links the hat described by [info] to the signed-in account, recording
  /// its firmware version and camera health.
  Future<void> linkDevice(String token, HatInfo info) async {
    final response = await _client
        .put(
          Uri.parse('$_baseUrl/api/v1/devices/${info.serialNumber}'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'hardwareModel': info.hardwareModel,
            'firmwareVersion': info.firmwareVersion,
            'cameraRestarts': info.cameraRestarts,
            'cameraFailed': info.camera == HatCameraHealth.failed,
          }),
        )
        .timeout(_timeout);
    _check(response);
  }

  /// The newest published release for [hardwareModel], or null if none.
  Future<FirmwareRelease?> latestFirmware(
    String token,
    String hardwareModel,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl/api/v1/firmware-releases',
    ).replace(queryParameters: {'hardwareModel': hardwareModel, 'limit': '1'});
    final response = await _client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(_timeout);
    final body = _check(response);
    final items = body['items'];
    if (items is! List || items.isEmpty) return null;
    return FirmwareRelease.fromJson(items.first as Map<String, dynamic>);
  }

  Map<String, dynamic> _check(http.Response response) {
    Map<String, dynamic> body = const {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    }
    if (response.statusCode >= 400) {
      final error = body['error'];
      throw DeviceApiException(
        error is Map<String, dynamic> && error['message'] is String
            ? error['message'] as String
            : 'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
        code: error is Map<String, dynamic> ? error['code'] as String? : null,
      );
    }
    return body;
  }
}
