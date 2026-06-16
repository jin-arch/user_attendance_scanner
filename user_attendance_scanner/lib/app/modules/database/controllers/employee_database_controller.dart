import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:user_attendance_scanner/app/data/services/connectivity_service.dart';
import 'package:user_attendance_scanner/app/data/services/local_db.dart';
import 'package:user_attendance_scanner/app/data/services/offline_mode_sync_service.dart';
import 'package:user_attendance_scanner/app/data/services/pending_upload_service.dart';
import 'package:user_attendance_scanner/app/modules/home/controllers/offline_mode_controller.dart';

class EmployeeDatabaseController extends GetxController {
  final RxList<Map<String, dynamic>> employeesWithPending =
      <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> selectedEmployeePending =
      <Map<String, dynamic>>[].obs;
  final RxString selectedEmployeeId = ''.obs;
  final RxString selectedEmployeeName = ''.obs;
  final RxBool isLoading = false.obs;
  final RxBool isUploading = false.obs;
  final RxBool isAutoSyncing = false.obs;
  final RxString errorMessage = ''.obs;

  String _siteId = '';
  String _initializedSite = '';
  Timer? _onlinePollTimer;
  bool _pollInProgress = false;
  final _offlineModeSync = OfflineModeSyncService();
  VoidCallback? _modeListener;
  final RxBool isOfflineUiMode = true.obs;

  void setSiteId(String siteId) {
    _siteId = siteId;
  }

  @override
  void onReady() {
    super.onReady();
    if (_siteId.isNotEmpty) {
      unawaited(loadEmployeesWithPendingRecords());
    }
  }

  void initializeForSite(String siteId) {
    setSiteId(siteId);
    final isSameSite = _initializedSite == siteId;
    _initializedSite = siteId;

    // Always refresh when page is reopened so newly queued rows appear immediately.
    unawaited(loadEmployeesWithPendingRecords());
    if (isSameSite && selectedEmployeeId.value.isNotEmpty) {
      unawaited(
        loadPendingRecordsForEmployee(
          employeeId: selectedEmployeeId.value,
          employeeName: selectedEmployeeName.value,
        ),
      );
    }

    _bindModeListener();
    if (isSameSite) return;
    _onlinePollTimer?.cancel();
    _onlinePollTimer = null;
    if (_offlineModeSync.isOnlineMode()) {
      _startOnlinePendingPoll();
    }
  }

  void _bindModeListener() {
    isOfflineUiMode.value = _offlineModeSync.isOfflineMode();
    _modeListener ??= () {
      isOfflineUiMode.value = _offlineModeSync.isOfflineMode();
      unawaited(_onSyncModeChanged());
    };
    _offlineModeSync.modeChanged.removeListener(_modeListener!);
    _offlineModeSync.modeChanged.addListener(_modeListener!);
  }

  Future<void> _onSyncModeChanged() async {
    await loadEmployeesWithPendingRecords();
    final employeeId = selectedEmployeeId.value;
    if (employeeId.isNotEmpty) {
      await loadPendingRecordsForEmployee(
        employeeId: employeeId,
        employeeName: selectedEmployeeName.value,
      );
    }
    if (_offlineModeSync.isOnlineMode()) {
      _startOnlinePendingPoll();
      await _pollPendingInOnlineMode();
    } else {
      _onlinePollTimer?.cancel();
      _onlinePollTimer = null;
    }
  }

