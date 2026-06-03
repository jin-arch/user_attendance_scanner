import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Visible in Android logcat: filter `HRIS_API` or `flutter`.
void hrisLog(String message) {
  debugPrint('[HRIS_API] $message');
  developer.log(message, name: 'HRIS_API');
}

void pendingSyncLog(String message) {
  debugPrint('[PENDING_SYNC] $message');
  developer.log(message, name: 'PENDING_SYNC');
}
