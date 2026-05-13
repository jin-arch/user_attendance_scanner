import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../services/local_db.dart';

/// Legacy controller to maintain backward compatibility with existing home_page.dart
class LegacyHomePageController extends GetxController {
  static const String _apiBaseUrl =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/';
  static const String _siteApiUrl = '${_apiBaseUrl}get/site/all';
  static const String _employeesApiUrl =
      '${_apiBaseUrl}get/employee/perSite?siteID=';
  static const String _timelogPerSiteApiUrl =
      '${_apiBaseUrl}get/timelog/lastweek/perSite?siteID=';
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';
  static const int _timeOutCooldownMinutes = 5;

  final Rx<DateTime> now = DateTime.now().obs;
  final RxBool biometricConnected = false.obs;
  final RxBool isSearching = false.obs;
  final RxBool isScanning = false.obs;
  final RxString statusMessage = ''.obs;
  final RxString lastDbSyncLabel = ''.obs;

  Timer? _clockTimer;

  // Getter for backward compatibility
  RxString get status => statusMessage;

  @override
  void onInit() {
    super.onInit();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      now.value = DateTime.now();
    });
  }

  @override
  void onClose() {
    _clockTimer?.cancel();
    super.onClose();
  }

  void startSearching([String? status]) {
    isSearching.value = true;
    if (status != null) {
      statusMessage.value = status;
    }
  }

  void stopSearching([String? status]) {
    isSearching.value = false;
    if (status != null) {
      statusMessage.value = status;
    }
  }

  void setConnected(bool connected, {String? status}) {
    biometricConnected.value = connected;
    if (!connected) {
      isScanning.value = false;
    }
    if (status != null) {
      statusMessage.value = status;
    }
  }

  void setScanning(bool scanning) {
    isScanning.value = scanning;
  }

  void setStatus(String status) {
    statusMessage.value = status;
  }

  void setLastDbSync([DateTime? syncedAt]) {
    final dateTime = syncedAt ?? DateTime.now();
    final hour12 = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    lastDbSyncLabel.value =
        'Last DB Sync: ${hour12.toString().padLeft(2, '0')}:$minute:$second $period';
  }

  Future<List<Map<String, dynamic>>> fetchSiteRows() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(_siteApiUrl));
      final basicToken = base64Encode(
        utf8.encode('$_apiUsername:$_apiPassword'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
      return _extractRows(decoded);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> syncEmployeesFromApiToLocalDb(String siteId) async {
    await LocalDb.pruneToSite(siteId);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final urlStr = '$_employeesApiUrl$siteId';
      final request = await client.getUrl(Uri.parse(urlStr));
      final basicToken = base64Encode(
        utf8.encode('$_apiUsername:$_apiPassword'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
      final rows = _extractRows(decoded);

      int totalEmps = 0;
      int skippedEmps = 0;
      int savedFingerprints = 0;
      int skippedTemplates = 0;
      final templatesToSave = <Map<String, dynamic>>[];
      for (final row in rows) {
        totalEmps++;
        final empId =
            (row['employee_id'] ?? row['emp_id'] ?? row['id'] ?? row['EMPID'])
                ?.toString()
                .trim();
        final firstName =
            (row['FIRSTNAME'] ?? row['first_name'])?.toString().trim();
        final middleName =
            (row['MIDDLENAME'] ?? row['middle_name'])?.toString().trim();
        final lastName =
            (row['LASTNAME'] ?? row['last_name'])?.toString().trim();
        final fullNameParts = [firstName, middleName, lastName]
            .whereType<String>()
            .where((part) => part.isNotEmpty && part.toLowerCase() != 'null')
            .toList();
        final empName = (row['employee_name'] ?? row['full_name'] ?? row['name'])
            ?.toString()
            .trim();
        final resolvedName = fullNameParts.isNotEmpty
            ? fullNameParts.join(' ')
            : ((empName != null &&
                    empName.isNotEmpty &&
                    empName.toLowerCase() != 'null')
                ? empName
                : null);

        if (empId == null || empId.isEmpty) {
          skippedEmps++;
          continue;
        }

        final thumbTemplates = <String, String?>{
          'left':
              (row['LEFTFINGERTHUMB'] ?? row['leftFingerThumb'] ?? row['left_thumb'])
                  ?.toString(),
          'right': (row['RIGHTFINGERTHUMB'] ??
                  row['rightFingerThumb'] ??
                  row['right_thumb'])
              ?.toString(),
          'default':
              (row['finger_template'] ?? row['template'] ?? row['fingerprint'])
                  ?.toString(),
        };

        for (final entry in thumbTemplates.entries) {
          final templateB64 = entry.value?.trim();
          if (_isBlank(templateB64)) {
            skippedTemplates++;
            continue;
          }

          try {
            final fid = _stableFingerprintId(empId, entry.key);
            templatesToSave.add({
              'fid': fid,
              'employee_id': empId,
              'employee_name': resolvedName,
              'finger_template': base64Decode(templateB64!),
            });
            savedFingerprints++;
          } catch (_) {
            skippedTemplates++;
          }
        }
      }

      await LocalDb.mergeEmployeesFromApi(
        siteId: siteId,
        apiEmployees: templatesToSave,
      );

      final dbCount = await LocalDb.getEmployeeCountBySite(siteId);
      debugPrint(
        '[SYNC_DEBUG] site=$siteId employees=$totalEmps skippedEmployees=$skippedEmps '
        'savedTemplates=$savedFingerprints skippedTemplates=$skippedTemplates dbCount=$dbCount',
      );
      setLastDbSync();
    } catch (e) {
      debugPrint('syncEmployeesFromApiToLocalDb: $e');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> fetchAndCacheSiteTimeLogs(String siteId) async {
    try {
      debugPrint('[TIMELOG_FETCH] ===== START FETCHING TIMELOGS =====');
      debugPrint('[TIMELOG_FETCH] SiteID: $siteId');
      final apiUrl = '$_timelogPerSiteApiUrl$siteId';
      debugPrint('[TIMELOG_FETCH] API URL: $apiUrl');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      try {
        final request = await client.getUrl(
          Uri.parse(apiUrl),
        );
        final basicToken = base64Encode(
          utf8.encode('$_apiUsername:$_apiPassword'),
        );
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic $basicToken',
        );

        debugPrint('[TIMELOG_FETCH] Sending HTTP GET request...');
        final response = await request.close();
        debugPrint('[TIMELOG_FETCH] HTTP Response Status: ${response.statusCode}');

        final body = await response.transform(utf8.decoder).join();
        debugPrint('[TIMELOG_FETCH] Response Body Length: ${body.length} characters');

        if (body.length < 500) {
          debugPrint('[TIMELOG_FETCH] Response Body: $body');
        } else {
          debugPrint('[TIMELOG_FETCH] Response Body (first 500 chars): ${body.substring(0, 500)}');
        }

        if (response.statusCode < 200 || response.statusCode > 299) {
          debugPrint('[TIMELOG_FETCH] ERROR: HTTP ${response.statusCode} - $body');
          throw Exception('HTTP ${response.statusCode}: $body');
        }

        if (body.isEmpty) {
          debugPrint('[TIMELOG_FETCH] WARNING: Empty response body from API');
          return;
        }

        debugPrint('[TIMELOG_FETCH] Decoding JSON response...');
        final decoded = jsonDecode(body);
        debugPrint('[TIMELOG_FETCH] Decoded JSON type: ${decoded.runtimeType}');

        final rows = _extractRows(decoded);
        debugPrint('[TIMELOG_FETCH] Extracted rows count: ${rows.length}');

        if (rows.isEmpty) {
          debugPrint('[TIMELOG_FETCH] WARNING: No rows extracted from API response');
          debugPrint('[TIMELOG_FETCH] Full decoded response: $decoded');
          return;
        }

        // Log first 3 rows for inspection
        for (int i = 0; i < rows.take(3).length; i++) {
          debugPrint('[TIMELOG_FETCH] Row $i: ${rows[i]}');
        }

        debugPrint('[TIMELOG_FETCH] Saving ${rows.length} rows to local cache...');
        await LocalDb.replaceTimelogCache(siteId: siteId, rows: rows);
        debugPrint('[TIMELOG_FETCH] ===== TIMELOG FETCH COMPLETE =====');
      } finally {
        client.close(force: true);
      }
    } catch (e, stackTrace) {
      debugPrint('[TIMELOG_FETCH] ERROR: $e');
      debugPrint('[TIMELOG_FETCH] Stack trace: $stackTrace');
    }
  }

  Future<void> syncPendingHrisQueue() async {
    try {
      await LocalDb.syncPendingHrisQueue();
    } catch (e) {
      debugPrint('syncPendingHrisQueue: $e');
    }
  }

  List<Map<String, dynamic>> _extractRows(dynamic decoded) {
    debugPrint('[EXTRACT_ROWS] Input type: ${decoded.runtimeType}');

    dynamic data = decoded;
    if (decoded is Map<String, dynamic>) {
      // Try common response wrapper keys
      data =
          decoded['data'] ??
              decoded['sites'] ??
              decoded['result'] ??
              decoded['records'] ??
              decoded['site'] ??
              decoded['employees'] ??
              decoded['timelogs'] ??
              decoded['timelog'] ??
              decoded['logs'] ??
              decoded['results'] ??
              decoded['items'] ??
              decoded;  // If no wrapper found, use the entire map
    }

    debugPrint('[EXTRACT_ROWS] Data type after extraction: ${data.runtimeType}');

    if (data is List) {
      debugPrint('[EXTRACT_ROWS] Found list with ${data.length} items');
      final result = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      debugPrint('[EXTRACT_ROWS] Converted to ${result.length} valid maps');
      return result;
    } else if (data is Map<String, dynamic>) {
      debugPrint('[EXTRACT_ROWS] Converting single map to list');
      return [data];
    }

    debugPrint('[EXTRACT_ROWS] No valid data format found, returning empty list');
    return const [];
  }

  int _stableFingerprintId(String employeeId, String thumbKey) {
    var hash = 0x811C9DC5;
    final input = '$employeeId:$thumbKey';
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  bool _isBlank(dynamic value) {
    if (value == null) return true;
    final text = value.toString().trim();
    return text.isEmpty || text == 'null';
  }

  Future<String?> recordAttendance({
    required String siteId,
    required String employeeId,
  }) async {
    try {
      final now = DateTime.now();
      final today = now.toIso8601String().split('T')[0];
      final timeStr = formatTimeOnly(now);

      final existingTimelog = await LocalDb.getLatestTimelogForEmployee(
        siteId: siteId,
        employeeId: employeeId,
      );

      if (existingTimelog != null) {
        final timelogDate = existingTimelog['timeLogDate']?.toString() ??
            existingTimelog['timelog_date']?.toString() ??
            existingTimelog['timelog']?.toString();

        if (timelogDate != null && timelogDate.startsWith(today)) {
          final timeInMorning = existingTimelog['timeInMorning']?.toString();
          final timeOutMorning = existingTimelog['timeOutMorning']?.toString();
          final timeOutAfternoon =
              existingTimelog['timeOutAfternoon']?.toString();

          // Additional check: If user has any time in today without corresponding time out
          if ((!isBlankAttendanceValue(timeInMorning) && isBlankAttendanceValue(timeOutMorning)) || 
              (!isBlankAttendanceValue(existingTimelog['timeInAfternoon']) && isBlankAttendanceValue(timeOutAfternoon))) {
            return 'ALREADY IN';
          }

          if (!isBlankAttendanceValue(timeInMorning) &&
              isBlankAttendanceValue(timeOutMorning)) {
            final timeInDateTime = _parseTodayTime(timeInMorning, now);

            if (timeInDateTime != null &&
                now.difference(timeInDateTime).inMinutes >=
                    _timeOutCooldownMinutes) {
              await LocalDb.saveTimelog(
                siteId: siteId,
                employeeId: employeeId,
                timelogData: {
                  'timelogID':
                      existingTimelog['timelogID'] ?? 'tl_${now.millisecondsSinceEpoch}',
                  'timelog': timeStr,
                  'timeLogDate': today,
                  'timeInMorning': timeInMorning,
                  'timeOutMorning': timeStr,
                  'remarks': 'AUTO TIMEOUT',
                  'schedule': 'AUTO',
                  'code': 'SUCCESS',
                },
              );
              return 'TIME OUT';
            }
            return 'ALREADY IN';
          }

          if (!isBlankAttendanceValue(timeOutMorning) ||
              !isBlankAttendanceValue(timeOutAfternoon)) {
            return 'ALREADY OUT - Come back tomorrow';
          }
        }
      }

      await LocalDb.saveTimelog(
        siteId: siteId,
        employeeId: employeeId,
        timelogData: {
          'timelogID': 'tl_${now.millisecondsSinceEpoch}',
          'timelog': timeStr,
          'timeLogDate': today,
          'timeInMorning': timeStr,
          'remarks': 'SUCCESS',
          'schedule': 'AUTO',
          'code': 'SUCCESS',
        },
      );

      return 'TIME IN';
    } catch (e) {
      debugPrint('recordAttendance error: $e');
      return 'TIME IN UNSUCCESSFUL';
    }
  }

  String formatTimeOnly(DateTime dateTime) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    final s = dateTime.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  bool isBlankAttendanceValue(dynamic value) {
    if (value == null) return true;
    final text = value.toString().trim();
    return text.isEmpty || 
           text == '00:00:00' || 
           text == '00:00' || 
           text == '0' || 
           text == '-' || 
           text.toLowerCase() == 'null' ||
           text.toLowerCase() == 'n/a' ||
           text.toLowerCase() == 'na' ||
           text.toLowerCase() == 'none' ||
           text.toLowerCase() == 'empty';
  }

  DateTime? _parseTodayTime(String? rawTime, DateTime now) {
    if (isBlankAttendanceValue(rawTime)) return null;
    final text = rawTime!.trim();
    final upper = text.toUpperCase();
    final hasPm = upper.contains('PM');
    final hasAm = upper.contains('AM');
    final normalized = upper.replaceAll(RegExp(r'[^0-9:]'), '');
    final parts = normalized
        .split(':')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;

    var hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    if (hour == null || minute == null) return null;

    if (hasPm && hour < 12) hour += 12;
    if (hasAm && hour == 12) hour = 0;
    if (hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59) {
      return null;
    }

    return DateTime(now.year, now.month, now.day, hour, minute, second);
  }
}
