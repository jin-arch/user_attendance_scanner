import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  const username = 'devuser';
  const password = '12456789!';
  final auth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  final endpoints = [
    'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/site/all',
    'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/employee/perSite?siteID=1',
    'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/timelog/lastweek/perSite?siteID=1',
    'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/timelog/perEmployee?siteID=1&employeeID=250223694',
    'https://fastdevs-api.com/HRIS_BIOMETRICS/public/api/v1/site/all',
  ];

  final headers = {
    'User-Agent': 'FAST-Attendance/1.0',
    'Authorization': auth,
  };

  for (final url in endpoints) {
    try {
      print('GET -> $url');
      final r = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
      print('  HTTP ${r.statusCode}');
      final body = r.body;
      final preview = body.length > 200 ? '${body.substring(0, 200)}...' : body;
      print('  Body: $preview\n');
    } catch (e) {
      print('  Request failed: $e\n');
    }
  }
}
