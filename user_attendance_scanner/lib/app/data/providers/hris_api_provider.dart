import 'dart:convert';
import 'dart:io';

import 'package:user_attendance_scanner/app/core/values/api_config.dart';
import 'package:user_attendance_scanner/app/core/utils/hris_log.dart';

/// Network client for HRIS Biometrics API (GET/POST endpoints).
class HrisApiProvider {
  HrisApiProvider._();
  static final HrisApiProvider instance = HrisApiProvider._();

  static void _log(String message) => hrisLog(message);

  static List<Map<String, dynamic>> extractRows(dynamic decoded) {
    dynamic data = decoded;
    if (decoded is Map<String, dynamic>) {
      data =
          decoded['data'] ??
          decoded['sites'] ??
          decoded['result'] ??
          decoded['records'] ??
          decoded['site'] ??
          decoded['employees'] ??
          decoded['timelogs'] ??
          decoded['timelog'] ??
          decoded['logs'] ??
          decoded['results'] ??
          decoded['items'] ??
          decoded;
    }

    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (data is Map<String, dynamic>) {
      return [data];
    }

    return const [];
  }

  Future<List<Map<String, dynamic>>> getRows(
    String endpoint, {
    Map<String, String?> queryParameters = const {},
  }) async {
    final client = HttpClient();
    client.connectionTimeout = ApiConfig.connectionTimeout;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint').replace(
        queryParameters: queryParameters.map(
          (key, value) => MapEntry(key, value ?? ''),
        ),
      );
      _log('GET $uri');
      final request = await client.getUrl(uri);
      _applyAuthHeaders(request);

      final response = await request.close().timeout(ApiConfig.requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode < 200 || response.statusCode > 299) {
        _log('ERROR GET HTTP ${response.statusCode} - $body');
        throw Exception('HTTP ${response.statusCode}: $body');
      }

      if (body.trim().isEmpty) {
        _log('GET empty response body');
        return const [];
      }

      _log('GET OK ${response.statusCode} (${body.length} bytes)');
      final decoded = jsonDecode(body);
      final rows = extractRows(decoded);
      _log('GET parsed ${rows.length} rows');
      return rows;
    } catch (e) {
      _log('GET failed: $e');
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// HRIS write endpoints (timeIn/timeOut, insert timeLog) require POST with query params.
  Future<List<Map<String, dynamic>>> postRows(
    String endpoint, {
    Map<String, String?> queryParameters = const {},
  }) async {
    final client = HttpClient();
    client.connectionTimeout = ApiConfig.connectionTimeout;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint').replace(
        queryParameters: queryParameters.map(
          (key, value) => MapEntry(key, value ?? ''),
        ),
      );
      _log('POST $uri');
      final request = await client.postUrl(uri);
      _applyAuthHeaders(request);

      final response = await request.close().timeout(ApiConfig.requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode < 200 || response.statusCode > 299) {
        _log('POST ERROR HTTP ${response.statusCode} - $body');
        throw Exception('HTTP ${response.statusCode}: $body');
      }

      if (body.trim().isEmpty) {
        _log('POST empty response body');
        return const [];
      }

      _log('POST OK ${response.statusCode} (${body.length} bytes)');
      final decoded = jsonDecode(body);
      final rows = extractRows(decoded);
      _log('POST parsed ${rows.length} rows');
      return rows;
    } catch (e) {
      _log('POST failed: $e');
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> postJson(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String?> queryParameters = const {},
  }) async {
    final client = HttpClient();
    client.connectionTimeout = ApiConfig.connectionTimeout;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint').replace(
        queryParameters: queryParameters.map(
          (key, value) => MapEntry(key, value ?? ''),
        ),
      );
      final leftLen = body['leftFingerThumb']?.toString().length ?? 0;
      final rightLen = body['rightFingerThumb']?.toString().length ?? 0;
      _log(
        'POST $uri employeeID=${body['employeeID']} '
        'leftLen=$leftLen rightLen=$rightLen',
      );
      final request = await client.postUrl(uri);
      _applyAuthHeaders(request);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json',
      );
      request.write(jsonEncode(body));

      final response = await request.close().timeout(ApiConfig.requestTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(ApiConfig.requestTimeout);
      if (response.statusCode < 200 || response.statusCode > 299) {
        _log('POST ERROR HTTP ${response.statusCode}: $responseBody');
        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }

      _log('POST OK HTTP ${response.statusCode}');

      if (responseBody.trim().isEmpty) {
        return <String, dynamic>{};
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'data': decoded};
    } finally {
      client.close(force: true);
    }
  }

  void _applyAuthHeaders(HttpClientRequest request) {
    final basicToken = base64Encode(
      utf8.encode('${ApiConfig.username}:${ApiConfig.password}'),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, ApiConfig.userAgent);
    request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');
  }
}
