import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../utils/hris_log.dart';
import 'hris_push_policy.dart';
import 'local_db.dart';
import 'scanner_registry_service.dart';

/// Syncs offline queue (attendance + fingerprint updates) to HRIS API.
class PendingSyncService extends GetxService {
  /// When UI is Online mode, always attempt HRIS push (connectivity checked only for logging).
  Future<bool> shouldPushToHrisApi() => HrisPushPolicy.shouldPushToHrisApi();

  /// Push one attendance row to HRIS (all endpoints in [LocalDb.submitAttendanceSync]).
  Future<bool> uploadAttendancePayload({
    required String siteId,
    required String employeeId,
    required Map<String, dynamic> payload,
  }) async {
    pendingSyncLog(
      'uploadAttendance start employee=$employeeId site=$siteId code=${payload['code']}',
    );
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
    pendingSyncLog('uploadAttendance done employee=$employeeId');
    return true;
  }

  /// Push fingerprint templates to HRIS thumbDetails API.
  Future<bool> uploadFingerprint({
    required String employeeId,
    required String siteId,
    String? leftFingerThumb,
    String? rightFingerThumb,
  }) async {
    String? left = leftFingerThumb;
    String? right = rightFingerThumb;

    if (left == null || right == null) {
      final templates = await LocalDb.getEmployeeThumbTemplatesForApi(
        employeeId: employeeId,
        siteId: siteId,
      );
      if (templates == null) {
        pendingSyncLog('No thumb templates for employee=$employeeId');
        return false;
      }
      left = templates.$1;
      right = templates.$2;
    }

    pendingSyncLog(
      'uploadFingerprint start employee=$employeeId leftLen=${left.length} rightLen=${right.length}',
    );
    await LocalDb.updateEmployeeThumbDetails(
      employeeId: employeeId,
      leftFingerThumb: left,
      rightFingerThumb: right,
    );
    pendingSyncLog('uploadFingerprint done employee=$employeeId');
    return true;
  }

  Future<void> markFingerprintQueueSynced({
    required String employeeId,
    required String siteId,
  }) async {
    final pending = await LocalDb.getAllUnsyncedQueueRows();
    for (final row in pending) {
      if ((row['record_type'] ?? '').toString().toLowerCase() != 'fingerprint') {
        continue;
      }
      if (row['employee_id']?.toString() != employeeId) continue;
      if (row['site_id']?.toString() != siteId) continue;
      final id = row['id'] as int?;
      if (id != null) await LocalDb.markAttendanceSynced(id);
    }
  }

  Future<({int synced, int failed})> syncAllPending({String? siteId}) async {
    if (!await shouldPushToHrisApi()) {
      pendingSyncLog('syncAllPending skipped (not online / no network)');
      return (synced: 0, failed: 0);
    }

    var synced = 0;
    var failed = 0;

    final pending = await LocalDb.getAllUnsyncedQueueRows();
    final rows = _rowsForSite(pending, siteId);
    pendingSyncLog(
      'syncAllPending start pending=${rows.length} siteId=${siteId ?? "(all)"}',
    );
    for (final row in rows) {
      try {
        final ok = await _syncRow(row, siteId: siteId);
        if (ok) {
          synced++;
        } else {
          failed++;
        }
      } catch (e, st) {
        failed++;
        pendingSyncLog('Row ${row['id']} failed: $e');
        debugPrintStack(stackTrace: st, label: 'PENDING_SYNC');
      }
    }

    if (siteId != null && siteId.isNotEmpty) {
      await _reloadScannerIfRegistered(siteId);
    }

    pendingSyncLog('syncAllPending done synced=$synced failed=$failed');
    return (synced: synced, failed: failed);
  }

  List<Map<String, dynamic>> _rowsForSite(
    List<Map<String, dynamic>> rows,
    String? siteId,
  ) {
    if (siteId == null || siteId.isEmpty) return rows;
    return rows.where((row) {
      final rowSite = row['site_id']?.toString() ?? '';
      return rowSite.isEmpty || rowSite == siteId;
    }).toList();
  }

  /// HRIS queue + attendance queue; retries until no progress or pending cleared.
  Future<({int synced, int failed, int remaining})> flushAllPending({
    String? siteId,
  }) async {
    if (!await shouldPushToHrisApi()) {
      pendingSyncLog('flushAllPending skipped (not online / no network)');
      final remaining = siteId != null && siteId.isNotEmpty
          ? await LocalDb.countPendingTimelogsForSite(siteId)
          : 0;
      return (synced: 0, failed: 0, remaining: remaining);
    }

    var totalSynced = 0;
    var totalFailed = 0;

    await LocalDb.syncPendingHrisQueue();

    for (var pass = 0; pass < 5; pass++) {
      final result = await syncAllPending(siteId: siteId);
      totalSynced += result.synced;
      totalFailed += result.failed;
      if (result.synced == 0 && result.failed == 0) break;

      if (siteId != null && siteId.isNotEmpty) {
        final left = await LocalDb.countPendingTimelogsForSite(siteId);
        if (left == 0) break;
      }
    }

    final remaining = siteId != null && siteId.isNotEmpty
        ? await LocalDb.countPendingTimelogsForSite(siteId)
        : 0;
    pendingSyncLog(
      'flushAllPending done synced=$totalSynced failed=$totalFailed remaining=$remaining',
    );
    return (synced: totalSynced, failed: totalFailed, remaining: remaining);
  }

  Future<void> _reloadScannerIfRegistered(String siteId) async {
    if (!Get.isRegistered<ScannerRegistryService>()) return;
    await Get.find<ScannerRegistryService>().reloadSiteFromLocalDb(siteId);
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

    final payloadJson = row['payload_json']?.toString() ?? '';
    if (!payloadJson.contains('"code"')) {
      pendingSyncLog('Skipping queue $id (not a time-in/out timelog payload)');
      return false;
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
      pendingSyncLog('No timelog payload for queue $queueId');
      return false;
    }

    await uploadAttendancePayload(
      siteId: siteId,
      employeeId: employeeId,
      payload: payload,
    );

    await LocalDb.markAttendanceSynced(queueId);
    pendingSyncLog('Attendance synced queueId=$queueId');
    return true;
  }

  Future<bool> _syncFingerprint({
    required int queueId,
    required String employeeId,
    required String siteId,
  }) async {
    if (employeeId.isEmpty || siteId.isEmpty) return false;

    final ok = await uploadFingerprint(
      employeeId: employeeId,
      siteId: siteId,
    );
    if (!ok) return false;

    await LocalDb.markAttendanceSynced(queueId);
    await _reloadScannerIfRegistered(siteId);
    pendingSyncLog('Fingerprint synced queueId=$queueId');
    return true;
  }
}
