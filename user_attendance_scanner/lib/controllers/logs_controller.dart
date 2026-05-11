import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../services/local_db.dart';
import '../models/employee_model.dart';
import '../services/device_service.dart';
import '../services/employee_repository.dart';

class LogsController extends GetxController {
  // Dependencies
  late final DeviceService _deviceService;
  late final EmployeeRepository _employeeRepository;

  // API Configuration
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';

  // Observable state
  final RxList<Map<String, dynamic>> logs = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = false.obs;
  final RxString searchQuery = ''.obs;
  final RxString selectedFilter = 'All'.obs;
  final RxString statusMessage = ''.obs;
  final RxString lastDbSyncLabel = ''.obs;
  final RxString errorMessage = ''.obs;
  final TextEditingController searchController = TextEditingController();

  // Authentication state
  final RxBool isAuthenticated = false.obs;
  final Rx<Employee?> authenticatedEmployee = Rx<Employee?>(null);
  final RxBool isScanning = false.obs;
  final RxBool isDeviceConnected = false.obs;

  // Employee ID search and cooldown
  final RxString employeeIdSearch = ''.obs;
  final RxBool isCooldownActive = false.obs;
  final RxInt cooldownSeconds = 0.obs;
  final RxBool showTimeLogs = true.obs;

  // Cooldown state - tracks when each log entry's times should be hidden
  final RxMap<String, DateTime> logCooldownMap = RxMap<String, DateTime>({});
  final RxInt activeCooldownCount = 0.obs;
  static const int _cooldownDuration = 60; // 1 minute cooldown
  Timer? _cooldownCheckTimer;

  // Site ID for filtering
  final String? siteId;

  LogsController({this.siteId});
  
  @override
  void onInit() {
    super.onInit();
    _deviceService = Get.find<DeviceService>();
    _employeeRepository = Get.find<EmployeeRepository>();
    _setupSearchListener();
    _initializeDevice();
    // Start automatic fingerprint detection when page loads
    _startAutomaticDetection();
  }
  
  @override
  void onClose() {
    searchController.dispose();
    _cooldownCheckTimer?.cancel();
    super.onClose();
  }
  
  void _setupSearchListener() {
    searchController.addListener(() {
      searchQuery.value = searchController.text.toLowerCase();
    });
  }

  /// Start cooldown timer for a specific log entry
  void startLogCooldown(String logKey) {
    final now = DateTime.now();
    logCooldownMap[logKey] = now.add(const Duration(seconds: _cooldownDuration));
    activeCooldownCount.value = logCooldownMap.length;

    // Start periodic check if not already running
    if (_cooldownCheckTimer == null) {
      _startCooldownCheckTimer();
    }

    debugPrint('[COOLDOWN] Started 1-minute cooldown for log: $logKey');
  }

  /// Check if a log entry is in cooldown (times should be hidden)
  bool isLogInCooldown(String logKey) {
    if (!logCooldownMap.containsKey(logKey)) {
      return false;
    }

    final cooldownEnd = logCooldownMap[logKey];
    if (cooldownEnd == null) {
      return false;
    }

    final isInCooldown = DateTime.now().isBefore(cooldownEnd);
    if (!isInCooldown) {
      // Cooldown expired, remove from map
      logCooldownMap.remove(logKey);
      activeCooldownCount.value = logCooldownMap.length;
    }

    return isInCooldown;
  }

