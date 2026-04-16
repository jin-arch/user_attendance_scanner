import 'attendance_model.dart';

abstract class AttendanceRepository {
  /// Save attendance record to local database
  Future<void> saveAttendance(Attendance attendance);
  
  /// Get attendance logs for a specific site
  Future<List<Attendance>> getAttendanceLogsForSite(String siteId, {
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  });
  
  /// Get attendance logs for a specific employee
  Future<List<Attendance>> getAttendanceLogsForEmployee(
    String employeeId, 
    String siteId, {
    DateTime? startDate,
    DateTime? endDate,
  });
  
  /// Get pending (unsynced) attendance records
  Future<List<Attendance>> getPendingAttendance();
  
  /// Mark attendance as synced
  Future<void> markAttendanceAsSynced(List<Attendance> attendanceList);
  
  /// Sync pending attendance to API
  Future<void> syncPendingAttendanceToApi();
  
  /// Get latest attendance for employee (to determine next attendance type)
  Future<Attendance?> getLatestAttendanceForEmployee(String employeeId, String siteId);
  
  /// Clear attendance records for a site
  Future<void> clearAttendanceForSite(String siteId);
  
  /// Get attendance count for site in date range
  Future<int> getAttendanceCountForSite(String siteId, {
    DateTime? startDate,
    DateTime? endDate,
  });
}