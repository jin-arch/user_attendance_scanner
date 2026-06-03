import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final auth =
      'Basic ${base64Encode(utf8.encode('devuser:12456789!'))}';
  const base =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/';
  final paths = [
    'get/timelog/lastweek/perSite?siteID=1',
    'get/timelog/perEmployee?employeeID=250223694',
    'get/timelog/perEmployee?employeeID=250223694&siteID=1',
    'get/timelog/perEmployee?EMPLOYEEID=250223694',
    'get/timelog/perEmployee?employeeID=250925864',
    'get/timelog/history/perEmployee?employeeID=250223694',
    'get/timelog/history/perEmployee?employeeID=250223694&siteID=1',
    'get/timelog/all/perEmployee?employeeID=250223694',
    'get/timelog/month/perSite?siteID=1',
    'get/timelog/year/perSite?siteID=1',
  ];
  for (final p in paths) {
    try {
      final r = await http
          .get(
            Uri.parse('$base$p'),
            headers: {'Authorization': auth, 'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 25));
      stdout.writeln('${r.statusCode} $p (${r.body.length} bytes)');
      if (r.statusCode != 200) {
        final preview = r.body.length > 80 ? r.body.substring(0, 80) : r.body;
        stdout.writeln('  $preview');
      }
    } catch (e) {
      stdout.writeln('ERR $p: $e');
    }
  }
}
