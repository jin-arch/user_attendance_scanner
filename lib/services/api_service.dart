import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/';
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';

  Map<String, String> _basicHeaders() {
    final basicToken = base64Encode(
      utf8.encode('$_apiUsername:$_apiPassword'),
    );
    return {
      'accept': 'application/json',
      'authorization': 'Basic $basicToken',
    };
  }

  // Get Sites
  Future<List<dynamic>> getSites() async {
    final response = await http.get(
      Uri.parse('${baseUrl}get/site/all'),
      headers: _basicHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load sites');
    }
  }

  // Get Employees by Site
  Future<List<dynamic>> getEmployees(String siteId) async {
    final response = await http.get(
      Uri.parse('${baseUrl}get/employee/perSite?siteID=$siteId'),
      headers: _basicHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load employees');
    }
  }

  // Get 3 months Employees timeLogs
  Future<List<dynamic>> getTimeLogs(String siteId) async {
    final response = await http.get(
      Uri.parse('${baseUrl}get/timelog/lastweek/perSite?siteID=$siteId'),
      headers: _basicHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load time logs');
    }
  }

  // Biometric Registration
  Future<bool> registerBiometric({
    required String employeeID,
    required String leftFingerThumb,
    required String rightFingerThumb,
  }) async {
    final uri = Uri.parse(
      '${baseUrl}update/employee/thumbDetails?employeeID=$employeeID',
    );

    final response = await http.put(
      uri,
      headers: {
        ..._basicHeaders(),
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'employeeID': employeeID,
        'leftFingerThumb': leftFingerThumb,
        'rightFingerThumb': rightFingerThumb,
      }),
    );
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  // Attendance Time In
  Future<bool> timeIn(Map<String, dynamic> timeLogModel, String code) async {
    // Build URL using string concatenation for code param
    final uri = Uri.parse(
      '${baseUrl}update/timeLog/timeIn'
      '?passedID=null'
      '&timelogID=${timeLogModel['timeLogID'] ?? ''}'
      '&remarks=${timeLogModel['remarks'] ?? ''}'
      '&timelog=${timeLogModel['timelog'] ?? ''}'
      '&timeInMorning=${timeLogModel['timeInMorning'] ?? ''}'
      '&timeInAfternoon=${timeLogModel['timeInAfternoon'] ?? ''}'
      '&code=$code'
    );

    final response = await http.get(uri, headers: _basicHeaders());
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  // Attendance Time Out
  Future<bool> timeOut(Map<String, dynamic> timeLogModel, String code) async {
    // Build URL using string concatenation for code param
    final uri = Uri.parse(
      '${baseUrl}update/timeLog/timeOut'
      '?passedID=null'
      '&timelogID=${timeLogModel['timeLogID'] ?? ''}'
      '&timelog=${timeLogModel['timelog'] ?? ''}'
      '&timeOutMorning=${timeLogModel['timeOutMorning'] ?? ''}'
      '&timeOutAfternoon=${timeLogModel['timeOutAfternoon'] ?? ''}'
      '&code=$code'
      '&remarks=${timeLogModel['remarks'] ?? ''}'
    );

    final response = await http.get(uri, headers: _basicHeaders());
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  // HRIS Logs
  Future<bool> insertHrisLog(Map<String, dynamic> timeLogModel, String code) async {
    final uri = Uri.parse('${baseUrl}insert/hris/logs/transaction').replace(
      queryParameters: {
        'passedID': 'null',
        'companyID': '${timeLogModel['employeeID'] ?? ''}',
        'datelog': '${timeLogModel['timelog'] ?? ''}',
        'log_time': '${timeLogModel['log_time'] ?? ''}',
        'log_type': code,
        'logID': '${timeLogModel['timeLogID'] ?? ''}',
      },
    );

    final response = await http.get(uri, headers: _basicHeaders());
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  // Insert TimeLog
  Future<bool> insertTimeLog(Map<String, dynamic> timeLogModel, String siteId, String code, String schedCode) async {
    final uri = Uri.parse('${baseUrl}insert/timeLog').replace(
      queryParameters: {
        'siteID': siteId,
        'employeeID': '${timeLogModel['employeeID'] ?? ''}',
        'timelogID': '${timeLogModel['timeLogID'] ?? ''}',
        'timelog': '${timeLogModel['timelog'] ?? ''}',
        'remarks': '${timeLogModel['remarks'] ?? ''}',
        'schedule': schedCode,
        'timeinmorning': '${timeLogModel['timeInMorning'] ?? ''}',
        'timeinafternoon': '${timeLogModel['timeInAfternoon'] ?? ''}',
        'timeoutmorning': '${timeLogModel['timeOutMorning'] ?? ''}',
        'timeoutafternoon': '${timeLogModel['timeOutAfternoon'] ?? ''}',
        'datecaptured': '${timeLogModel['timelog'] ?? ''}',
        'code': code,
      },
    );

    final response = await http.get(uri, headers: _basicHeaders());
    return response.statusCode >= 200 && response.statusCode < 300;
  }
}
