/// HRIS Biometrics API — import this file for config, endpoints, and HTTP client.
///
/// ```dart
/// import 'package:user_attendance_scanner/app/data/api/hris_api.dart';
///
/// final rows = await HrisApiProvider.instance.getRows(HrisEndpoints.sitesAll);
/// ```
library;

export '../../core/values/api_config.dart';
export '../providers/hris_api_provider.dart';
export 'hris_endpoints.dart';
