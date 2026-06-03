// ignore_for_file: unused_element, unused_local_variable, dead_code

import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../services/local_db.dart';
import '../constants/date_time_formats.dart';
import '../models/employee_model.dart';
import '../services/device_service.dart';
import '../services/device_service_impl.dart';
import '../services/employee_repository.dart';
import '../services/scanner_registry_service.dart';
class _ScannerEmployee {
  const _ScannerEmployee({required this.id, required this.name});
  final String id;
  final String name;
}

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
  final RxString selectedFilter = 'All'.obs;
  final RxString statusMessage = ''.obs;
  final RxString lastDbSyncLabel = ''.obs;
  final RxString errorMessage = ''.obs;
  final TextEditingController searchController = TextEditingController();
  final Rxn<DateTime> selectedDate = Rxn<DateTime>();

  // Authentication state
  final RxBool isAuthenticated = false.obs;
  final Rx<Employee?> authenticatedEmployee = Rx<Employee?>(null);
  final RxBool isScanning = false.obs;
  final RxBool isDeviceConnected = false.obs;

  // Cooldown
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

  /// Same in-memory maps as home page scanner (fid -> employee).
  final Map<int, _ScannerEmployee> _scannerEmployeeByFid = {};
  final Map<String, _ScannerEmployee> _scannerEmployeeByFidText = {};

  LogsController({this.siteId});
  
  // AFK timeout tracking
  Timer? _afkTimer;
  static const int _afkTimeoutSeconds = 60; // 1 minute inactivity timeout
  DateTime? _lastAfkInteractionAt;

  @override
  void onInit() {
    super.onInit();
    _deviceService = Get.find<DeviceService>();
    _employeeRepository = Get.find<EmployeeRepository>();
    _initializeDevice();
    // Start automatic fingerprint detection when page loads
    _startAutomaticDetection();
    _startAfkTimer();
  }

  @override
  void onClose() {
    try {
      searchController.dispose();
      _cooldownCheckTimer?.cancel();
      _afkTimer?.cancel();
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Error in onClose: $e');
    }
    super.onClose();
  }
  
  void _updateSelectedDate(DateTime? date) {
    selectedDate.value = date;
    searchController.text =
        date == null ? '' : DateTimeFormats.dateOnly(date);
  }

  void setSelectedDate(DateTime? date) {
    _updateSelectedDate(date);
    onUserInteraction();
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

  void onUserInteraction() {
    _lastAfkInteractionAt = DateTime.now();
    _resetAfkTimer();
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
    _cooldownCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
        if (siteId != null && siteId!.isNotEmpty) {
          await _loadEmployeesForSite();
        }
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
      debugPrint('[LOGS_CONTROLLER] Site selected: $siteId, starting fingerprint scan');
      await _loadEmployeesForSite();
      await startFingerprintAuthentication();
    } else {
      errorMessage.value = 'No site selected for authentication';
    }
  }

  Future<void> _authenticateWithLocalData() async {
    try {
      setStatus('Ready to authenticate - scan fingerprint');

      // Don't automatically load all logs - wait for user authentication
      // User must scan fingerprint before viewing logs
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Authentication error: $e');
      errorMessage.value = 'Authentication failed: $e';
    }
  }

  String _normalizeEmployeeId(String employeeId) =>
      employeeId.trim().toLowerCase();

  List<Employee> _dedupeEmployeesById(List<Employee> employees) {
    final byId = <String, Employee>{};
    for (final employee in employees) {
      final key = _normalizeEmployeeId(employee.id);
      if (key.isEmpty) continue;

      final existing = byId[key];
      if (existing == null) {
        byId[key] = employee;
        continue;
      }

      final hasTemplate = employee.fingerTemplate != null &&
          employee.fingerTemplate!.isNotEmpty;
      final existingHasTemplate = existing.fingerTemplate != null &&
          existing.fingerTemplate!.isNotEmpty;
      if (hasTemplate && !existingHasTemplate) {
        byId[key] = employee;
      }
    }
    return byId.values.toList();
  }

  Employee? _findEmployeeById(List<Employee> employees, String employeeId) {
    final target = _normalizeEmployeeId(employeeId);
    for (final employee in employees) {
      if (_normalizeEmployeeId(employee.id) == target) {
        return employee;
      }
    }
    return null;
  }

  /// Check if employee has enrolled thumb mark (any fingerprint row for that ID).
  Future<bool> _employeeHasThumbMark(String employeeId) async {
    try {
      final employees =
          _dedupeEmployeesById(await _employeeRepository.getEmployeesForSite(siteId!));
      return employees.any(
        (e) =>
            _normalizeEmployeeId(e.id) == _normalizeEmployeeId(employeeId) &&
            e.fingerTemplate != null &&
            e.fingerTemplate!.isNotEmpty,
      );
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Error checking thumb mark: $e');
      return false;
    }
  }

  Future<void> _completeFingerprintAuthentication(Employee employee) async {
    authenticatedEmployee.value = employee;
    isAuthenticated.value = true;
    errorMessage.value = '';

    debugPrint(
      '[LOGS_CONTROLLER] Fingerprint auth complete: ${employee.id} - ${employee.name}',
    );
    setStatus('Welcome, ${employee.name}! Loading time logs...');
    await loadLogs();

    if (logs.isNotEmpty) {
      setStatus('Loaded ${logs.length} time logs for ${employee.name}');
    } else if (isAuthenticated.value) {
      setStatus('Authenticated - no time logs found for ${employee.name}');
    }
    _resetAfkTimer();
  }

  /// Employee ID authentication is disabled (fingerprint-only access).
  Future<void> authenticateByEmployeeId(
    String employeeId,
  ) async {
    final trimmed = employeeId.trim();
    errorMessage.value = trimmed.isEmpty
        ? 'Employee ID authentication is disabled. Please scan your fingerprint.'
        : 'Employee ID authentication is disabled for $trimmed. Please scan your fingerprint.';
    setStatus('Scan fingerprint to authenticate');
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

  /// Wait for finger on scanner, then perform scanning only when finger is detected
  Future<void> _waitForFingerAndScan() async {
    debugPrint('[LOGS_CONTROLLER] Ready for fingerprint scan...');
    setStatus('Place finger on scanner');

    try {
      // Activate scanning mode on the device
      debugPrint('[LOGS_CONTROLLER] Activating scanner...');
      await _deviceService.startScanningMode();
      debugPrint('[LOGS_CONTROLLER] Scanner activated - waiting for finger');

      // Wait for finger detection instead of continuous scanning
      while (!isAuthenticated.value && isDeviceConnected.value && siteId != null) {
        try {
          await _performFingerprintScan();

          if (!isAuthenticated.value) {
            setStatus('Place finger on scanner');
          }

          // If match found, exit loop
          if (isAuthenticated.value) {
            debugPrint('[LOGS_CONTROLLER] ✓ Employee matched and authenticated');
            break;
          }

          // No match - wait before next attempt
          debugPrint('[LOGS_CONTROLLER] No match detected - waiting for next finger placement...');
          // Clear any error messages
          if (errorMessage.value.isNotEmpty) {
            errorMessage.value = '';
          }
          // Wait for finger to be removed and placed again
          await Future.delayed(const Duration(milliseconds: 2000));
        } catch (e) {
          debugPrint('[LOGS_CONTROLLER] Scan attempt error: $e');
          setStatus('Place finger on scanner');
          // Clear error and add delay before continuing
          errorMessage.value = '';
          debugPrint('[LOGS_CONTROLLER] Waiting before retry after error...');
          await Future.delayed(const Duration(milliseconds: 2000));
        }
      }
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Scan mode error: $e');
      errorMessage.value = 'Scanner error: $e';
      setStatus('Place finger on scanner...');
      isScanning.value = false;
    }
  }

  /// Check if finger is present on the scanner
  Future<bool> _checkFingerPresence() async {
    try {
      // Try to get a quick template to check if finger is present
      final template = await _deviceService.scanFingerprint();
      
      // If no template or invalid template, assume no finger
      if (template == null || !_isValidFingerprintTemplate(template)) {
        return false;
      }
      
      // Template detected - finger is present
      return true;
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Finger presence check error: $e');
      return false;
    }
  }
  
  /// Load employees into device + fid maps (same flow as home page scanner).
  Future<void> _loadEmployeesForSite() async {
    if (siteId == null || siteId!.isEmpty) return;

    try {
      debugPrint('[LOGS_SCAN] Loading employees for site: $siteId');
      final rows = await LocalDb.getEmployeesBySite(siteId!);
      _scannerEmployeeByFid.clear();
      _scannerEmployeeByFidText.clear();

      if (isDeviceConnected.value && Get.isRegistered<ScannerRegistryService>()) {
        await Get.find<ScannerRegistryService>().reloadSiteFromLocalDb(siteId!);
      }

      for (final row in rows) {
        final fid = row['fid'] as int?;
        final empId = row['employee_id']?.toString().trim() ?? '';
        final empName = row['employee_name']?.toString().trim();
        if (fid == null || empId.isEmpty) continue;

        final entry = _ScannerEmployee(id: empId, name: empName ?? empId);
        _scannerEmployeeByFid[fid] = entry;
        _scannerEmployeeByFidText[fid.toString()] = entry;
      }

      debugPrint(
        '[LOGS_SCAN] Scanner maps ready: ${_scannerEmployeeByFid.length} (rows=${rows.length})',
      );
    } catch (e) {
      debugPrint('[LOGS_CONTROLLER] Failed to load employees: $e');
    }
  }

  _ScannerEmployee? _lookupScannerEmployee({String? fidRaw, int? fingerId}) {
    return (fidRaw != null ? _scannerEmployeeByFidText[fidRaw.trim()] : null) ??
        (fingerId != null ? _scannerEmployeeByFid[fingerId] : null) ??
        (fingerId != null
            ? _scannerEmployeeByFidText[fingerId.toString()]
            : null);
  }

  Future<void> _performFingerprintScan() async {
    var didScan = false;
    try {
      debugPrint('[LOGS_CONTROLLER] ===== FINGERPRINT SCAN START =====');

      if (_scannerEmployeeByFid.isEmpty) {
        await _loadEmployeesForSite();
      }

      if (_scannerEmployeeByFid.isEmpty) {
        debugPrint('[LOGS_SCAN] No enrolled employees in scanner DB');
        return;
      }

      final template = await _deviceService.scanFingerprint();
      debugPrint('[LOGS_CONTROLLER] Fingerprint template received: ${template != null}');

      if (template != null && _isValidFingerprintTemplate(template)) {
        didScan = true;
        isScanning.value = true;
        setStatus('Scanning fingerprint...');
        debugPrint('[LOGS_CONTROLLER] Valid fingerprint - identifying on device...');

        final identification = await _deviceService.identifyOnDevice(
          capturedTemplate: template,
        );
        debugPrint(
          '[LOGS_SCAN] identify result fidRaw=${identification.fidRaw} fingerId=${identification.fingerId}',
        );

        var matched = _lookupScannerEmployee(
          fidRaw: identification.fidRaw,
          fingerId: identification.fingerId,
        );

        if (matched == null) {
          debugPrint('[LOGS_SCAN] Employee not found, reloading scanner DB...');
          await _loadEmployeesForSite();
          matched = _lookupScannerEmployee(
            fidRaw: identification.fidRaw,
            fingerId: identification.fingerId,
          );
        }

        if (matched != null) {
          debugPrint(
            '[LOGS_SCAN] ✓ Matched employee: ${matched.id} - ${matched.name}',
          );
          await _completeFingerprintAuthentication(
            Employee(
              id: matched.id,
              name: matched.name,
              siteId: siteId!,
              fid: identification.fingerId ??
                  DeviceServiceImpl.parseFingerId(identification.fidRaw),
            ),
          );
          debugPrint('[LOGS_CONTROLLER] ✓ Fingerprint authentication complete');
        } else {
          debugPrint(
            '[LOGS_SCAN] ✗ FID ${identification.fidRaw ?? identification.fingerId} not in employee map',
          );
        }
      } else {
        debugPrint('[LOGS_CONTROLLER] ✗ No valid fingerprint template received - ignoring noise');
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
    if (didScan) {
      isScanning.value = false;
    }
    debugPrint('[LOGS_CONTROLLER] ===== FINGERPRINT SCAN END =====');
  }

  /// Validate fingerprint template to filter out noise and invalid data
  bool _isValidFingerprintTemplate(Uint8List template) {
    // Check template size - valid templates should have reasonable size
    if (template.isEmpty || template.length < 100) {
      return false;
    }
    
    // Check for all zeros (empty/no data)
    bool hasNonZero = false;
    for (int i = 0; i < template.length; i++) {
      if (template[i] != 0) {
        hasNonZero = true;
        break;
      }
    }
    if (!hasNonZero) return false;
    
    // Check for repeated patterns (noise)
    if (template.length > 10) {
      int sameCount = 1;
      for (int i = 1; i < template.length; i++) {
        if (template[i] == template[i-1]) {
          sameCount++;
          if (sameCount > template.length * 0.8) {
            return false; // Too much repetition, likely noise
          }
        } else {
          sameCount = 1;
        }
      }
    }
    
    return true;
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
      // OFFLINE-FIRST: Load logs from local database ONLY
      debugPrint('[LOGS_CONTROLLER] Loading from OFFLINE database (offline-first approach)...');
      final localLogs = await LocalDb.getAttendanceLogsForEmployee(
        authenticatedEmployee.value!.id,
        siteId!,
      );
      debugPrint('[LOGS_CONTROLLER] Offline DB returned ${localLogs.length} logs');

      if (localLogs.isNotEmpty) {
        final enriched = localLogs.map((log) {
          final copy = Map<String, dynamic>.from(log);
          copy['employee_id'] ??= authenticatedEmployee.value!.id;
          copy['employee_name'] = _resolveEmployeeName(copy);
          copy['period'] = _resolvePeriod(copy);
          return copy;
        }).toList();

        final deduped = <String, Map<String, dynamic>>{};
        for (final log in enriched) {
          final key =
              '${log['timestamp']}_${log['type']}_${log['period']}_${log['time_only']}';
          deduped.putIfAbsent(key, () => log);
        }

        logs.assignAll(deduped.values.toList());
        debugPrint(
          '[LOGS_CONTROLLER] ✅ Loaded ${logs.length} logs from OFFLINE database (${localLogs.length} raw)',
        );
        setStatus('Loaded ${logs.length} time logs (offline)');
        debugPrint('[LOGS_CONTROLLER] ===== LOAD LOGS END =====');
        return;
      }

      debugPrint(
        '[LOGS_CONTROLLER] No local logs — pulling full history from API',
      );
      try {
        await LocalDb.syncTimelogsForEmployeeFromApi(
          siteId: siteId!,
          employeeId: authenticatedEmployee.value!.id,
        );
        final afterSync = await LocalDb.getAttendanceLogsForEmployee(
          authenticatedEmployee.value!.id,
          siteId!,
        );
        if (afterSync.isNotEmpty) {
          logs.assignAll(
            afterSync.map((log) {
              final copy = Map<String, dynamic>.from(log);
              copy['employee_name'] = _resolveEmployeeName(copy);
              copy['period'] = _resolvePeriod(copy);
              return copy;
            }).toList(),
          );
          setStatus('Loaded ${logs.length} time logs from server');
          debugPrint('[LOGS_CONTROLLER] ===== LOAD LOGS END (API SYNC) =====');
          return;
        }
      } catch (e) {
        debugPrint('[LOGS_CONTROLLER] API timelog sync failed: $e');
      }

      debugPrint('[LOGS_CONTROLLER] ⚠️ No logs found after sync');
      setStatus('Authenticated - no time logs found');
      logs.clear();
      debugPrint('[LOGS_CONTROLLER] ===== LOAD LOGS END (NO LOCAL DATA) =====');
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
    selectedDate.value = null;
    errorMessage.value = '';
    logCooldownMap.clear();
    activeCooldownCount.value = 0;
    setStatus('Logged out - scan fingerprint to authenticate');
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
          localEmployees = await _employeeRepository.getEmployeesForSite(siteId);
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

  String _resolveEmployeeName(Map<String, dynamic> log) {
    final employeeId = (log['employee_id'] ?? '').toString().trim();
    final rawName =
        (log['employee_name'] ?? log['name'] ?? '').toString().trim();
    final authName = authenticatedEmployee.value?.name.trim() ?? '';

    final isPlaceholder = rawName.isEmpty ||
        rawName.toLowerCase() == 'unknown' ||
        rawName.toLowerCase().startsWith('employee');

    if (isPlaceholder &&
        authName.isNotEmpty &&
        (employeeId.isEmpty ||
            employeeId.toLowerCase() ==
                (authenticatedEmployee.value?.id.toLowerCase() ?? ''))) {
      return authName;
    }

    if (rawName.isNotEmpty) return rawName;
    if (authName.isNotEmpty) return authName;
    return employeeId.isEmpty ? 'Unknown' : employeeId;
  }

  String _resolvePeriod(Map<String, dynamic> log) {
    final rawPeriod = (log['period'] ?? '').toString().trim();
    final parsed = _parseLogTimestamp(log['timestamp']);

    if (parsed != null) {
      return parsed.hour < 12 ? 'Morning' : 'Afternoon';
    }

    final timeText = (log['time_only'] ?? '').toString().trim();
    if (timeText.isNotEmpty && timeText.contains(':')) {
      final hour = int.tryParse(timeText.split(':').first);
      if (hour != null) {
        return hour < 12 ? 'Morning' : 'Afternoon';
      }
    }

    if (rawPeriod.toLowerCase().contains('morn')) return 'Morning';
    if (rawPeriod.toLowerCase().contains('after')) return 'Afternoon';
    return rawPeriod;
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
          debugPrint('[LOGS_CONTROLLER] Response is Map with keys: ${(data).keys.toList()}');
          employees = data['data'] ?? data['employees'] ?? data['records'] ?? [];
        }

        debugPrint('[LOGS_CONTROLLER] Found ${employees.length} employees in response');

        for (final emp in employees) {
          if (emp is! Map) {
            debugPrint('[LOGS_CONTROLLER] Skipping non-map employee: $emp');
            continue;
          }

          final row = Map<String, dynamic>.from(emp);
          final id = LocalDb.employeeIdFromApiRow(row) ?? '';
          final name = LocalDb.profileFieldsFromApiRow(row)['employee_name'] ?? '';

          debugPrint('[LOGS_CONTROLLER] Processing: id="$id", name="$name", all_keys=${(emp).keys.toList()}');

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
    if (!isAuthenticated.value) {
      return [];
    }

    var filtered = logs.toList();
    
    // Apply type filter
    if (selectedFilter.value != 'All') {
      filtered = filtered.where((log) {
        final type = (log['type'] ?? '').toString().toLowerCase();
        return type.contains(selectedFilter.value.toLowerCase());
      }).toList();
    }
    
    final targetDate = selectedDate.value;
    if (targetDate != null) {
      final targetKey = DateTimeFormats.dateKey(targetDate);
      filtered = filtered.where((log) {
        final logKey = _logDateKey(log);
        return logKey != null && logKey == targetKey;
      }).toList();
    }
    
    return filtered;
  }
  
  void setFilter(String filter) {
    selectedFilter.value = filter;
  }
  
  void clearSearch() {
    searchController.clear();
    selectedDate.value = null;
  }
  
  String formatTimestamp(dynamic timestamp) {
    if (timestamp == null || timestamp.toString().isEmpty) return 'N/A';
    try {
      final dateTime = _parseLogTimestamp(timestamp);
      if (dateTime == null) return 'N/A';
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  String formatDate(dynamic timestamp) {
    if (timestamp == null || timestamp.toString().isEmpty) return 'N/A';
    try {
      final dateTime = _parseLogTimestamp(timestamp);
      if (dateTime == null) return 'N/A';
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  DateTime? _parseLogTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    final raw = timestamp.toString().trim();
    if (raw.isEmpty) return null;

    final normalized = raw.replaceAll('/', '-');
    final parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed;

    if (normalized.contains(' ')) {
      final datePart = normalized.split(' ').first;
      return DateTime.tryParse(datePart);
    }
    return null;
  }

  String? _logDateKey(Map<String, dynamic> log) {
    final raw = log['timelog_date'] ??
        log['timeLogDate'] ??
        log['timelog'] ??
        log['timestamp'] ??
        log['date'] ??
        log['datetime'];
    final parsed = _parseLogTimestamp(raw);
    return parsed == null ? null : DateTimeFormats.dateKey(parsed);
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
      
      final count = await LocalDb.syncTimelogsFromApi(siteId!);

      if (count > 0) {
        setStatus('Saved $count timelog records to local database');
        debugPrint('[LOGS_CONTROLLER] Saved $count timelog rows to local database');
      } else {
        setStatus('No time logs found on server (sync employees first)');
      }
    } catch (e) {
      errorMessage.value = 'Failed to fetch time logs: $e';
      setStatus('Error fetching time logs from server');
    } finally {
      isLoading.value = false;
    }
  }

  // Send individual log entry to server
  Future<void> sendLogToServer(Map<String, dynamic> log) async {
    try {
      debugPrint('[LOGS_CONTROLLER] ===== SEND LOG TO SERVER START =====');
      debugPrint('[LOGS_CONTROLLER] Sending log: ${log['employee_id']} - ${log['employee_name']} - ${log['type']} - ${log['timestamp']}');
      
      if (siteId == null || siteId!.isEmpty) {
        errorMessage.value = 'No site selected';
        return;
      }

      setStatus('Sending log to server...');
      
      // Prepare the log data for API
      final logData = {
        'employee_id': log['employee_id'],
        'employee_name': log['employee_name'],
        'type': log['type'],
        'timestamp': log['timestamp'],
        'time_only': log['time_only'],
        'period': log['period'],
        'site_id': siteId,
        'raw_data': log['raw_data'],
      };

      final url = Uri.parse(
        'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/post/timelog',
      );
      
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'FAST-Attendance/1.0',
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_apiUsername:$_apiPassword'))}',
      };

      debugPrint('[LOGS_CONTROLLER] Sending to URL: $url');
      debugPrint('[LOGS_CONTROLLER] Log data: $logData');

      final response = await http.post(
        url,
        headers: headers,
        body: json.encode(logData),
      ).timeout(const Duration(seconds: 15));

      debugPrint('[LOGS_CONTROLLER] Response Status: ${response.statusCode}');
      debugPrint('[LOGS_CONTROLLER] Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        debugPrint('[LOGS_CONTROLLER] Server response: $responseData');
        
        // Check if the response indicates success
        if (responseData['success'] == true || responseData['status'] == 'success') {
          setStatus('Log sent to server successfully');
          debugPrint('[LOGS_CONTROLLER] ✓ Log sent successfully');
        } else {
          errorMessage.value = 'Server returned error: ${responseData['message'] ?? 'Unknown error'}';
          debugPrint('[LOGS_CONTROLLER] ✗ Server error: ${responseData['message']}');
        }
      } else {
        errorMessage.value = 'Failed to send log: HTTP ${response.statusCode}';
        debugPrint('[LOGS_CONTROLLER] ✗ HTTP error: ${response.statusCode}');
        debugPrint('[LOGS_CONTROLLER] Response: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('[LOGS_CONTROLLER] ✗ Error sending log to server: $e');
      debugPrint('[LOGS_CONTROLLER] Stack trace: $stackTrace');
      errorMessage.value = 'Failed to send log: $e';
      setStatus('Error sending log to server');
    } finally {
      debugPrint('[LOGS_CONTROLLER] ===== SEND LOG TO SERVER END =====');
      // Clear status message after a delay
      Future.delayed(const Duration(seconds: 3), () {
        if (statusMessage.value.contains('Sending')) {
          setStatus('');
        }
      });
    }
  }

  // Utility methods
  void setStatus(String status) {
    statusMessage.value = status;
  }
}
