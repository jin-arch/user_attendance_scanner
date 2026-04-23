import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/local_db.dart';

class DatabaseController extends GetxController {
  // Observable state
  final RxList<Map<String, dynamic>> employees = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = false.obs;
  final RxString searchQuery = ''.obs;
  final TextEditingController searchController = TextEditingController();
  
  // Site ID for filtering
  final String? siteId;
  
  // Callbacks for UI updates
  Function()? onEmployeesLoaded;
  Function(String)? onError;
  
  DatabaseController({this.siteId});
  
  @override
  void onInit() {
    super.onInit();
    _setupSearchListener();
    loadEmployees();
  }
  
  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }
  
  void _setupSearchListener() {
    searchController.addListener(() {
      searchQuery.value = searchController.text.toLowerCase();
    });
  }
  
  Future<void> loadEmployees() async {
    debugPrint('[DATABASE_CONTROLLER] Loading employees for siteId: $siteId');
    
    if (siteId == null || siteId!.isEmpty) {
      debugPrint('[DATABASE_CONTROLLER] No site ID provided');
      onError?.call('No site ID provided');
      employees.clear();
      return;
    }
    
    isLoading.value = true;
    try {
      final employeesData = await LocalDb.getEmployeesBySite(siteId!);
      debugPrint('[DATABASE_CONTROLLER] Loaded ${employeesData.length} employees');
      
      employees.assignAll(employeesData);
      onEmployeesLoaded?.call();
    } catch (e) {
      debugPrint('[DATABASE_CONTROLLER] Error loading employees: $e');
      onError?.call('Error loading employees: $e');
      employees.clear();
    } finally {
      isLoading.value = false;
    }
  }
  
  Future<void> refreshEmployees() async {
    await loadEmployees();
  }
  
  // Get unique employees with fingerprint count
  List<Map<String, dynamic>> get uniqueEmployees {
    // Group by employee_id to show unique employees with fingerprint count
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final emp in employees) {
      final empId = emp['employee_id'] as String;
      if (grouped.containsKey(empId)) {
        grouped[empId]!['fingerprint_count'] = (grouped[empId]!['fingerprint_count'] as int) + 1;
      } else {
        grouped[empId] = {
          'employee_id': empId,
          'employee_name': emp['employee_name'],
          'site_id': emp['site_id'],
          'fingerprint_count': 1,
        };
      }
    }
    return grouped.values.toList();
  }
  
  // Filter and search logic
  List<Map<String, dynamic>> get filteredEmployees {
    final unique = uniqueEmployees;
    if (searchQuery.value.isEmpty) return unique;
    return unique.where((emp) {
      final empId = (emp['employee_id'] ?? '').toString().toLowerCase();
      final empName = (emp['employee_name'] ?? '').toString().toLowerCase();
      return empId.contains(searchQuery.value) || empName.contains(searchQuery.value);
    }).toList();
  }
  
  void clearSearch() {
    searchController.clear();
    searchQuery.value = '';
  }
  
  // Get statistics
  Map<String, dynamic> getEmployeeStatistics() {
    final unique = uniqueEmployees;
    final stats = <String, dynamic>{
      'totalEmployees': unique.length,
      'totalFingerprints': employees.length,
      'employeesWithCompleteFingerprints': 0,
      'employeesWithIncompleteFingerprints': 0,
    };
    
    for (final emp in unique) {
      final fingerprintCount = emp['fingerprint_count'] as int;
      if (fingerprintCount >= 6) { // Assuming 6 fingerprints is complete
        stats['employeesWithCompleteFingerprints'] = (stats['employeesWithCompleteFingerprints'] as int) + 1;
      } else {
        stats['employeesWithIncompleteFingerprints'] = (stats['employeesWithIncompleteFingerprints'] as int) + 1;
      }
    }
    
    return stats;
  }
  
  // Get employee by ID
  Map<String, dynamic>? getEmployeeById(String employeeId) {
    try {
      return uniqueEmployees.firstWhere((emp) => emp['employee_id'] == employeeId);
    } catch (e) {
      return null;
    }
  }
  
  // Get all fingerprints for an employee
  List<Map<String, dynamic>> getEmployeeFingerprints(String employeeId) {
    return employees.where((emp) => emp['employee_id'] == employeeId).toList();
  }
  
  // Delete employee and all their fingerprints
  Future<bool> deleteEmployee(String employeeId) async {
    try {
      // Delete all fingerprints for this employee
      final employeeFingerprints = getEmployeeFingerprints(employeeId);
      for (final fingerprint in employeeFingerprints) {
        await LocalDb.deleteEmployee(
          employeeId,
          siteId!,
        );
      }
      
      // Delete employee photo if exists
      await LocalDb.deleteEmployeePhoto(
        employeeId,
        siteId!,
      );
      
      // Refresh the list
      await loadEmployees();
      return true;
    } catch (e) {
      onError?.call('Error deleting employee: $e');
      return false;
    }
  }
  
  // Export employees to CSV format
  String exportEmployeesToCsv() {
    final buffer = StringBuffer();
    final unique = uniqueEmployees;
    
    buffer.writeln('Employee ID,Employee Name,Site ID,Fingerprint Count');
    
    for (final emp in unique) {
      final empId = emp['employee_id'] ?? '';
      final empName = emp['employee_name'] ?? '';
      final siteId = emp['site_id'] ?? '';
      final fingerprintCount = emp['fingerprint_count'] ?? 0;
      
      buffer.writeln('$empId,$empName,$siteId,$fingerprintCount');
    }
    
    return buffer.toString();
  }
  
  // Get employees with incomplete fingerprints
  List<Map<String, dynamic>> getEmployeesWithIncompleteFingerprints() {
    return uniqueEmployees.where((emp) {
      final fingerprintCount = emp['fingerprint_count'] as int;
      return fingerprintCount < 6;
    }).toList();
  }
  
  // Get employees with no fingerprints
  List<Map<String, dynamic>> getEmployeesWithNoFingerprints() {
    return uniqueEmployees.where((emp) {
      final fingerprintCount = emp['fingerprint_count'] as int;
      return fingerprintCount == 0;
    }).toList();
  }
  
  // Search employees by multiple criteria
  List<Map<String, dynamic>> searchEmployees({
    String? employeeId,
    String? employeeName,
    int? minFingerprintCount,
    int? maxFingerprintCount,
  }) {
    var results = uniqueEmployees;
    
    if (employeeId != null && employeeId.isNotEmpty) {
      results = results.where((emp) {
        final empId = (emp['employee_id'] ?? '').toString().toLowerCase();
        return empId.contains(employeeId.toLowerCase());
      }).toList();
    }
    
    if (employeeName != null && employeeName.isNotEmpty) {
      results = results.where((emp) {
        final empName = (emp['employee_name'] ?? '').toString().toLowerCase();
        return empName.contains(employeeName.toLowerCase());
      }).toList();
    }
    
    if (minFingerprintCount != null) {
      results = results.where((emp) {
        final fingerprintCount = emp['fingerprint_count'] as int;
        return fingerprintCount >= minFingerprintCount;
      }).toList();
    }
    
    if (maxFingerprintCount != null) {
      results = results.where((emp) {
        final fingerprintCount = emp['fingerprint_count'] as int;
        return fingerprintCount <= maxFingerprintCount;
      }).toList();
    }
    
    return results;
  }
}