  /// Get remaining cooldown time in seconds
  int getRemainingCooldown(String logKey) {
    if (!logCooldownMap.containsKey(logKey)) {
      return 0;
    }

    final cooldownEnd = logCooldownMap[logKey];
    if (cooldownEnd == null) {
      return 0;
    }

    final remaining = cooldownEnd.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Start periodic timer to check and update cooldowns
  void _startCooldownCheckTimer() {
    _cooldownCheckTimer?.cancel();
    _cooldownCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Check if any cooldowns have expired
      final expiredKeys = <String>[];
      for (final entry in logCooldownMap.entries) {
        if (DateTime.now().isAfter(entry.value)) {
          expiredKeys.add(entry.key);
        }
      }

      // Remove expired cooldowns
      if (expiredKeys.isNotEmpty) {
        for (final key in expiredKeys) {
          logCooldownMap.remove(key);
        }
        activeCooldownCount.value = logCooldownMap.length;

        // Stop timer if no more active cooldowns
        if (logCooldownMap.isEmpty) {
          _cooldownCheckTimer?.cancel();
          _cooldownCheckTimer = null;
          debugPrint('[COOLDOWN] All cooldowns expired');
        }
      }
    });
  }

  /// Format cooldown display (e.g., "45 seconds remaining")
  String formatCooldownTime(String logKey) {
    final remaining = getRemainingCooldown(logKey);
    if (remaining <= 0) {
      return '';
    }
    return '$remaining${remaining == 1 ? ' second' : ' seconds'} remaining';
  }

  
  Future<void> _initializeDevice() async {
    try {
      isDeviceConnected.value = await _deviceService.connect();
      if (isDeviceConnected.value) {
        debugPrint('[LOGS_CONTROLLER] Device connected successfully');
      }
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Device connection failed: $e');
      isDeviceConnected.value = false;
    }
  }

  Future<void> _startAutomaticDetection() async {
    // Wait for device initialization
    await Future.delayed(const Duration(milliseconds: 1000));
    
    if (siteId != null && siteId!.isNotEmpty) {
      // Fetch time logs from API and save to local database
      await fetchAndSaveTimeLogsFromApi();
      
      // Try to authenticate using local database data
      await _authenticateWithLocalData();
    } else {
      errorMessage.value = 'No site selected for authentication';
    }
  }

  Future<void> _authenticateWithLocalData() async {
    try {
      setStatus('Ready to authenticate - enter employee ID');

      // Don't automatically load all logs - wait for user authentication
      // User must either scan fingerprint or input employee ID
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Authentication error: $e');
      errorMessage.value = 'Authentication failed: $e';
    }
  }

  /// Check if employee has enrolled thumb mark
  Future<bool> _employeeHasThumbMark(String employeeId) async {
    try {
      final employees = await _employeeRepository.getEmployeesForSite(siteId!);
      final employee = employees.firstWhere(
        (e) => e.id == employeeId,
        orElse: () => Employee(id: '', name: '', siteId: siteId!),
      );
      return employee.fingerTemplate != null && employee.fingerTemplate!.isNotEmpty;
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Error checking thumb mark: $e');
      return false;
    }
  }

  /// Authenticate by Employee ID - show only that employee's logs
  Future<void> authenticateByEmployeeId(String employeeId) async {
    if (employeeId.trim().isEmpty) {
      errorMessage.value = 'Please enter a valid employee ID';
      return;
    }

    try {
      isLoading.value = true;
      errorMessage.value = '';

      debugPrint('[AUTH] ===== EMPLOYEE AUTHENTICATION START =====');
      debugPrint('[AUTH] Employee ID: $employeeId');
      debugPrint('[AUTH] Site ID: $siteId');

      if (siteId == null || siteId!.isEmpty) {
        errorMessage.value = 'No site selected';
        debugPrint('[AUTH] ERROR: No site selected');
        return;
      }

      // Check if employee has enrolled thumb mark
      setStatus('Verifying employee biometric data...');
      debugPrint('[AUTH] Checking if employee has thumb mark...');
      final hasThumbMark = await _employeeHasThumbMark(employeeId.trim());
      debugPrint('[AUTH] Has thumb mark: $hasThumbMark');

      if (!hasThumbMark) {
        errorMessage.value = 'Employee ID $employeeId has no enrolled thumb mark. Please enroll first.';
        authenticatedEmployee.value = null;
        isAuthenticated.value = false;
        logs.clear();
        setStatus('Employee not enrolled');
        debugPrint('[AUTH] ERROR: Employee not enrolled');
        return;
      }

      // Get employee name from API or local DB
      debugPrint('[AUTH] Fetching employee name...');
      String empName = 'Employee $employeeId';

      try {
        // Try to get from API first
        final apiResponse = await http.get(
          Uri.parse(
            'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/employee/perSite?siteID=$siteId',
          ),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Basic ${base64Encode(utf8.encode('$_apiUsername:$_apiPassword'))}',
          },
        ).timeout(const Duration(seconds: 10));

        if (apiResponse.statusCode == 200) {
          final data = json.decode(apiResponse.body);
          List<dynamic> employees = [];

          if (data is List) {
            employees = data;
          } else if (data is Map && data['data'] is List) {
            employees = data['data'];
          }

          for (final emp in employees) {
            final id = emp['employee_id']?.toString() ?? emp['id']?.toString() ?? '';
            if (id == employeeId.trim()) {
              empName = emp['employee_name']?.toString() ??
                       emp['name']?.toString() ??
                       'Employee $employeeId';
              debugPrint('[AUTH] Found employee name from API: $empName');
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('[AUTH] Could not fetch from API: $e');
      }

      // Set authenticated user (don't fail if no logs exist yet)
      authenticatedEmployee.value = Employee(
        id: employeeId.trim(),
        name: empName,
        siteId: siteId!,
      );
      isAuthenticated.value = true;

      debugPrint('[AUTH] ✅ Employee authenticated: $empName');
      debugPrint('[AUTH] ===== EMPLOYEE AUTHENTICATION END =====');

      // Now load logs (will fetch from API if needed)
      setStatus('Loading employee time logs...');
      await loadLogs();

    } catch (e) {
      debugPrint('[AUTH] ERROR: $e');
      errorMessage.value = 'Authentication error: $e';
      authenticatedEmployee.value = null;
      isAuthenticated.value = false;
      logs.clear();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> startFingerprintAuthentication() async {
    if (!isDeviceConnected.value) {
      errorMessage.value = 'Fingerprint scanner not connected';
      return;
    }
    
    try {
      isScanning.value = true;
      errorMessage.value = '';
      
      // Load employees for the site
      if (siteId != null && siteId!.isNotEmpty) {
        await _loadEmployeesForSite();
      }
      
      // Start scanning
      await _deviceService.startScanningMode();
      await _performFingerprintScan();
    } catch (e) {
      errorMessage.value = 'Authentication failed: $e';
    } finally {
      isScanning.value = false;
    }
  }
  
  Future<void> _loadEmployeesForSite() async {
    try {
      // This would load employees for the current site
      // For now, we'll assume employees are loaded elsewhere
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Failed to load employees: $e');
    }
  }
  
    
  Future<void> _performFingerprintScan() async {
    try {
      setStatus('Place finger on scanner...');
      final template = await _deviceService.scanFingerprint();
      if (template != null) {
        setStatus('Processing fingerprint...');
        // Get all employees for matching
        final employees = await _employeeRepository.getEmployeesForSite(siteId!);
        
        final scanResult = await _deviceService.matchFingerprint(template, employees);
        
        if (scanResult.isSuccess && scanResult.employee != null) {
          authenticatedEmployee.value = scanResult.employee;
          isAuthenticated.value = true;
          setStatus('Welcome, ${scanResult.employee!.name}! Loading your time logs...');
          
          // Get logs from local database for this specific employee (same as Employee ID auth)
          final employeeLogs = await LocalDb.getAttendanceLogsForEmployee(
            scanResult.employee!.id,
            siteId!,
          );
          
          if (employeeLogs.isEmpty) {
            errorMessage.value = 'No time logs found for authenticated employee';
            logs.clear();
            setStatus('No time logs found');
          } else {
            // Show only this employee's logs
            logs.assignAll(employeeLogs);
            setStatus('Showing time logs for ${scanResult.employee!.name}');
            debugPrint('[LOGS_CONTROLLER] Fingerprint authenticated: ${scanResult.employee!.id} - Found ${employeeLogs.length} logs');
          }
        } else {
          errorMessage.value = scanResult.errorMessage ?? 'Fingerprint not recognized';
          setStatus('Authentication failed - try again');
        }
      } else {
        errorMessage.value = 'No fingerprint detected';
        setStatus('No fingerprint detected - try again');
      }
    } catch (e) {
      errorMessage.value = 'Scanning error: $e';
      setStatus('Scanning error - try again');
    }
  }
  
  Future<void> loadLogs() async {
    if (!isAuthenticated.value) {
      debugPrint('[LOGS_CONTROLLER] User not authenticated, skipping log load');
      return;
    }

    debugPrint('[LOGS_CONTROLLER] ===== LOAD LOGS START =====');
    debugPrint('[LOGS_CONTROLLER] SiteId: $siteId');
    debugPrint('[LOGS_CONTROLLER] Authenticated Employee: ${authenticatedEmployee.value?.id} - ${authenticatedEmployee.value?.name}');

    if (siteId == null || siteId!.isEmpty) {
      debugPrint('[LOGS_CONTROLLER] No site ID provided');
      errorMessage.value = 'No site selected';
      logs.clear();
      return;
    }

    errorMessage.value = '';
    isLoading.value = true;
    try {
      // Try to fetch from API first
      debugPrint('[LOGS_CONTROLLER] Attempting to fetch from API...');
      final apiLogs = await _fetchLogsFromApi(siteId!);
      debugPrint('[LOGS_CONTROLLER] API returned ${apiLogs.length} logs');

      final filteredApiLogs = _filterLogsByEmployee(apiLogs);
      debugPrint('[LOGS_CONTROLLER] After filtering: ${filteredApiLogs.length} logs for employee ${authenticatedEmployee.value?.id}');

      if (filteredApiLogs.isNotEmpty) {
        logs.assignAll(filteredApiLogs);
        debugPrint('[LOGS_CONTROLLER] ✅ Loaded ${filteredApiLogs.length} logs from API');
        return;
      }

      // Fallback to local database if API fails or returns no data
      debugPrint('[LOGS_CONTROLLER] API returned no data, trying local database...');
      final logsData = await LocalDb.getAttendanceLogsForSite(siteId!);
      debugPrint('[LOGS_CONTROLLER] Local DB returned ${logsData.length} attendance logs for site $siteId');

      final filteredLogs = _filterLogsByEmployee(logsData);
      debugPrint('[LOGS_CONTROLLER] After filtering: ${filteredLogs.length} logs for employee ${authenticatedEmployee.value?.id}');

      if (filteredLogs.isNotEmpty) {
        logs.assignAll(filteredLogs);
        debugPrint('[LOGS_CONTROLLER] ✅ Loaded ${filteredLogs.length} logs from local database');
      } else {
        debugPrint('[LOGS_CONTROLLER] ⚠️ No logs found for employee ${authenticatedEmployee.value?.id}');
        debugPrint('[LOGS_CONTROLLER] Available logs in local DB for this site:');
        for (int i = 0; i < logsData.take(10).length; i++) {
          debugPrint('[LOGS_CONTROLLER]   Log $i: ${logsData[i]}');
        }
      }

      logs.assignAll(filteredLogs);
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Error loading logs: $e');
      errorMessage.value = 'Error loading logs: $e';

      // Try fallback to local database on error
      try {
        final logsData = await LocalDb.getAttendanceLogsForSite(siteId!);
        final filteredLogs = _filterLogsByEmployee(logsData);
        logs.assignAll(filteredLogs);
        debugPrint('[LOGS_CONTROLLER] ✅ Loaded ${filteredLogs.length} logs from local database (error fallback)');
      } catch (dbError) {
        debugPrint('[LOGS_CONTROLLER] Fallback also failed: $dbError');
        logs.clear();
      }
    } finally {
      isLoading.value = false;
      debugPrint('[LOGS_CONTROLLER] ===== LOAD LOGS END =====');
    }
  }

  List<Map<String, dynamic>> _filterLogsByEmployee(List<Map<String, dynamic>> allLogs) {
    if (authenticatedEmployee.value == null) {
      debugPrint('[FILTER] No authenticated employee');
      return [];
    }

    final employeeId = authenticatedEmployee.value!.id;
    debugPrint('[FILTER] Filtering ${allLogs.length} logs for employeeId: $employeeId');

    final filtered = allLogs.where((log) {
      final logEmployeeId = (log['employee_id'] ?? log['employeeId'] ?? '').toString();
      final match = logEmployeeId == employeeId;
      if (!match) {
        debugPrint('[FILTER] Log employee_id "$logEmployeeId" ≠ search id "$employeeId"');
      }
      return match;
    }).toList();

    debugPrint('[FILTER] Filtered result: ${filtered.length} matching logs');
    return filtered;
  }

  /// Logout current user - clear all logs and authentication
  void logout() {
    isAuthenticated.value = false;
    authenticatedEmployee.value = null;
    logs.clear();
    searchController.clear();
    searchQuery.value = '';
    errorMessage.value = '';
    logCooldownMap.clear();
    activeCooldownCount.value = 0;
    setStatus('Logged out - enter employee ID or scan fingerprint');
    debugPrint('[LOGS_CONTROLLER] User logged out');
  }

  Future<List<Map<String, dynamic>>> _fetchLogsFromApi(String siteId) async {
    try {
      final url = Uri.parse(
        'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/timelog/lastweek/perSite?siteID=$siteId',
      );
      debugPrint('[LOGS_CONTROLLER] ===== START API FETCH =====');
      debugPrint('[LOGS_CONTROLLER] URL: $url');

      // Add authentication headers (same as home page controller)
      final headers = {
        'Accept': 'application/json',
        'User-Agent': 'FAST-Attendance/1.0',
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_apiUsername:$_apiPassword'))}',
      };
      debugPrint('[LOGS_CONTROLLER] Headers: $headers');

      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Request timeout after 15 seconds');
        },
      );

      debugPrint('[LOGS_CONTROLLER] Response Status: ${response.statusCode}');
      debugPrint('[LOGS_CONTROLLER] Response Body Length: ${response.body.length}');

      if (response.body.length < 500) {
        debugPrint('[LOGS_CONTROLLER] Response Body: ${response.body}');
      } else {
        debugPrint('[LOGS_CONTROLLER] Response Body (first 500 chars): ${response.body.substring(0, 500)}');
      }

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          debugPrint('[LOGS_CONTROLLER] WARNING: Empty response body');
          return [];
        }

        final data = json.decode(response.body);
        debugPrint('[LOGS_CONTROLLER] Decoded JSON type: ${data.runtimeType}');

        // Handle different response formats
        List<dynamic> items = [];

        if (data is List) {
          items = data;
          debugPrint('[LOGS_CONTROLLER] Response is List with ${items.length} items');
        } else if (data is Map) {
          // Try common wrapper keys
          items = data['data'] ??
              data['timelog'] ??
              data['timelogs'] ??
              data['records'] ??
              data['result'] ??
              data['results'] ??
              [];
          debugPrint('[LOGS_CONTROLLER] Response is Map, extracted ${items.length} items');
        }

        if (items.isEmpty) {
          debugPrint('[LOGS_CONTROLLER] WARNING: No items found in response');
          debugPrint('[LOGS_CONTROLLER] Full response: $data');
          return [];
        }

        // Parse items - try multiple field name variations
        final result = items.map<Map<String, dynamic>>((item) {
          if (item is! Map) return {};

          return {
            'employee_id': (item['employee_id'] ??
                           item['employeeID'] ??
                           item['EMPLOYEEID'] ??
                           item['companyID'] ??
                           '')?.toString() ?? '',
            'employee_name': (item['employee_name'] ??
                             item['employeeName'] ??
                             item['EMPLOYEE_NAME'] ??
                             item['name'] ??
                             item['employee'] ??
                             item['fullName'] ??
                             item['full_name'] ??
                             'Unknown')?.toString() ?? 'Unknown',
            'type': (item['type'] ??
                    item['attendance_type'] ??
                    '')?.toString() ?? '',
            'time_only': (item['time_only'] ??
                         item['timeOnly'] ??
                         item['time'] ??
                         '')?.toString() ?? '',
            'timestamp': (item['timestamp'] ??
                         item['timelog'] ??
                         item['timeLogDate'] ??
                         '')?.toString() ?? '',
            'period': (item['period'] ??
                      item['periodType'] ??
                      '')?.toString() ?? '',
            // Also store original data for debugging
            'raw_data': item,
          };
        }).where((item) => item['employee_id']!.isNotEmpty).toList();

        debugPrint('[LOGS_CONTROLLER] Parsed ${result.length} valid items');
        for (int i = 0; i < result.take(3).length; i++) {
          debugPrint('[LOGS_CONTROLLER] Item $i: ${result[i]}');
        }

        return result;
      } else {
        debugPrint('[LOGS_CONTROLLER] ERROR: HTTP ${response.statusCode}');
        debugPrint('[LOGS_CONTROLLER] Response: ${response.body}');
        return [];
      }
    } catch (e, stackTrace) {
      debugPrint('[LOGS_CONTROLLER] API fetch error: $e');
      debugPrint('[LOGS_CONTROLLER] Stack trace: $stackTrace');
      return [];
    }
  }
  
  Future<void> refreshLogs() async {
    await loadLogs();
  }
  
  // Filter and search logic
  List<Map<String, dynamic>> get filteredLogs {
    var filtered = logs.toList();
    
    // Apply type filter
    if (selectedFilter.value != 'All') {
      filtered = filtered.where((log) {
        final type = (log['type'] ?? '').toString().toLowerCase();
        return type.contains(selectedFilter.value.toLowerCase());
      }).toList();
    }
    
    // Apply search filter
    if (searchQuery.value.isNotEmpty) {
      filtered = filtered.where((log) {
        final empId = (log['employee_id'] ?? '').toString().toLowerCase();
        final empName = (log['employee_name'] ?? '').toString().toLowerCase();
        return empId.contains(searchQuery.value) || empName.contains(searchQuery.value);
      }).toList();
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

  // API and Database methods
  Future<void> fetchAndSaveTimeLogsFromApi() async {
    if (siteId == null || siteId!.isEmpty) {
      errorMessage.value = 'No site selected';
      return;
    }

    try {
      isLoading.value = true;
      setStatus('Fetching time logs from server...');
      
      // Fetch all time logs from API
      final apiLogs = await _fetchLogsFromApi(siteId!);
      
      if (apiLogs.isNotEmpty) {
        setStatus('Saving ${apiLogs.length} time logs to local database...');
        
        // Save to local database
        await LocalDb.saveAttendanceLogsForSite(siteId!, apiLogs);
        
        setStatus('Successfully saved ${apiLogs.length} time logs to local database');
        debugPrint('[LOGS_CONTROLLER] Saved ${apiLogs.length} logs to local database');
      } else {
        setStatus('No time logs found on server');
      }
    } catch (e) {
      errorMessage.value = 'Failed to fetch time logs: $e';
      setStatus('Error fetching time logs from server');
    } finally {
      isLoading.value = false;
    }
  }

  // Utility methods
  void setStatus(String status) {
    statusMessage.value = status;
  }
}