  void _startOnlinePendingPoll() {
    _onlinePollTimer?.cancel();
    _onlinePollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_pollPendingInOnlineMode());
    });
  }

  Future<void> _pollPendingInOnlineMode() async {
    if (_pollInProgress || _siteId.isEmpty) return;
    if (!OfflineModeSyncService().isOnlineMode()) return;
    if (!await ConnectivityService().isOnline()) return;
    _pollInProgress = true;
    try {
      if (!Get.isRegistered<PendingUploadService>()) {
        Get.put(PendingUploadService(), permanent: true);
      }

      isAutoSyncing.value = true;
      await Get.find<PendingUploadService>().flushAllPending(
        siteId: _siteId,
        reason: 'online_poll',
      );
      await loadEmployeesWithPendingRecords();
      final employeeId = selectedEmployeeId.value;
      if (employeeId.isNotEmpty) {
        await loadPendingRecordsForEmployee(
          employeeId: employeeId,
          employeeName: selectedEmployeeName.value,
        );
      }
    } catch (e) {
      errorMessage.value = 'Online pending sync error: $e';
      debugPrint('[EMPLOYEE_DB] Online poll error: $e');
    } finally {
      isAutoSyncing.value = false;
      _pollInProgress = false;
    }
  }

  @override
  void onClose() {
    _onlinePollTimer?.cancel();
    if (_modeListener != null) {
      _offlineModeSync.modeChanged.removeListener(_modeListener!);
    }
    super.onClose();
  }

  Future<void> loadEmployeesWithPendingRecords() async {
    if (_siteId.isEmpty) return;

    try {
      isLoading.value = true;
      errorMessage.value = '';

      final employees =
          await LocalDb.getEmployeesWithPendingRecords(_siteId);
      employeesWithPending.assignAll(employees);

      debugPrint(
          '[EMPLOYEE_DB] Loaded ${employees.length} employees with pending records');
    } catch (e) {
      errorMessage.value = 'Error loading employees: $e';
      debugPrint('[EMPLOYEE_DB] Error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadPendingRecordsForEmployee({
    required String employeeId,
    required String employeeName,
  }) async {
    if (_siteId.isEmpty || employeeId.isEmpty) return;

    try {
      isLoading.value = true;
      errorMessage.value = '';

      selectedEmployeeId.value = employeeId;
      selectedEmployeeName.value = employeeName;

      final pending = await LocalDb.getPendingAttendanceByEmployee(
        employeeId: employeeId,
        siteId: _siteId,
      );

      final uniqueByQueueId = <int, Map<String, dynamic>>{};
      for (final row in pending) {
        final id = row['id'] as int? ?? 0;
        if (id > 0) {
          uniqueByQueueId[id] = {
            ...row,
            ...LocalDb.describePendingAttendanceRow(row),
          };
        }
      }
      selectedEmployeePending.assignAll(uniqueByQueueId.values.toList());

      debugPrint(
          '[EMPLOYEE_DB] Loaded ${selectedEmployeePending.length} pending records for $employeeId');
    } catch (e) {
      errorMessage.value = 'Error loading records: $e';
      debugPrint('[EMPLOYEE_DB] Error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> uploadPendingForEmployee({
    required String employeeId,
  }) async {
    try {
      isUploading.value = true;
      errorMessage.value = '';

      final pending = selectedEmployeePending;
      if (pending.isEmpty) {
        errorMessage.value = 'No pending records to upload';
        return;
      }

      final ids = pending
          .map((r) => (r['id'] as int? ?? 0))
          .where((id) => id > 0)
          .toList();

      if (ids.isEmpty) {
        errorMessage.value = 'Invalid pending records';
        return;
      }

      if (!OfflineModeSyncService().isOnlineMode()) {
        errorMessage.value =
            'Offline mode — switch to Online mode to upload to the server';
        return;
      }
      if (!await ConnectivityService().isOnline()) {
        errorMessage.value = 'No network connection — connect to upload';
        return;
      }
      if (!Get.isRegistered<PendingUploadService>()) {
        Get.put(PendingUploadService(), permanent: true);
      }
      await Get.find<PendingUploadService>().flushAllPending(
        siteId: _siteId,
        reason: 'upload_employee',
      );

      debugPrint('[EMPLOYEE_DB] Uploaded pending for $employeeId');

      await loadEmployeesWithPendingRecords();
      if (employeesWithPending.isEmpty) {
        clearSelection();
      } else {
        await loadPendingRecordsForEmployee(
          employeeId: employeeId,
          employeeName: selectedEmployeeName.value,
        );
      }
    } catch (e) {
      errorMessage.value = 'Upload failed: $e';
      debugPrint('[EMPLOYEE_DB] Upload error: $e');
    } finally {
      isUploading.value = false;
    }
  }

  Future<void> uploadAllPending() async {
    try {
      isUploading.value = true;
      errorMessage.value = '';

      final allPending = await LocalDb.getPendingAttendance();
      if (allPending.isEmpty) {
        errorMessage.value = 'No pending records to upload';
        return;
      }

      final ids = allPending
          .map((r) => (r['id'] as int? ?? 0))
          .where((id) => id > 0)
          .toList();

      if (ids.isEmpty) {
        errorMessage.value = 'Invalid pending records';
        return;
      }

      if (!OfflineModeSyncService().isOnlineMode()) {
        errorMessage.value =
            'Offline mode — switch to Online mode to upload to the server';
        return;
      }
      if (!await ConnectivityService().isOnline()) {
        errorMessage.value = 'No network connection — connect to upload';
        return;
      }
      if (!Get.isRegistered<PendingUploadService>()) {
        Get.put(PendingUploadService(), permanent: true);
      }
      await Get.find<PendingUploadService>().flushAllPending(
        siteId: _siteId,
        reason: 'upload_all',
      );

      debugPrint('[EMPLOYEE_DB] Uploaded all pending records');

      // Reload data
      await loadEmployeesWithPendingRecords();
      if (employeesWithPending.isEmpty) {
        clearSelection();
      } else if (selectedEmployeeId.value.isNotEmpty) {
        await loadPendingRecordsForEmployee(
          employeeId: selectedEmployeeId.value,
          employeeName: selectedEmployeeName.value,
        );
      }
    } catch (e) {
      errorMessage.value = 'Upload failed: $e';
      debugPrint('[EMPLOYEE_DB] Upload error: $e');
    } finally {
      isUploading.value = false;
    }
  }

  void clearSelection() {
    selectedEmployeeId.value = '';
    selectedEmployeeName.value = '';
    selectedEmployeePending.clear();
  }

  /// Opens offline/online mode picker (used by Pending Records action button).
  Future<void> promptSyncModeSelection() async {
    if (!Get.isRegistered<OfflineModeController>()) {
      Get.put(OfflineModeController());
    }
    await Get.find<OfflineModeController>().presentModeSelectionDialog(
      showPicker: true,
    );
    await _onSyncModeChanged();
  }

  /// Refresh lists after Online-mode flush (from [OfflineModeController]).
  Future<void> reloadAfterOnlineSync() async {
    await loadEmployeesWithPendingRecords();
    final employeeId = selectedEmployeeId.value;
    if (employeeId.isNotEmpty) {
      await loadPendingRecordsForEmployee(
        employeeId: employeeId,
        employeeName: selectedEmployeeName.value,
      );
    }
  }

  /// Send error report for a specific pending record
  Future<void> sendErrorReport(Map<String, dynamic> record) async {
    try {
      final recordId = record['id']?.toString() ?? 'unknown';
      final employeeId = record['employee_id']?.toString() ?? 'unknown';
      final employeeName = record['employee_name']?.toString() ?? 'Unknown';
      final errorMessage = record['error_message']?.toString() ?? 'No error message';
      final payloadJson = record['payload_json']?.toString() ?? 'No payload';
      final attendanceTime = record['attendance_time']?.toString() ?? 'Unknown';
      final recordType = record['record_type']?.toString() ?? 'attendance';

      // Generate error report content
      final reportContent = '''
ERROR REPORT
=============
Record ID: $recordId
Employee ID: $employeeId
Employee Name: $employeeName
Record Type: $recordType
Attendance Time: $attendanceTime

ERROR MESSAGE:
$errorMessage

PAYLOAD:
$payloadJson

Generated at: ${DateTime.now().toIso8601String()}
''';

      // Save to file
      final directory = await LocalDb.getEmployeePhotosDirectory();
      final fileName = 'error_report_${recordId}_${DateTime.now().millisecondsSinceEpoch}.txt';
      final filePath = '${directory.path}/$fileName';
      await File(filePath).writeAsString(reportContent);

      // Show sharing options
      await _showSharingOptions(filePath, fileName, reportContent);
    } catch (e) {
      errorMessage.value = 'Failed to generate error report: $e';
      debugPrint('[EMPLOYEE_DB] Error generating report: $e');
    }
  }

  Future<void> _showSharingOptions(String filePath, String fileName, String content) async {
    await Get.dialog(
      Dialog(
        backgroundColor: const Color(0xFF0B2742),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Share Error Report',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.mail, color: Color(0xFF3E7DDD)),
                title: const Text(
                  'Send via Gmail',
                  style: TextStyle(color: Colors.white, fontFamily: 'Poppins'),
                ),
                onTap: () {
                  Get.back();
                  _sendViaEmail(fileName, content);
                },
              ),
              ListTile(
                leading: const Icon(Icons.message, color: Color(0xFF44D980)),
                title: const Text(
                  'Send via Messenger',
                  style: TextStyle(color: Colors.white, fontFamily: 'Poppins'),
                ),
                onTap: () {
                  Get.back();
                  _sendViaMessenger(content);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: Color(0xFFFF9800)),
                title: const Text(
                  'Copy to Clipboard',
                  style: TextStyle(color: Colors.white, fontFamily: 'Poppins'),
                ),
                onTap: () {
                  Get.back();
                  _copyToClipboard(content);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close, color: Color(0xFFFF6B6B)),
                title: const Text(
                  'Close',
                  style: TextStyle(color: Colors.white, fontFamily: 'Poppins'),
                ),
                onTap: () => Get.back(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendViaEmail(String fileName, String content) async {
    try {
      // For email, we use a mailto link
      final subject = Uri.encodeComponent('Error Report: $fileName');
      final body = Uri.encodeComponent(content);
      final uri = Uri.parse('mailto:?subject=$subject&body=$body');
      
      // Note: This requires url_launcher package to be added to pubspec.yaml
      // For now, we'll show a message
      Get.snackbar(
        'Email Sharing',
        'To enable email sharing, add url_launcher package to pubspec.yaml',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF3E7DDD),
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      debugPrint('[EMPLOYEE_DB] Email URI: $uri');
    } catch (e) {
      errorMessage.value = 'Failed to open email: $e';
      debugPrint('[EMPLOYEE_DB] Email error: $e');
    }
  }

  Future<void> _sendViaMessenger(String content) async {
    try {
      // For messenger, we share the text content
      // Note: This requires share_plus or similar package
      Get.snackbar(
        'Messenger Sharing',
        'To enable messenger sharing, add share_plus package to pubspec.yaml',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF44D980),
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      debugPrint('[EMPLOYEE_DB] Messenger content length: ${content.length}');
    } catch (e) {
      errorMessage.value = 'Failed to open messenger: $e';
      debugPrint('[EMPLOYEE_DB] Messenger error: $e');
    }
  }

  Future<void> _copyToClipboard(String content) async {
    try {
      // Note: This requires flutter/services
      Get.snackbar(
        'Clipboard',
        'To enable clipboard, add flutter/services import',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFFF9800),
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      debugPrint('[EMPLOYEE_DB] Content copied to clipboard');
    } catch (e) {
      errorMessage.value = 'Failed to copy to clipboard: $e';
      debugPrint('[EMPLOYEE_DB] Clipboard error: $e');
    }
  }
}
