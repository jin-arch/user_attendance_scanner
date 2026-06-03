import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  const base =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/';
  final client = HttpClient();
  final token = base64Encode(utf8.encode('devuser:12456789!'));

  Future<void> postJson(String ep, Map<String, dynamic> body, {String? empId}) async {
    final q = empId != null ? {'employeeID': empId} : <String, String>{};
    final uri = Uri.parse('$base$ep').replace(queryParameters: q);
    stdout.writeln('POST $uri');
    stdout.writeln('body keys: ${body.keys}');
    final req = await client.postUrl(uri);
    req.headers.set('Authorization', 'Basic $token');
    req.headers.set('Accept', 'application/json');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    stdout.writeln('  -> ${res.statusCode}: $text');
  }

  await postJson(
    'update/employee/thumbDetails',
    {
      'employeeID': 'TEST_EMP',
      'leftFingerThumb': 'dGVzdA==',
      'rightFingerThumb': 'dGVzdDI=',
    },
    empId: 'TEST_EMP',
  );
  client.close(force: true);
}
