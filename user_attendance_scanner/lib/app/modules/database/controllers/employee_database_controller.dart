import 'dart:async';

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
}
