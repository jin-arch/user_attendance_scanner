/// HRIS Biometrics API configuration (single source of truth).
abstract final class ApiConfig {
  static const String baseUrl =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/';

  static const String username = 'devuser';
  static const String password = '12456789!';

  static const Duration requestTimeout = Duration(seconds: 25);
  static const Duration connectionTimeout = Duration(seconds: 30);

  static const String userAgent = 'FAST-Attendance/1.0';
}
