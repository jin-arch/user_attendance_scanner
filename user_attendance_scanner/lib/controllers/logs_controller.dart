import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/local_db.dart';

class LogsController extends GetxController {
  // Observable state
  final RxList<Map<String, dynamic>> logs = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = false.obs;
  final RxString searchQuery = ''.obs;
  final RxString selectedFilter = 'All'.obs;
  final TextEditingController searchController = TextEditingController();
  
  // Site ID for filtering
  final String? siteId;
  
  // Callbacks for UI updates
  Function()? onLogsLoaded;
  Function(String)? onError;
  
  LogsController({this.siteId});
  
  @override
  void onInit() {
    super.onInit();
    _setupSearchListener();
    loadLogs();
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
  
  Future<void> loadLogs() async {
    debugPrint('[LOGS_CONTROLLER] Loading logs for siteId: $siteId');
    
    if (siteId == null || siteId!.isEmpty) {
      debugPrint('[LOGS_CONTROLLER] No site ID provided');
      onError?.call('No site ID provided');
      logs.clear();
      return;
    }
    
    isLoading.value = true;
    try {
      // Get properly formatted attendance logs from timelog_cache
      final logsData = await LocalDb.getAttendanceLogsForSite(siteId!);
      debugPrint('[LOGS_CONTROLLER] Loaded ${logsData.length} logs');
      
      logs.assignAll(logsData);
      onLogsLoaded?.call();
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Error loading logs: $e');
      onError?.call('Error loading logs: $e');
      logs.clear();
    } finally {
      isLoading.value = false;
    }
  }
  
  Future<void> refreshLogs() async {
    await loadLogs();
  }
  
  // Filter and search logic
  List<Map<String, dynamic>> get filteredLogs {
    var filtered = logs;
    
    // Apply type filter
    if (selectedFilter.value != 'All') {
      filtered = RxList<Map<String, dynamic>>(filtered.where((log) {
        final type = (log['type'] ?? '').toString().toLowerCase();
        return type.contains(selectedFilter.value.toLowerCase());
      }).toList());
    }
    
    // Apply search filter
    if (searchQuery.value.isNotEmpty) {
      filtered = RxList<Map<String, dynamic>>(filtered.where((log) {
        final empId = (log['employee_id'] ?? '').toString().toLowerCase();
        final empName = (log['employee_name'] ?? '').toString().toLowerCase();
        return empId.contains(searchQuery.value) || empName.contains(searchQuery.value);
      }).toList());
    }
    
    return filtered;
  }
  
  void setFilter(String filter) {
    selectedFilter.value = filter;
  }
  
  void clearSearch() {
    searchController.clear();
    searchQuery.value = '';
  }
  
  String formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      final date = DateTime.parse(timestamp.toString());
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp.toString();
    }
  }
  
  // Get statistics
  Map<String, int> getLogStatistics() {
    final stats = <String, int>{
      'total': logs.length,
      'timeIn': 0,
      'timeOut': 0,
    };
    
    for (final log in logs) {
      final type = (log['type'] ?? '').toString().toLowerCase();
      if (type.contains('in')) {
        stats['timeIn'] = (stats['timeIn'] ?? 0) + 1;
      } else if (type.contains('out')) {
        stats['timeOut'] = (stats['timeOut'] ?? 0) + 1;
      }
    }
    
    return stats;
  }
  
  // Get today's logs
  List<Map<String, dynamic>> getTodayLogs() {
    final today = DateTime.now();
    final todayString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    
    return logs.where((log) {
      final timestamp = log['timestamp'];
      if (timestamp == null) return false;
      try {
        final logDate = DateTime.parse(timestamp.toString());
        final logDateString = '${logDate.year}-${logDate.month.toString().padLeft(2, '0')}-${logDate.day.toString().padLeft(2, '0')}';
        return logDateString == todayString;
      } catch (e) {
        return false;
      }
    }).toList();
  }
  
  // Get logs for a specific date range
  List<Map<String, dynamic>> getLogsForDateRange(DateTime startDate, DateTime endDate) {
    return logs.where((log) {
      final timestamp = log['timestamp'];
      if (timestamp == null) return false;
      try {
        final logDate = DateTime.parse(timestamp.toString());
        return logDate.isAfter(startDate.subtract(const Duration(days: 1))) && 
               logDate.isBefore(endDate.add(const Duration(days: 1)));
      } catch (e) {
        return false;
      }
    }).toList();
  }
  
  // Export logs to CSV format
  String exportLogsToCsv() {
    final buffer = StringBuffer();
    buffer.writeln('Employee ID,Employee Name,Type,Time,Date,Timestamp');
    
    for (final log in logs) {
      final empId = log['employee_id'] ?? '';
      final empName = log['employee_name'] ?? '';
      final type = log['type'] ?? '';
      final time = log['time_only'] ?? formatTimestamp(log['timestamp']);
      final timestamp = log['timestamp'] ?? '';
      
      buffer.writeln('$empId,$empName,$type,$time,$timestamp,$timestamp');
    }
    
    return buffer.toString();
  }
}
