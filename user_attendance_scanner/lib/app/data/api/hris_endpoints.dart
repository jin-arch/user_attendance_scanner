import 'package:user_attendance_scanner/app/core/values/api_config.dart';

/// HRIS Biometrics API endpoint paths (relative to [ApiConfig.baseUrl]).
abstract final class HrisEndpoints {
  // --- Sites ---
  static const String sitesAll = 'get/site/all';

  /// Alternate public site list (full URL, different base path).
  static const String publicSitesAll =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/public/api/v1/site/all';

  // --- Employees ---
  static const String employeesBySite = 'get/employee/perSite';
  static const String updateEmployeeThumbDetails = 'update/employee/thumbDetails';

  // --- Timelogs (read) ---
  static const String timelogByEmployee = 'get/timelog/perEmployee';
  static const String timelogLastWeekBySite = 'get/timelog/lastweek/perSite';

  // --- Timelogs (write) ---
  static const String postTimelog = 'post/timelog';
  static const String timeIn = 'update/timeLog/timeIn';
  static const String timeOut = 'update/timeLog/timeOutasd';
  static const String insertHrisLogTransaction = 'insert/hris/logs/transaction';
  static const String insertTimeLog = 'insert/timeLog';

  /// Full URL for a biometrics API endpoint path.
  static String url(String endpoint) => '${ApiConfig.baseUrl}$endpoint';

  /// Parsed URI with optional query parameters.
  static Uri uri(
    String endpoint, {
    Map<String, String?> queryParameters = const {},
  }) {
    return Uri.parse(url(endpoint)).replace(
      queryParameters: queryParameters.map(
        (key, value) => MapEntry(key, value ?? ''),
      ),
    );
  }
}
