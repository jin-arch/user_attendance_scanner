import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final url = 'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/post/timelog/';
  const username = 'devuser';
  const password = '12456789!';

  final headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent': 'FAST-Attendance/1.0',
    'Authorization': 'Basic ${base64Encode(utf8.encode(''))}',
  };

  // Build Authorization header correctly
  final auth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  headers['Authorization'] = auth;

  final now = DateTime.now();
  final body = {
    'employee_id': 'TEST123',
    'employee_name': 'Test User',
    'type': 'IN',
    'timestamp': now.toIso8601String(),
    'time_only': now.toIso8601String().split('T').last,
    'period': 'AM',
    'site_id': '1',
    'raw_data': 'automated-test',
  };

  try {
    print('POST -> $url');
    final resp = await http
        .post(Uri.parse(url), headers: headers, body: json.encode(body))
        .timeout(const Duration(seconds: 15));

    print('HTTP ${resp.statusCode}');
    print('Response body: ${resp.body}');
  } catch (e) {
    print('Request failed: $e');
  }
}
