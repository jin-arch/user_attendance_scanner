import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'local_db.dart';
import 'offline_mode_sync_service.dart';
import 'scanner_registry_service.dart';

/// Syncs offline queue (attendance + fingerprint updates) when online.
class PendingSyncService extends GetxService {
  final _offlineMode = OfflineModeSyncService();

  ScannerRegistryService get _registry => Get.find<ScannerRegistryService>();

  bool get shouldSyncNow => _offlineMode.isOnlineMode();

  Future<({int synced, int failed})> syncAllPending({String? siteId}) async {
    if (!shouldSyncNow) {
      debugPrint('[PENDING_SYNC] Skipped — app is in offline mode');
      return (synced: 0, failed: 0);
    }

    var synced = 0;
    var failed = 0;

    final pending = await LocalDb.getPendingAttendance();
    for (final row in pending) {
      try {
        final ok = await _syncRow(row, siteId: siteId);
        if (ok) {
          synced++;
        } else {
          failed++;
        }
      } catch (e) {
        failed++;
        debugPrint('[PENDING_SYNC] Row ${row['id']} failed: $e');
      }
    }

    if (siteId != null && siteId.isNotEmpty) {
      await _registry.reloadSiteFromLocalDb(siteId);
    }

    debugPrint('[PENDING_SYNC] Done synced=$synced failed=$failed');
    return (synced: synced, failed: failed);
  }

  Future<bool> _syncRow(
    Map<String, dynamic> row, {
    String? siteId,
  }) async {
    final id = row['id'] as int?;
    if (id == null) return false;

    final recordType =
        (row['record_type'] ?? 'attendance').toString().toLowerCase();
    final employeeId = row['employee_id']?.toString() ?? '';
    final rowSiteId = row['site_id']?.toString() ?? siteId ?? '';

    if (recordType == 'fingerprint') {
      return _syncFingerprint(
        queueId: id,
        employeeId: employeeId,
        siteId: rowSiteId,
      );
    }

    return _syncAttendance(
      queueId: id,
      employeeId: employeeId,
      siteId: rowSiteId,
      attendanceTime: row['attendance_time']?.toString() ?? '',
      payloadJson: row['payload_json']?.toString(),
    );
  }

  Future<bool> _syncAttendance({
    required int queueId,
    required String employeeId,
    required String siteId,
    required String attendanceTime,
    String? payloadJson,
  }) async {
    Map<String, dynamic>? payload;
    if (payloadJson != null && payloadJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(payloadJson);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } catch (_) {}
    }

    if (payload == null && siteId.isNotEmpty) {
      payload = await LocalDb.getTimelogPayloadForPendingAttendance(
        employeeId: employeeId,
        siteId: siteId,
        attendanceTime: attendanceTime,
      );
    }

    if (payload == null) {
      debugPrint('[PENDING_SYNC] No timelog payload for queue $queueId');
      return false;
    }

    await LocalDb.submitAttendanceSync(
      siteId: siteId,
      employeeId: employeeId,
      timeLogId: payload['timeLogId']?.toString() ?? '',
      timeLog: payload['timeLogDate']?.toString() ?? '',
      remarks: payload['remarks']?.toString() ?? 'SUCCESS',
      schedule: payload['schedule']?.toString() ?? 'AUTO',
      code: payload['code']?.toString() ?? 'IN_AM',
      timeInMorning: payload['timeInMorning']?.toString(),
      timeOutMorning: payload['timeOutMorning']?.toString(),
      timeInAfternoon: payload['timeInAfternoon']?.toString(),
      timeOutAfternoon: payload['timeOutAfternoon']?.toString(),
    );

    await LocalDb.markAttendanceSynced(queueId);
    return true;
  }

  Future<bool> _syncFingerprint({
    required int queueId,
    required String employeeId,
    required String siteId,
  }) async {
    if (employeeId.isEmpty || siteId.isEmpty) return false;

    final templates = await LocalDb.getEmployeeThumbTemplatesForApi(
      employeeId: employeeId,
      siteId: siteId,
    );
    if (templates == null) return false;

    await LocalDb.updateEmployeeThumbDetails(
      employeeId: employeeId,
      leftFingerThumb: templates.$1,
      rightFingerThumb: templates.$2,
    );

    await LocalDb.markAttendanceSynced(queueId);
    await _registry.reloadSiteFromLocalDb(siteId);
    return true;
  }
}
