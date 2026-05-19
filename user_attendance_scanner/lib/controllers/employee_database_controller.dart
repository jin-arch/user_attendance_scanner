import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/local_db.dart';

class EmployeeDatabaseController extends GetxController {
  final RxList<Map<String, dynamic>> employeesWithPending =
      <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> selectedEmployeePending =
      <Map<String, dynamic>>[].obs;
  final RxString selectedEmployeeId = ''.obs;
  final RxString selectedEmployeeName = ''.obs;
  final RxBool isLoading = false.obs;
  final RxBool isUploading = false.obs;
  final RxString errorMessage = ''.obs;

  String _siteId = '';

  @override
  void onInit() {
    super.onInit();
  }

  void setSiteId(String siteId) {
    _siteId = siteId;
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

      selectedEmployeePending.assignAll(pending);

      debugPrint(
          '[EMPLOYEE_DB] Loaded ${pending.length} pending records for $employeeId');
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

      // TODO: Implement API call to upload records
      // For now, just mark as synced locally
      await LocalDb.markMultipleAttendanceSynced(ids);

      debugPrint('[EMPLOYEE_DB] Uploaded ${ids.length} records for $employeeId');

      // Reload data
      await loadPendingRecordsForEmployee(
        employeeId: employeeId,
        employeeName: selectedEmployeeName.value,
      );
      await loadEmployeesWithPendingRecords();
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

      // TODO: Implement API call to upload all records
      // For now, just mark as synced locally
      await LocalDb.markMultipleAttendanceSynced(ids);

      debugPrint('[EMPLOYEE_DB] Uploaded ${ids.length} total records');

      // Reload data
      await loadEmployeesWithPendingRecords();
      if (selectedEmployeeId.value.isNotEmpty) {
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
}
