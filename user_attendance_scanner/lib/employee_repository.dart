import 'employee_model.dart';

abstract class EmployeeRepository {
  /// Get all employees for a specific site
  Future<List<Employee>> getEmployeesForSite(String siteId);
  
  /// Save employee to local database
  Future<void> saveEmployee(Employee employee);
  
  /// Update employee information
  Future<void> updateEmployee(Employee employee);
  
  /// Delete employee by ID and site
  Future<void> deleteEmployee(String employeeId, String siteId);
  
  /// Get employee by ID
  Future<Employee?> getEmployeeById(String employeeId, String siteId);
  
  /// Sync employees from API to local database
  Future<List<Employee>> syncEmployeesFromApi(String siteId);
  
  /// Get employee count for site
  Future<int> getEmployeeCountForSite(String siteId);
  
  /// Clear employees for a specific site
  Future<void> clearEmployeesForSite(String siteId);
  
  /// Check if employee exists
  Future<bool> employeeExists(String employeeId, String siteId);
}