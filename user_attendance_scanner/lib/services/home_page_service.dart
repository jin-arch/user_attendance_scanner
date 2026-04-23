import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../zkfp/zkteco_usb.dart';
import '../services/local_db.dart';
import '../controllers/legacy_home_page_controller.dart';
import 'package:image_picker/image_picker.dart';

class SiteOption {
  const SiteOption({required this.id, required this.name});
  final String id;
  final String name;
}

class EmployeeEntry {
  const EmployeeEntry({required this.id, required this.name});
  final String id;
  final String name;
}

enum ScanResultType {
  timeInSuccess,
  timeOutSuccess,
  alreadyTimedIn,
  alreadyTimedOut,
  timeInUnsuccessful,
  timeOutUnsuccessful,
  fingerprintNotRecognized,
}

class ScanResult {
  const ScanResult({
    required this.success,
    required this.timestamp,
    this.errorMessage,
    this.type = ScanResultType.fingerprintNotRecognized,
    this.employeeName,
    this.attendanceType,
  });
  final bool success;
  final DateTime timestamp;
  final String? errorMessage;
  final ScanResultType type;
  final String? employeeName;
  final String? attendanceType;
}

class PendingTimeLog {
  const PendingTimeLog({
    required this.timeLogId,
    required this.timeLogDate,
    required this.remarks,
    required this.schedule,
    required this.code,
    this.timeInMorning,
    this.timeOutMorning,
    this.timeInAfternoon,
    this.timeOutAfternoon,
  });
  final String timeLogId;
  final String timeLogDate;
  final String remarks;
  final String schedule;
  final String code;
  final String? timeInMorning;
  final String? timeOutMorning;
  final String? timeInAfternoon;
  final String? timeOutAfternoon;
}

enum HomeUiMode { scanner, portal }

class HomePageService extends GetxService {
  static const String _apiBaseUrl =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/';
  static const String _siteApiUrl = '${_apiBaseUrl}get/site/all';
  static const String _employeesApiUrl =
      '${_apiBaseUrl}get/employee/perSite?siteID=';
  static const String _timelogPerSiteApiUrl =
      '${_apiBaseUrl}get/timelog/lastweek/perSite?siteID=';
  static const String _timeInApiEndpoint = 'update/timeLog/timeIn';
  static const String _timeOutApiEndpoint = 'update/timeLog/timeOut';
  static const String _insertHrisLogsApiEndpoint =
      'insert/hris/logs/transaction';
  static const String _insertTimeLogApiEndpoint = 'insert/timeLog';
  static const String _thumbDetailsApiEndpoint = 'update/employee/thumbDetails';
  static const String _legacyAttendanceApiUrl =
      '${_apiBaseUrl}post/attendance/add';
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';
  static const String _deviceSitePrefsKey = 'device_site_map_v1';

  // Device and state management
  final ZKTecoUSB _device = ZKTecoUSB();
  final RxBool isLoadingSites = false.obs;
  final RxString selectedSiteId = ''.obs;
  final RxString selectedSiteName = ''.obs;
  final RxBool isLoadingEmployees = false.obs;
  final RxBool isConnected = false.obs;
  final RxBool isScanning = false.obs;
  final RxBool isLiveSyncRunning = false.obs;
  final RxString status = 'Disconnected'.obs;
  final RxList<SiteOption> sites = <SiteOption>[].obs;
  final RxList<EmployeeEntry> employees = <EmployeeEntry>[].obs;
  final Rx<HomeUiMode> uiMode = HomeUiMode.scanner.obs;
  final Rx<ScanResult?> lastResult = Rx<ScanResult?>(null);
  final RxBool showResult = false.obs;
  final Map<String, String> deviceSiteMap = {};
  final Map<int, EmployeeEntry> employeeDb = {};
  final Map<String, EmployeeEntry> employeeDbByFid = {};
  final RxBool isActiveRoute = true.obs;
  final RxBool isProcessingTemplate = false.obs;
  final Rx<DateTime?> lastTemplateHandledAt = Rx<DateTime?>(null);
  void Function(Uint8List template, int size)? templateHandler;

  // Getter for device access
  ZKTecoUSB get device => _device;

