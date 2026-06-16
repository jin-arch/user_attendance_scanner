import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service to check if automatic time is enabled on the device
/// This is a security measure to prevent users from manually changing time
class TimeSecurityService {
  static const MethodChannel _channel = MethodChannel('com.example.user_attendance_scanner/zkfinger');

  /// Check if automatic time is enabled
  /// Returns a map with:
  /// - isAutoTimeEnabled: bool - whether automatic time is enabled
  /// - isAutoTimeZoneEnabled: bool - whether automatic time zone is enabled
  /// - isSecure: bool - whether both are enabled (system is secure)
  static Future<Map<String, bool>> checkAutomaticTime() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod('checkAutomaticTime');
        if (result is Map) {
          return {
            'isAutoTimeEnabled': result['isAutoTimeEnabled'] as bool? ?? false,
            'isAutoTimeZoneEnabled': result['isAutoTimeZoneEnabled'] as bool? ?? false,
            'isSecure': result['isSecure'] as bool? ?? false,
          };
        }
      } catch (e) {
        debugPrint('[TimeSecurity] Error checking automatic time: $e');
      }
    }
    
    // For non-Android platforms or if check fails, assume secure
    // (Windows doesn't have the same automatic time security concern)
    return {
      'isAutoTimeEnabled': true,
      'isAutoTimeZoneEnabled': true,
      'isSecure': true,
    };
  }

  /// Check if the device time settings are secure
  /// Returns true if automatic time is enabled (or on non-Android platforms)
  static Future<bool> isTimeSecure() async {
    final result = await checkAutomaticTime();
    return result['isSecure'] ?? true;
  }
}
