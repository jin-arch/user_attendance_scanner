import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  const base =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/';
  const basic = 'devuser:12456789!';
  final client = HttpClient();
  final token = base64Encode(utf8.encode(basic));

  Future<void> testGet(String ep, Map<String, String> q) async {
    final uri = Uri.parse('$base$ep').replace(queryParameters: q);
    stdout.writeln('GET $uri');
    final req = await client.getUrl(uri);
    req.headers.set('Authorization', 'Basic $token');
    req.headers.set('Accept', 'application/json');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    stdout.writeln('  -> ${res.statusCode} (${body.length} bytes)');
    if (body.length < 400) stdout.writeln('  $body');
  }

  Future<void> testPostQuery(String ep, Map<String, String> q) async {
    final uri = Uri.parse('$base$ep').replace(queryParameters: q);
    stdout.writeln('POST (no body) $uri');
    final req = await client.postUrl(uri);
    req.headers.set('Authorization', 'Basic $token');
    req.headers.set('Accept', 'application/json');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    stdout.writeln('  -> ${res.statusCode} (${body.length} bytes)');
    if (body.length < 400) stdout.writeln('  $body');
  }

  await testGet('get/site/all', {});
  await testGet('update/timeLog/timeIn', {
    'passedID': 'null',
    'timelogID': '999999',
    'remarks': 'TEST',
    'timelog': '2026-05-26',
    'timeInMorning': '08:00:00',
    'timeInAfternoon': '',
    'code': 'IN_AM',
  });
  await testPostQuery('update/timeLog/timeIn', {
    'passedID': 'null',
    'timelogID': '999999',
    'remarks': 'TEST',
    'timelog': '2026-05-26',
    'timeInMorning': '08:00:00',
    'timeInAfternoon': '',
    'code': 'IN_AM',
  });
  await testPostQuery('insert/hris/logs/transaction', {
    'passedID': 'null',
    'companyID': '1',
    'datelog': '2026-05-26',
    'log_time': '08:00:00',
    'log_type': 'IN_AM',
    'logID': '999999',
  });
  client.close(force: true);
}