  final RxString matchedAttendanceType = ''.obs;
  final Rxn<DateTime> matchedAt = Rxn<DateTime>();
  
  // Timer properties
  Timer? portalAutoReturnTimer;
  Timer? liveSyncTimer;
  Timer? scanTimer;
  
  // Employee matching
  final Rxn<EmployeeEntry> matchedEmployee = Rxn<EmployeeEntry>();
  
  // Controller reference
  late final LegacyHomePageController controller;
  
  // Callbacks
  Function(String)? onStatusUpdate;
  Function(ScanResult)? onScanResult;
  Function()? onEmployeesLoaded;
  Function(String)? onError;

  @override
  void onInit() {
    super.onInit();
    controller = Get.find<LegacyHomePageController>();
    _setupDeviceCallbacks();
  }

  void _setupDeviceCallbacks() {
    if (ZKTecoUSB.isAndroidPlatform) {
      _device.onDeviceAttached = () {
        controller.setStatus('Device attached!');
        autoConnectIfSiteSelected();
      };
      _device.onDeviceDetached = () {
        controller.setConnected(false, status: 'Device detached');
        employeeDb.clear();
        employeeDbByFid.clear();
        isProcessingTemplate.value = false;
        lastTemplateHandledAt.value = null;
        portalAutoReturnTimer?.cancel();
        stopLiveDbSync();
        stopScanLoop();
      };
      templateHandler = (template, size) {
        handleAndroidTemplate(template, size);
      };
      _device.onTemplateExtracted = templateHandler;
    }
  }

