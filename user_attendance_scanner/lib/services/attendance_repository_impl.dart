import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/attendance_model.dart';
import 'attendance_repository.dart';
import '../services/local_db.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  @override
  Future<void> saveAttendance(Attendance attendance) async {
    try {
      await LocalDb.insertAttendanceQueue(
        employeeId: attendance.employeeId,
        employeeName: attendance.employeeName,
        siteId: attendance.siteId,
        attendanceType: attendance.type.displayName,
        timestamp: attendance.timestamp,
      );

      debugPrint(
        '[ATTENDANCE_QUEUE] queued type=${attendance.type.displayName} employee=${attendance.employeeName}(${attendance.employeeId}) '
        'site=${attendance.siteId} ts=${attendance.timestamp.toIso8601String()}',
      );
    } catch (e) {
      throw Exception('Failed to save attendance: $e');
    }
  }

  @override
  Future<List<Attendance>> getAttendanceLogsForSite(String siteId, {
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      final rows = await LocalDb.getAttendanceLogsForSite(siteId);
      return rows.map((row) => _parseAttendanceFromLog(row, siteId)).toList();
    } catch (e) {
      throw Exception('Failed to get attendance logs: $e');
    }
  }

  @override
  Future<List<Attendance>> getAttendanceLogsForEmployee(
    String employeeId, 
    String siteId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final allLogs = await getAttendanceLogsForSite(siteId);
      return allLogs.where((log) => log.employeeId == employeeId).toList();
    } catch (e) {
      throw Exception('Failed to get employee attendance logs: $e');
    }
  }

  @override
  Future<List<Attendance>> getPendingAttendance() async {
    try {
      final rows = await LocalDb.getPendingAttendanceQueue();
      return rows.map((row) => Attendance.fromJson(row)).toList();
    } catch (e) {
      throw Exception('Failed to get pending attendance: $e');
    }
  }

  @override
  Future<void> markAttendanceAsSynced(List<Attendance> attendanceList) async {
    try {
      // Mark attendance records as synced by updating the queue
      final pendingRows = await LocalDb.getPendingAttendanceQueue();
      
      for (final attendance in attendanceList) {
        // Find matching pending record and mark as synced
        for (final row in pendingRows) {
          final rowEmployeeId = row['employee_id']?.toString() ?? '';
          final rowTime = row['attendance_time']?.toString() ?? '';
          
          if (rowEmployeeId == attendance.employeeId && 
              rowTime == attendance.timestamp.toIso8601String()) {
            await LocalDb.markAttendanceSynced(row['id'] as int);
            debugPrint('[ATTENDANCE_REPO] Marked attendance as synced: ${attendance.employeeId} at ${attendance.timestamp}');
            break;
          }
        }
      }
    } catch (e) {
      throw Exception('Failed to mark attendance as synced: $e');
    }
  }

  @override
  Future<void> syncPendingAttendanceToApi() async {
    try {
      // Get pending attendance records from queue
      final pendingAttendance = await getPendingAttendance();
      
      if (pendingAttendance.isEmpty) {
        debugPrint('[ATTENDANCE_REPO] No pending attendance to sync');
        return;
      }
      
      debugPrint('[ATTENDANCE_REPO] Syncing ${pendingAttendance.length} pending attendance records to API');
      
      // Sync each pending attendance record to API
      for (final attendance in pendingAttendance) {
        try {
          // Submit attendance to API using LocalDb methods
          final timestamp = attendance.timestamp;
          final timeLogDate = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
          final timeLog = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
          
          // Determine if it's time in or time out
          final isTimeIn = attendance.type.displayName.toLowerCase().contains('in');
          
          if (isTimeIn) {
            await LocalDb.submitAttendanceTimeIn(
              passedID: null,
              timeLogId: DateTime.now().millisecondsSinceEpoch.toString(),
              remarks: 'Biometric Attendance',
              timeLog: timeLogDate,
              timeInMorning: timeLog,
              timeInAfternoon: null,
              code: attendance.employeeId,
            );
          } else {
            await LocalDb.submitAttendanceTimeOut(
              passedID: null,
              timeLogId: DateTime.now().millisecondsSinceEpoch.toString(),
              remarks: 'Biometric Attendance',
              timeLog: timeLogDate,
              timeOutMorning: timeLog,
              timeOutAfternoon: null,
              code: attendance.employeeId,
            );
          }
          
          // Mark as synced
          await markAttendanceAsSynced([attendance]);
          debugPrint('[ATTENDANCE_REPO] Successfully synced attendance for ${attendance.employeeId}');
        } catch (e) {
          debugPrint('[ATTENDANCE_REPO] Failed to sync attendance for ${attendance.employeeId}: $e');
          // Continue with next record even if one fails
        }
      }
      
      debugPrint('[ATTENDANCE_REPO] Completed syncing pending attendance');
    } catch (e) {
      throw Exception('Failed to sync pending attendance to API: $e');
    }
  }

  @override
  Future<Attendance?> getLatestAttendanceForEmployee(String employeeId, String siteId) async {
    try {
      final employeeLogs = await getAttendanceLogsForEmployee(employeeId, siteId);
      if (employeeLogs.isEmpty) return null;
      
      // Sort by timestamp descending and get the latest
      employeeLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return employeeLogs.first;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> clearAttendanceForSite(String siteId) async {
    try {
      // This would require a new method in LocalDb
      // For now, no-op
    } catch (e) {
      throw Exception('Failed to clear attendance for site: $e');
    }
  }

  @override
  Future<int> getAttendanceCountForSite(String siteId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final logs = await getAttendanceLogsForSite(siteId);
      
      if (startDate != null || endDate != null) {
        final filteredLogs = logs.where((log) {
          if (startDate != null && log.timestamp.isBefore(startDate)) {
            return false;
          }
          if (endDate != null && log.timestamp.isAfter(endDate)) {
            return false;
          }
          return true;
        }).toList();
        return filteredLogs.length;
      }
      
      return logs.length;
    } catch (e) {
      return 0;
    }
  }

  Attendance _parseAttendanceFromLog(Map<String, dynamic> row, String siteId) {
    // Parse attendance from the timelog_cache format
    final rawJson = row['raw_json'];
    final Map<String, dynamic> json = rawJson is String 
        ? jsonDecode(rawJson) 
        : rawJson as Map<String, dynamic>;
    
    // Extract attendance type from the JSON structure
    AttendanceType? type;
    if (json['timeInMorning'] != null) {
      type = AttendanceType.timeInMorning;
    } else if (json['timeOutMorning'] != null) {
      type = AttendanceType.timeOutMorning;
    } else if (json['timeInAfternoon'] != null) {
      type = AttendanceType.timeInAfternoon;
    } else if (json['timeOutAfternoon'] != null) {
      type = AttendanceType.timeOutAfternoon;
    }
    
    return Attendance(
      employeeId: row['employee_id']?.toString() ?? '',
      employeeName: json['name']?.toString() ?? '',
      siteId: siteId,
      timestamp: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
      type: type ?? AttendanceType.timeInMorning,
      synced: (row['synced'] ?? 0) == 1,
    );
  }
}
