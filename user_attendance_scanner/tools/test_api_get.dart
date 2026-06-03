import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final url = 'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/employees?site_id=1';
  const username = 'devuser';
  const password = '12456789!';

  final headers = {
    'User-Agent': 'FAST-Attendance/1.0',
    'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
  };

  try {
    print('GET -> $url');
    final resp = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
    print('HTTP ${resp.statusCode}');
    print('Body: ${resp.body}');
  } catch (e) {
    print('Request failed: $e');
  }
}