  Future<void> loadDeviceSiteMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deviceSitePrefsKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        deviceSiteMap
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, '$v')));
      }
    } catch (_) {}
  }

  Future<void> saveDeviceSiteMap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceSitePrefsKey, jsonEncode(deviceSiteMap));
  }

  Future<List<SiteOption>> fetchSites() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(_siteApiUrl));
      final basicToken = base64Encode(
        utf8.encode('$_apiUsername:$_apiPassword'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
      final list = _extractSiteRows(decoded);

      final siteList = list
          .map((site) {
            final name =
                site['site_name'] ??
                site['SITENAME'] ??
                site['name'] ??
                site['site'] ??
                site['title'];
            final id =
                site['site_id'] ??
                site['SITEID'] ??
                site['id'] ??
                site['siteid'] ??
                site['site_code'] ??
                site['code'];

            if (name == null && id == null) {
              return null;
            }

            final label = (name ?? id).toString().trim();
            final value = (id ?? name).toString().trim();

            if (label.isEmpty || value.isEmpty) {
              return null;
            }

            return SiteOption(id: value, name: label);
          })
          .whereType<SiteOption>()
          .toList();

      // If API returns no sites, add fallback sample sites
      if (siteList.isEmpty) {
        return _getFallbackSites();
      }

      return siteList;
    } catch (e) {
      // On any error, return fallback sites to prevent empty app
      return _getFallbackSites();
    } finally {
      client.close(force: true);
    }
  }

  List<SiteOption> _getFallbackSites() {
    return [
      const SiteOption(id: 'demo-1', name: 'Demo Office 1'),
      const SiteOption(id: 'demo-2', name: 'Demo Office 2'),
      const SiteOption(id: 'demo-3', name: 'Demo Office 3'),
    ];
  }

  List<Map<String, dynamic>> _extractSiteRows(dynamic decoded) {
    dynamic data = decoded;
    if (decoded is Map<String, dynamic>) {
      data =
          decoded['data'] ??
          decoded['sites'] ??
          decoded['result'] ??
          decoded['records'] ??
          decoded['site'] ??
          decoded['employees'] ??
          decoded['timelogs'] ??
          decoded['timelog'] ??
          decoded['logs'];
    }

    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return const [];
  }

  Future<void> ensureSitesLoaded() async {
    if (sites.isNotEmpty || isLoadingSites.value) return;

    isLoadingSites.value = true;
    try {
      final fetched = await fetchSites();
      sites.assignAll(fetched);
    } catch (e) {
      onStatusUpdate?.call('Connected, but site list failed to load: $e');
    } finally {
      isLoadingSites.value = false;
    }
  }

  String? siteNameById(String? siteId) {
    if (siteId == null || siteId.isEmpty) return null;
    try {
      final site = sites.firstWhere((s) => s.id == siteId);
      return site.name;
    } catch (e) {
      return null;
    }
  }

  Future<void> autoConnectIfSiteSelected() async {
    if (_device.isConnected || controller.isSearching.value) return;
    
    // Only auto-connect if we have a site selected
    if (selectedSiteId?.value == null || selectedSiteId!.value!.isEmpty) return;
    
    debugPrint('[AUTO_CONNECT] Attempting auto-connect for site: ${selectedSiteId?.value}');
    
    try {
      if (ZKTecoUSB.isAndroidPlatform) {
        final env = await _device.getAndroidSdkEnvironment();
        if (env['canUseSdk'] != true) {
          debugPrint('[AUTO_CONNECT] SDK not compatible: ${env['reason']}');
          return;
        }
      }

      final sdkInit = await _device.initSdk();
      if (!sdkInit) {
        debugPrint('[AUTO_CONNECT] SDK init failed');
        return;
      }

      final count = await _device.getDeviceCountAsync();
      if (count == 0) {
        debugPrint('[AUTO_CONNECT] No device found');
        await _device.terminateSdk();
        return;
      }

      final opened = await _device.openDevice(0);
      if (!opened) {
        debugPrint('[AUTO_CONNECT] Failed to open device');
        await _device.terminateSdk();
        return;
      }

      final serial = await _device.getSerialNumber();
      final siteName = siteNameById(selectedSiteId?.value);
      final siteText = siteName != null ? ' | Site: $siteName' : '';
      
      controller.setConnected(
        true,
        status: 'Connected: ${serial ?? 'Unknown'}$siteText',
      );

      debugPrint('[AUTO_CONNECT] Success - loading templates and starting sync');
      
      // Load templates and start background sync
      await loadAndRegisterTemplates();
      await fetchAndCacheSiteTimeLogs();
      startLiveDbSync();
      
      // Start scanning if in scanner mode
      if (uiMode.value == HomeUiMode.scanner) {
        startScanLoop();
      }
    } catch (e) {
      debugPrint('[AUTO_CONNECT] Error: $e');
    }
  }

  Future<void> loadAndRegisterTemplates() async {
    final siteId = selectedSiteId?.value;
    if (siteId == null || siteId.isEmpty) return;
    
    await loadFromLocalDb(siteId);
  }

  Future<void> loadFromLocalDb(String siteId) async {
    try {
      final employees = await LocalDb.getEmployeesBySite(siteId);
      
      employeeDb.clear();
      employeeDbByFid.clear();
      
      for (final emp in employees) {
        final empId = emp['employee_id'] as String;
        final empName = emp['employee_name'] as String;
        final fid = emp['fid'] as int;
        final template = emp['template'] as String;
        
        employeeDb[fid] = EmployeeEntry(id: empId, name: empName);
        employeeDbByFid[template] = EmployeeEntry(id: empId, name: empName);
      }
      
      onEmployeesLoaded?.call();
      debugPrint('[LOCAL_DB] Loaded ${employeeDb.length} employee templates');
    } catch (e) {
      debugPrint('[LOCAL_DB] Error loading templates: $e');
    }
  }

  Future<void> fetchAndCacheSiteTimeLogs() async {
    final siteId = selectedSiteId?.value;
    if (siteId == null || siteId.isEmpty) return;
    
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      
      final url = '$_timelogPerSiteApiUrl$siteId';
      final request = await client.getUrl(Uri.parse(url));
      final basicToken = base64Encode(
        utf8.encode('$_apiUsername:$_apiPassword'),
      );
      
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode <= 299) {
        final decoded = jsonDecode(body);
        final logs = _extractSiteRows(decoded);
        
        // Cache timelogs in local database
        await LocalDb.cacheTimeLogs(siteId, logs);
        debugPrint('[API] Cached ${logs.length} timelogs for site $siteId');
      }
    } catch (e) {
      debugPrint('[API] Error fetching timelogs: $e');
    }
  }

  void startLiveDbSync() {
    if (isLiveSyncRunning.value) return;
    isLiveSyncRunning.value = true;
    
    liveSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!isLiveSyncRunning.value) return;
      
      final siteId = selectedSiteId?.value;
      if (siteId != null && siteId.isNotEmpty) {
        await fetchAndCacheSiteTimeLogs();
      }
    });
  }

  void stopLiveDbSync() {
    liveSyncTimer?.cancel();
    liveSyncTimer = null;
    isLiveSyncRunning.value = false;
  }

  void startScanLoop() {
    if (controller.isScanning.value) return;
    controller.setScanning(true);
    debugPrint('[SCAN_LOOP] Starting scan loop...');
    
    scanTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!controller.isScanning.value || !_device.isConnected) return;
      
      try {
        final template = await _device.captureFingerprint();
        if (template != null && template.isNotEmpty) {
          await _processFingerprintTemplate(template);
        }
      } catch (e) {
        debugPrint('[SCAN_LOOP] Capture error: $e');
      }
    });
  }

  void stopScanLoop() {
    scanTimer?.cancel();
    scanTimer = null;
    controller.setScanning(false);
    debugPrint('[SCAN_LOOP] Scan loop stopped');
  }

  Future<void> _processFingerprintTemplate(Uint8List template) async {
    if (!isActiveRoute.value || isProcessingTemplate.value) return;
    
    final now = DateTime.now();
    if (lastTemplateHandledAt.value != null) {
      final diff = now.difference(lastTemplateHandledAt.value!);
      if (diff.inMilliseconds < 1000) {
        return; // Debounce rapid scans
      }
    }
    
    isProcessingTemplate.value = true;
    lastTemplateHandledAt.value = now;
    
    try {
      final templateString = String.fromCharCodes(template);
      final employee = employeeDbByFid[templateString];
      
      if (employee != null) {
        await _processRecognizedEmployee(employee);
      } else {
        _showScanResult(ScanResult(
          success: false,
          timestamp: now,
          type: ScanResultType.fingerprintNotRecognized,
          errorMessage: 'Fingerprint not recognized',
        ));
      }
    } catch (e) {
      debugPrint('[SCAN] Error processing template: $e');
    } finally {
      isProcessingTemplate.value = false;
    }
  }

  Future<void> _processRecognizedEmployee(EmployeeEntry employee) async {
    final now = DateTime.now();
    final attendanceType = await _determineAttendanceType(employee.id, now);
    
    matchedEmployee.value = employee;
    matchedAttendanceType.value = attendanceType;
    matchedAt.value = now;
    
    final result = await _recordAttendance(employee, attendanceType, now);
    _showScanResult(result);
  }

  Future<String> _determineAttendanceType(String employeeId, DateTime now) async {
    try {
      final siteId = selectedSiteId?.value;
      if (siteId == null || siteId.isEmpty) return 'TIME IN';
      
      // Check if already timed in today
      final todayLogs = await LocalDb.getEmployeeLogsForDate(employeeId, siteId, now);
      final hasTimeIn = todayLogs.any((log) => 
        log['type'].toString().toLowerCase().contains('in'));
      
      return hasTimeIn ? 'TIME OUT' : 'TIME IN';
    } catch (e) {
      debugPrint('[ATTENDANCE] Error determining type: $e');
      return 'TIME IN';
    }
  }

  Future<ScanResult> _recordAttendance(EmployeeEntry employee, String attendanceType, DateTime timestamp) async {
    try {
      final siteId = selectedSiteId?.value;
      if (siteId == null || siteId.isEmpty) {
        return ScanResult(
          success: false,
          timestamp: timestamp,
          errorMessage: 'No site selected',
        );
      }
      
      // Record to local database first
      await LocalDb.insertTimeLog({
        'employeeId': employee.id,
        'employeeName': employee.name,
        'siteId': siteId,
        'type': attendanceType,
        'timestamp': timestamp.toIso8601String(),
      });
      
      // TODO: Send to remote API
      // await _sendToRemoteApi(employee, attendanceType, timestamp);
      
      final typeEnum = attendanceType.toLowerCase().contains('in') 
        ? ScanResultType.timeInSuccess 
        : ScanResultType.timeOutSuccess;
      
      return ScanResult(
        success: true,
        timestamp: timestamp,
        type: typeEnum,
        employeeName: employee.name,
        attendanceType: attendanceType,
      );
    } catch (e) {
      debugPrint('[ATTENDANCE] Error recording: $e');
      return ScanResult(
        success: false,
        timestamp: timestamp,
        errorMessage: 'Failed to record attendance: $e',
      );
    }
  }

  void _showScanResult(ScanResult result) {
    lastResult.value = result;
    showResult.value = true;
    onScanResult?.call(result);
    
    // Auto-hide result after 3 seconds
    Timer(const Duration(seconds: 3), () {
      if (showResult.value) {
        showResult.value = false;
      }
    });
  }

  void handleAndroidTemplate(Uint8List template, int size) {
    if (!isActiveRoute.value) return;
    _processFingerprintTemplate(template);
  }

  void setActiveRoute(bool active) {
    isActiveRoute.value = active;
    if (active && ZKTecoUSB.isAndroidPlatform) {
      templateHandler = (template, size) {
        handleAndroidTemplate(template, size);
      };
      _device.onTemplateExtracted = templateHandler;
    } else if (!active) {
      stopScanLoop();
      if (ZKTecoUSB.isAndroidPlatform) {
        if (_device.onTemplateExtracted == templateHandler) {
          _device.onTemplateExtracted = null;
        }
      }
    }
  }

  Future<void> reloadEmployeesForCurrentSite() async {
    final siteId = selectedSiteId?.value;
    if (siteId == null || siteId.isEmpty) return;
    
    debugPrint('[RELOAD_EMPLOYEES] Reloading employees for site: $siteId');
    try {
      await loadFromLocalDb(siteId);
      debugPrint('[RELOAD_EMPLOYEES] Successfully reloaded ${employeeDb.length} employees');
    } catch (e) {
      debugPrint('[RELOAD_EMPLOYEES] Error reloading employees: $e');
    }
  }

  void setSiteId(String siteId) {
    selectedSiteId.value = siteId;
  }

  void setUiMode(HomeUiMode mode) {
    uiMode.value = mode;
  }

  void clearLastResult() {
    showResult.value = false;
    lastResult.value = null;
  }

  // Missing methods needed by HomePage
  Future<void> _loadDeviceSiteMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deviceSitePrefsKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        deviceSiteMap
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, '$v')));
      }
    } catch (_) {}
  }

  Future<void> initialize() async {
    // Initialize the service
    await _loadDeviceSiteMap();
  }

  void resumeScanning() {
    if (isConnected.value && uiMode.value == HomeUiMode.scanner) {
      startScanLoop();
    }
  }

  void pauseScanning() {
    stopScanLoop();
  }

  void handleDeviceDetached() {
    employeeDb.clear();
    employeeDbByFid.clear();
    isProcessingTemplate.value = false;
    lastTemplateHandledAt.value = null;
    stopLiveDbSync();
    stopScanLoop();
  }

  String getCurrentSiteName() {
    final siteId = selectedSiteId?.value;
    if (siteId == null) return 'Unknown';
    final site = sites.firstWhereOrNull((s) => s.id == siteId);
    return site?.name ?? 'Unknown';
  }

  void toggleUiMode() {
    if (uiMode.value == HomeUiMode.scanner) {
      uiMode.value = HomeUiMode.portal;
    } else {
      uiMode.value = HomeUiMode.scanner;
    }
  }

  Future<void> connectDevice() async {
    if (!isConnected.value) {
      await _device.connect();
    }
  }

  Future<void> disconnectDevice() async {
    if (isConnected.value) {
      await _device.disconnect();
    }
  }

  Future<void> refreshData() async {
    final siteId = selectedSiteId?.value;
    if (siteId != null) {
      await loadFromLocalDb(siteId);
    }
  }

  Future<void> selectSite(String siteId) async {
    setSiteId(siteId);
    await loadFromLocalDb(siteId);
  }

  void dispose() {
    stopScanLoop();
    stopLiveDbSync();
    if (isConnected.value) {
      _device.disconnect();
    }
  }
}
