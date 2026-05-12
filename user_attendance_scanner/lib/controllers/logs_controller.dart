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
  
  // AFK timeout tracking
  Timer? _afkTimer;
  static const int _afkTimeoutSeconds = 60; // 1 minute inactivity timeout

  @override
  void onInit() {
    super.onInit();
    _deviceService = Get.find<DeviceService>();
    _employeeRepository = Get.find<EmployeeRepository>();
    _setupSearchListener();
    _initializeDevice();
    // Start automatic fingerprint detection when page loads
    _startAutomaticDetection();
    _startAfkTimer();
  }

  @override
  void onClose() {
    searchController.dispose();
    _cooldownCheckTimer?.cancel();
    _afkTimer?.cancel();
    super.onClose();
  }
  
  void _setupSearchListener() {
    searchController.addListener(() {
      searchQuery.value = searchController.text.toLowerCase();
      _resetAfkTimer(); // Reset AFK on user input
    });
  }

  void _startAfkTimer() {
    _afkTimer?.cancel();
    _afkTimer = Timer(const Duration(seconds: _afkTimeoutSeconds), () {
      debugPrint('[LOGS_CONTROLLER] AFK timeout - returning to home');
      logout();
      // Use Get.back() to return to previous screen (usually home)
      if (Get.isDialogOpen ?? false) Get.back();
      Get.back();
    });
  }

  void _resetAfkTimer() {
    _startAfkTimer();
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
      // Data already fetched and saved to SQL when site was selected
      // Just start fingerprint scanning - no need to re-fetch from API
      debugPrint('[LOGS_CONTROLLER] Site selected: $siteId, starting fingerprint scan');
      await startFingerprintAuthentication();
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
      
      // Set status to green after successful authentication and log loading
      if (isAuthenticated.value && logs.isNotEmpty) {
        setStatus('Time logs loaded successfully');
      } else if (isAuthenticated.value) {
        setStatus('Authenticated - no time logs found');
      }

      _resetAfkTimer(); // Reset AFK timeout on successful authentication
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

  /// Start fingerprint authentication - waits for finger on scanner
  Future<void> startFingerprintAuthentication() async {
    if (!isDeviceConnected.value) {
      errorMessage.value = 'Fingerprint scanner not connected';
      setStatus('Scanner not connected');
      return;
    }

    try {
      isScanning.value = false; // Not actively scanning yet
      errorMessage.value = '';
      setStatus('Ready - place your finger on the scanner');

      // Load employees for the site
      if (siteId != null && siteId!.isNotEmpty) {
        await _loadEmployeesForSite();
      }

      // Wait for finger detection - scan only when finger is placed
      await _waitForFingerAndScan();
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Fingerprint authentication error: $e');
      errorMessage.value = 'Authentication failed: $e';
      setStatus('Authentication failed - try again');
    }
  }

  /// Wait for finger on scanner, then perform continuous scanning
  Future<void> _waitForFingerAndScan() async {
    debugPrint('[LOGS_CONTROLLER] Ready for continuous fingerprint scan...');
    setStatus('Place finger on scanner - continuous scanning active');

    try {
      // Activate scanning mode on the device
      debugPrint('[LOGS_CONTROLLER] Activating scanner...');
      await _deviceService.startScanningMode();
      debugPrint('[LOGS_CONTROLLER] Scanner activated - continuous scanning enabled');

      // Keep scanning continuously until a match is found
      while (!isAuthenticated.value && isDeviceConnected.value && siteId != null) {
        try {
          isScanning.value = true;
          await _performFingerprintScan();
          isScanning.value = false;

          // If match found, exit loop
          if (isAuthenticated.value) {
            debugPrint('[LOGS_CONTROLLER] ✓ Employee matched and authenticated');
            break;
          }

          // No match - immediately continue scanning without delay
          debugPrint('[LOGS_CONTROLLER] No match detected - continuing continuous scan...');
          // Clear any error messages and keep scanning
          if (errorMessage.value.isNotEmpty) {
            errorMessage.value = '';
          }
        } catch (e) {
          debugPrint('[LOGS_CONTROLLER] Scan attempt error: $e');
          isScanning.value = false;
          // Clear error and continue scanning immediately
          errorMessage.value = '';
          debugPrint('[LOGS_CONTROLLER] Continuing continuous scan after error...');
        }
      }
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Scan mode error: $e');
      errorMessage.value = 'Scanner error: $e';
      setStatus('Place finger on scanner...');
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
      debugPrint('[LOGS_CONTROLLER] ===== FINGERPRINT SCAN START =====');
      // DON'T change status - keep it blue
      final template = await _deviceService.scanFingerprint();
      debugPrint('[LOGS_CONTROLLER] Fingerprint template received: ${template != null}');

      if (template != null) {
        // DON'T change status - keep it blue
        debugPrint('[LOGS_CONTROLLER] Loading employees for site: $siteId');

        // Get all employees for matching
        final employees = await _employeeRepository.getEmployeesForSite(siteId!);
        debugPrint('[LOGS_CONTROLLER] Loaded ${employees.length} employees');

        debugPrint('[LOGS_CONTROLLER] Matching fingerprint...');
        final scanResult = await _deviceService.matchFingerprint(template, employees);
        debugPrint('[LOGS_CONTROLLER] Match result: success=${scanResult.isSuccess}, employee=${scanResult.employee?.id}');

        if (scanResult.isSuccess && scanResult.employee != null) {
          debugPrint('[LOGS_CONTROLLER] ✓ Fingerprint matched: ${scanResult.employee!.id} - ${scanResult.employee!.name}');

          // Auto-populate employee ID in search field
          employeeIdSearch.value = scanResult.employee!.id;
          debugPrint('[LOGS_CONTROLLER] Auto-populated employee ID: ${scanResult.employee!.id}');

          authenticatedEmployee.value = scanResult.employee;
          isAuthenticated.value = true;
          // Change status to green (ready) after successful authentication
          setStatus('Welcome, ${scanResult.employee!.name}! Time logs ready');

          debugPrint('[LOGS_CONTROLLER] Authenticating by employee ID: ${scanResult.employee!.id}');
          // Auto-load logs via authenticate function
          await authenticateByEmployeeId(scanResult.employee!.id);

          _resetAfkTimer(); // Reset AFK timeout on successful scan
          debugPrint('[LOGS_CONTROLLER] ✓ Fingerprint authentication complete');
        } else {
          debugPrint('[LOGS_CONTROLLER] ✗ Fingerprint not matched: ${scanResult.errorMessage}');
          // Don't set error message to avoid stopping continuous scan
          // errorMessage.value = scanResult.errorMessage ?? 'Fingerprint not recognized';
          // Keep status blue for failed authentication
        }
      } else {
        debugPrint('[LOGS_CONTROLLER] ✗ No fingerprint template received');
        // Don't set error message to avoid stopping continuous scan
        // errorMessage.value = 'No fingerprint detected';
        // DON'T change status - keep it blue
      }
    } catch (e, stackTrace) {
      debugPrint('[LOGS_CONTROLLER] ✗ Fingerprint scan error: $e');
      debugPrint('[LOGS_CONTROLLER] Stack trace: $stackTrace');
      // Don't set error message to avoid stopping continuous scan
      // errorMessage.value = 'Scanning error: $e';
      // DON'T change status - keep it blue
    }
    debugPrint('[LOGS_CONTROLLER] ===== FINGERPRINT SCAN END =====');
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

    if (authenticatedEmployee.value == null) {
      debugPrint('[LOGS_CONTROLLER] No authenticated employee');
      errorMessage.value = 'No authenticated employee';
      logs.clear();
      return;
    }

    errorMessage.value = '';
    isLoading.value = true;
    try {
      // First, try to get logs from local database (cached when site was selected)
      debugPrint('[LOGS_CONTROLLER] Trying local database first...');
      final localLogs = await LocalDb.getAttendanceLogsForEmployee(
        authenticatedEmployee.value!.id,
        siteId!,
      );
      debugPrint('[LOGS_CONTROLLER] Local DB returned ${localLogs.length} logs');

      if (localLogs.isNotEmpty) {
        logs.assignAll(localLogs);
        debugPrint('[LOGS_CONTROLLER] ✅ Loaded ${localLogs.length} logs from local database');
        setStatus('Loaded ${localLogs.length} time logs - ready');
        return;
      }

      // If no local logs, try fetching from API
      debugPrint('[LOGS_CONTROLLER] No local logs, trying API...');
      setStatus('Fetching time logs from server...');
      final apiLogs = await _fetchLogsFromApi(siteId!);
      debugPrint('[LOGS_CONTROLLER] API returned ${apiLogs.length} logs');

      final filteredApiLogs = _filterLogsByEmployee(apiLogs);
      debugPrint('[LOGS_CONTROLLER] After filtering: ${filteredApiLogs.length} logs for employee ${authenticatedEmployee.value?.id}');

      if (filteredApiLogs.isNotEmpty) {
        logs.assignAll(filteredApiLogs);
        debugPrint('[LOGS_CONTROLLER] ✅ Loaded ${filteredApiLogs.length} logs from API');
        setStatus('Loaded ${filteredApiLogs.length} time logs - ready');
      } else {
        debugPrint('[LOGS_CONTROLLER] ⚠️ No logs found for employee ${authenticatedEmployee.value?.id}');
        setStatus('Authenticated - no time logs found');
        logs.clear();
      }
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Error loading logs: $e');
      errorMessage.value = 'Error loading logs: $e';
      logs.clear();
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

    final employeeId = authenticatedEmployee.value!.id.trim().toLowerCase();
    debugPrint('[FILTER] Filtering ${allLogs.length} logs for employeeId: "$employeeId"');

    final filtered = allLogs.where((log) {
      final logEmployeeId = (log['employee_id'] ?? log['employeeId'] ?? log['employeeID'] ?? log['companyID'] ?? '').toString().trim().toLowerCase();
      final match = logEmployeeId == employeeId;
      if (match) {
        debugPrint('[FILTER] ✓ MATCHED: "$logEmployeeId" == "$employeeId"');
      } else {
        debugPrint('[FILTER] ✗ NO MATCH: "$logEmployeeId" != "$employeeId"');
      }
      return match;
    }).toList();

    debugPrint('[FILTER] Filtered result: ${filtered.length} matching logs out of ${allLogs.length}');
    if (filtered.isNotEmpty) {
      debugPrint('[FILTER] First log: ${filtered.first}');
    }
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

        // Log the first item to see the actual structure
        if (items.isNotEmpty && items.first is Map) {
          debugPrint('[LOGS_CONTROLLER] First item keys: ${(items.first as Map).keys.toList()}');
          debugPrint('[LOGS_CONTROLLER] First item sample: ${items.first}');
        }

        // Parse items - handle multiple time fields per record
        bool isFirstItem = true;
        final List<Map<String, dynamic>> result = [];

        // Fetch employees from local database for name lookup
        late List<Employee> localEmployees;
        try {
          localEmployees = await _employeeRepository.getEmployeesForSite(siteId!);
          debugPrint('[LOGS_CONTROLLER] Loaded ${localEmployees.length} employees from local DB for name lookup');
        } catch (e) {
          debugPrint('[LOGS_CONTROLLER] Failed to load local employees: $e');
          localEmployees = [];
        }

        // Build a map of employee IDs to names from local DB
        final employeeNames = <String, String>{};
        for (final emp in localEmployees) {
          final normalizedId = emp.id.trim().toLowerCase();
          employeeNames[normalizedId] = emp.name;
          debugPrint('[LOGS_CONTROLLER] Local employee: $normalizedId -> ${emp.name}');
        }

        for (final item in items) {
          if (item is! Map) continue;

          // Log all available fields for the first item
          if (isFirstItem) {
            debugPrint('[LOGS_CONTROLLER] Available fields in item: ${(item).keys.toList()}');
            debugPrint('[LOGS_CONTROLLER] First item full data: $item');
            isFirstItem = false;
          }

          final employeeId = (item['employee_id'] ??
                             item['employeeID'] ??
                             item['EMPLOYEEID'] ??
                             item['companyID'] ??
                             item['CompanyID'] ??
                             '')?.toString() ?? '';

          if (employeeId.isEmpty) continue;

          // Get employee name from local lookup
          final normalizedEmpId = employeeId.trim().toLowerCase();
          final employeeName = employeeNames[normalizedEmpId] ??
                              (item['employee_name'] ??
                               item['employeeName'] ??
                               item['EMPLOYEE_NAME'] ??
                               item['EmployeeName'] ??
                               item['name'] ??
                               item['Name'] ??
                               'Unknown')?.toString() ?? 'Unknown';

          debugPrint('[LOGS_CONTROLLER] Employee lookup: $normalizedEmpId -> $employeeName (from ${employeeNames.containsKey(normalizedEmpId) ? 'local DB' : 'API or default'})');

          // Extract all time fields and create separate entries for each
          final timesIn = [
            ('TIMEINMORNING', item['TIMEINMORNING']?.toString() ?? '', 'Morning'),
            ('TIMEINAFTERNOON', item['TIMEINAFTERNOON']?.toString() ?? '', 'Afternoon'),
          ];

          final timesOut = [
            ('TIMEOUTMORNING', item['TIMEOUTMORNING']?.toString() ?? '', 'Morning'),
            ('TIMEOUTAFTERNOON', item['TIMEOUTAFTERNOON']?.toString() ?? '', 'Afternoon'),
          ];

          // Process all Time In entries
          for (final (fieldName, timeStr, periodName) in timesIn) {
            if (timeStr.isNotEmpty) {
              final timeOnly = _extractTimeOnly(timeStr);
              result.add({
                'employee_id': employeeId,
                'employee_name': employeeName,
                'type': 'Time In',
                'time_only': timeOnly,
                'timestamp': timeStr,
                'period': periodName,
                'raw_data': item,
              });
              debugPrint('[LOGS_CONTROLLER] Created Time In entry: $employeeName ($employeeId) - $periodName at $timeOnly');
            }
          }

          // Process all Time Out entries
          for (final (fieldName, timeStr, periodName) in timesOut) {
            if (timeStr.isNotEmpty) {
              final timeOnly = _extractTimeOnly(timeStr);
              result.add({
                'employee_id': employeeId,
                'employee_name': employeeName,
                'type': 'Time Out',
                'time_only': timeOnly,
                'timestamp': timeStr,
                'period': periodName,
                'raw_data': item,
              });
              debugPrint('[LOGS_CONTROLLER] Created Time Out entry: $employeeName ($employeeId) - $periodName at $timeOnly');
            }
          }
        }

        debugPrint('[LOGS_CONTROLLER] Parsed ${result.length} valid items');
        for (int i = 0; i < result.take(5).length; i++) {
          final item = result[i];
          debugPrint('[LOGS_CONTROLLER] Log $i: ID=${item['employee_id']}, Name=${item['employee_name']}, Type=${item['type']}, Time=${item['time_only']}, Timestamp=${item['timestamp']}');
          debugPrint('[LOGS_CONTROLLER] Full raw data $i: ${item['raw_data']}');
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

  String _extractTimeOnly(String timestamp) {
    if (timestamp.isEmpty) return '';
    try {
      // Convert from "2026/04/01 08:59:23" to "2026-04-01 08:59:23"
      final normalized = timestamp.replaceAll('/', '-');
      final dt = DateTime.parse(normalized);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      // If timestamp is not a valid ISO format, try extracting time manually
      if (timestamp.contains(' ')) {
        final parts = timestamp.split(' ');
        if (parts.length >= 2) {
          return parts[1].substring(0, parts[1].length >= 5 ? 5 : parts[1].length);
        }
      }
      return '';
    }
  }

  Future<Map<String, String>> _fetchEmployeeNamesFromApi(String siteId) async {
    final names = <String, String>{};
    try {
      final url = Uri.parse(
        'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/employee/perSite?siteID=$siteId',
      );
      debugPrint('[LOGS_CONTROLLER] ===== FETCHING EMPLOYEE NAMES =====');
      debugPrint('[LOGS_CONTROLLER] URL: $url');

      final headers = {
        'Accept': 'application/json',
        'User-Agent': 'FAST-Attendance/1.0',
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_apiUsername:$_apiPassword'))}',
      };

      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 10),
      );

      debugPrint('[LOGS_CONTROLLER] Employee API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('[LOGS_CONTROLLER] Employee API Data Type: ${data.runtimeType}');
        debugPrint('[LOGS_CONTROLLER] Employee API Response (first 500 chars): ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');

        List<dynamic> employees = [];

        if (data is List) {
          employees = data;
          debugPrint('[LOGS_CONTROLLER] Response is direct List with ${employees.length} items');
        } else if (data is Map && data['data'] is List) {
          employees = data['data'];
          debugPrint('[LOGS_CONTROLLER] Response is Map with data wrapper, ${employees.length} items');
        } else if (data is Map) {
          debugPrint('[LOGS_CONTROLLER] Response is Map with keys: ${(data as Map).keys.toList()}');
          employees = data['data'] ?? data['employees'] ?? data['records'] ?? [];
        }

        debugPrint('[LOGS_CONTROLLER] Found ${employees.length} employees in response');

        for (final emp in employees) {
          if (emp is! Map) {
            debugPrint('[LOGS_CONTROLLER] Skipping non-map employee: $emp');
            continue;
          }

          final id = emp['employee_id']?.toString() ??
                     emp['employeeID']?.toString() ??
                     emp['EMPLOYEEID']?.toString() ??
                     '';
          final name = emp['employee_name']?.toString() ??
                      emp['employeeName']?.toString() ??
                      emp['EMPLOYEE_NAME']?.toString() ??
                      emp['EmployeeName']?.toString() ??
                      emp['name']?.toString() ??
                      emp['Name']?.toString() ??
                      emp['fullname']?.toString() ??
                      emp['fullName']?.toString() ??
                      emp['FULLNAME']?.toString() ??
                      emp['first_name']?.toString() ??
                      '';

          debugPrint('[LOGS_CONTROLLER] Processing: id="$id", name="$name", all_keys=${(emp as Map).keys.toList()}');

          if (id.isNotEmpty && name.isNotEmpty) {
            final normalizedId = id.trim().toLowerCase();
            names[normalizedId] = name;
            debugPrint('[LOGS_CONTROLLER] ✓ Stored: $normalizedId -> $name');
          } else {
            debugPrint('[LOGS_CONTROLLER] ✗ Skipped: empty id=$id or name=$name');
          }
        }
        debugPrint('[LOGS_CONTROLLER] Total employee names stored: ${names.length}');
      } else {
        debugPrint('[LOGS_CONTROLLER] Employee API returned ${response.statusCode}');
        debugPrint('[LOGS_CONTROLLER] Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Error fetching employee names: $e');
    }
    debugPrint('[LOGS_CONTROLLER] ===== END EMPLOYEE NAMES FETCH =====');
    return names;
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
    if (timestamp == null || timestamp.toString().isEmpty) return 'N/A';
    try {
      // Handle API format "2026/04/01 08:59:23"
      String ts = timestamp.toString();
      if (ts.contains('/')) {
        ts = ts.replaceAll('/', '-');
      }
      final dateTime = DateTime.parse(ts);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  String formatDate(dynamic timestamp) {
    if (timestamp == null || timestamp.toString().isEmpty) return 'N/A';
    try {
      // Handle API format "2026/04/01 08:59:23"
      String ts = timestamp.toString();
      if (ts.contains('/')) {
        ts = ts.replaceAll('/', '-');
      }
      final dateTime = DateTime.parse(ts);
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  String getTimeInOut(Map<String, dynamic> log) {
    final type = (log['type'] ?? '').toString().toLowerCase();
    if (type.contains('in')) return 'Time In';
    if (type.contains('out')) return 'Time Out';
    return log['type']?.toString() ?? 'Unknown';
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
