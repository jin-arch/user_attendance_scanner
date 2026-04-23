import 'dart:typed_data';
import '../models/employee_model.dart';
import 'employee_repository.dart';
import '../services/local_db.dart';

class EmployeeRepositoryImpl implements EmployeeRepository {
  @override
  Future<List<Employee>> getEmployeesForSite(String siteId) async {
    try {
      final rows = await LocalDb.getEmployeesBySite(siteId);
      return rows.map((row) => Employee.fromJson(row)).toList();
    } catch (e) {
      throw Exception('Failed to get employees for site: $e');
    }
  }

  @override
  Future<void> saveEmployee(Employee employee) async {
    try {
      // Generate a unique fid (fingerprint ID) from employee ID
      final digits = employee.id.replaceAll(RegExp(r'\D'), '');
      final fid = int.tryParse(digits.length > 8 
          ? digits.substring(digits.length - 8) 
          : digits) ?? (employee.id.hashCode.abs() % 999997 + 1);
      
      await LocalDb.upsertEmployee(
        fid: fid,
        employeeId: employee.id,
        employeeName: employee.name,
        template: employee.fingerTemplate ?? Uint8List(0),
        siteId: employee.siteId,
      );
    } catch (e) {
      throw Exception('Failed to save employee: $e');
    }
  }

  @override
  Future<void> updateEmployee(Employee employee) async {
    await saveEmployee(employee); // LocalDb.upsertEmployee handles updates
  }

  @override
  Future<void> deleteEmployee(String employeeId, String siteId) async {
    try {
      await LocalDb.deleteEmployee(employeeId, siteId);
    } catch (e) {
      throw Exception('Failed to delete employee: $e');
    }
  }

  @override
  Future<Employee?> getEmployeeById(String employeeId, String siteId) async {
    try {
      final employees = await getEmployeesForSite(siteId);
      for (final emp in employees) {
        if (emp.id == employeeId) return emp;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<Employee>> syncEmployeesFromApi(String siteId) async {
    try {
      // This would call the existing sync logic from home_page.dart
      // For now, just return the local employees
      return await getEmployeesForSite(siteId);
    } catch (e) {
      throw Exception('Failed to sync employees from API: $e');
    }
  }

  @override
  Future<int> getEmployeeCountForSite(String siteId) async {
    try {
      return await LocalDb.getEmployeeCountBySite(siteId);
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<void> clearEmployeesForSite(String siteId) async {
    try {
      await LocalDb.pruneToSite(siteId);
    } catch (e) {
      throw Exception('Failed to clear employees for site: $e');
    }
  }

  @override
  Future<bool> employeeExists(String employeeId, String siteId) async {
    final employee = await getEmployeeById(employeeId, siteId);
    return employee != null;
  }
}
