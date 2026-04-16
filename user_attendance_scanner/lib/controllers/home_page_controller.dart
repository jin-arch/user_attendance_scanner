import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../site_model.dart';
import '../employee_model.dart';
import '../attendance_model.dart';
import '../scan_result_model.dart';
import '../app_routes.dart';
import '../site_repository.dart';
import '../employee_repository.dart';
import '../attendance_repository.dart';
import '../device_service.dart';

class HomePageController extends GetxController {
  // Dependencies (will be injected)
  final SiteRepository _siteRepository;
  final EmployeeRepository _employeeRepository;
  final AttendanceRepository _attendanceRepository;
  final DeviceService _deviceService;

  HomePageController(
    this._siteRepository,
    this._employeeRepository,
    this._attendanceRepository,
    this._deviceService,
  );

  // Observable state
  final now = DateTime.now().obs;
  final sites = <Site>[].obs;
  final employees = <Employee>[].obs;
  final selectedSite = Rx<Site?>(null);
  final lastScanResult = Rx<ScanResult?>(null);
  
  // UI State
  final isLoadingSites = false.obs;
  final isLoadingEmployees = false.obs;
  final isSearching = false.obs;
  final isScanning = false.obs;
  final isConnected = false.obs;
  final isSyncing = false.obs;
  
  // Status and messages
  final statusMessage = ''.obs;
  final lastDbSyncLabel = ''.obs;
  final errorMessage = ''.obs;

  // Timers
  Timer? _clockTimer;
  Timer? _syncTimer;

  @override
  void onInit() {
    super.onInit();
    _initializeController();
  }

  @override
  void onClose() {
    _clockTimer?.cancel();
    _syncTimer?.cancel();
    super.onClose();
  }

  Future<void> _initializeController() async {
    // Start clock timer
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      now.value = DateTime.now();
    });

    // Initialize app
    await loadSites();
    await connectDevice();
    _startAutoSync();
  }

  // SITE MANAGEMENT
  Future<void> loadSites() async {
    try {
      isLoadingSites.value = true;
      errorMessage.value = '';
      
      final fetchedSites = await _siteRepository.fetchSites();
      sites.value = fetchedSites;
      
      if (fetchedSites.isNotEmpty && selectedSite.value == null) {
        await selectSite(fetchedSites.first);
      }
    } catch (e) {
      errorMessage.value = 'Failed to load sites: $e';
      // Try cached sites as fallback
      final cachedSites = await _siteRepository.getCachedSites();
      sites.value = cachedSites;
    } finally {
      isLoadingSites.value = false;
    }
  }

  Future<void> selectSite(Site site) async {
    try {
      selectedSite.value = site;
      await loadEmployeesForSite(site.id);
      setStatus('Site selected: ${site.name}');
    } catch (e) {
      errorMessage.value = 'Failed to select site: $e';
    }
  }

  // EMPLOYEE MANAGEMENT
  Future<void> loadEmployeesForSite(String siteId) async {
    try {
      isLoadingEmployees.value = true;
      employees.value = await _employeeRepository.getEmployeesForSite(siteId);
      
      final count = employees.length;
      setStatus('Loaded $count employees for site');
    } catch (e) {
      errorMessage.value = 'Failed to load employees: $e';
      employees.value = [];
    } finally {
      isLoadingEmployees.value = false;
    }
  }

  Future<void> syncEmployees() async {
    final site = selectedSite.value;
    if (site == null) return;

    try {
      isSyncing.value = true;
      setStatus('Syncing employees from server...');
      
      final syncedEmployees = await _employeeRepository.syncEmployeesFromApi(site.id);
      employees.value = syncedEmployees;
      
      setStatus('Synced ${syncedEmployees.length} employees');
      setLastDbSync();
    } catch (e) {
      errorMessage.value = 'Sync failed: $e';
    } finally {
      isSyncing.value = false;
    }
  }

  // DEVICE MANAGEMENT
  Future<void> connectDevice() async {
    try {
      isSearching.value = true;
      setStatus('Searching for device...');
      
      final connected = await _deviceService.connect();
      isConnected.value = connected;
      
      if (connected) {
        setStatus('Device connected successfully');
        await startScanning();
      } else {
        setStatus('Device not found');
      }
    } catch (e) {
      errorMessage.value = 'Device connection failed: $e';
      isConnected.value = false;
    } finally {
      isSearching.value = false;
    }
  }

  Future<void> disconnectDevice() async {
    try {
      await stopScanning();
      await _deviceService.disconnect();
      isConnected.value = false;
      setStatus('Device disconnected');
    } catch (e) {
      errorMessage.value = 'Disconnect failed: $e';
    }
  }

  // SCANNING MANAGEMENT
  Future<void> startScanning() async {
    if (!isConnected.value || isScanning.value) return;

    try {
      isScanning.value = true;
      await _deviceService.startScanningMode();
      setStatus('Scanner ready - place finger on scanner');
      
      // Start continuous scanning
      _scanContinuously();
    } catch (e) {
      errorMessage.value = 'Failed to start scanning: $e';
      isScanning.value = false;
    }
  }

  Future<void> stopScanning() async {
    try {
      isScanning.value = false;
      await _deviceService.stopScanningMode();
      setStatus('Scanning stopped');
    } catch (e) {
      errorMessage.value = 'Failed to stop scanning: $e';
    }
  }

  Future<void> _scanContinuously() async {
    while (isScanning.value && isConnected.value) {
      try {
        final template = await _deviceService.scanFingerprint();
        if (template != null) {
          await _processScanResult(template);
          break; // Exit scanning loop after successful scan
        }
        
        // Small delay before next scan attempt
        await Future.delayed(const Duration(milliseconds: 250));
      } catch (e) {
        errorMessage.value = 'Scanning error: $e';
        break;
      }
    }
  }

  Future<void> _processScanResult(Uint8List template) async {
    try {
      setStatus('Processing fingerprint...');
      
      final scanResult = await _deviceService.matchFingerprint(template, employees);
      lastScanResult.value = scanResult;
      
      if (scanResult.isSuccess && scanResult.employee != null) {
        await _recordAttendance(scanResult.employee!);
        setStatus('Welcome, ${scanResult.employee!.name}!');
      } else {
        setStatus(scanResult.errorMessage ?? 'Fingerprint not recognized');
      }
    } catch (e) {
      errorMessage.value = 'Failed to process scan: $e';
    }
  }

  // ATTENDANCE MANAGEMENT
  Future<void> _recordAttendance(Employee employee) async {
    try {
      final site = selectedSite.value;
      if (site == null) return;

      // Determine attendance type based on latest attendance
      final latestAttendance = await _attendanceRepository.getLatestAttendanceForEmployee(
        employee.id, 
        site.id
      );
      
      final attendanceType = _determineAttendanceType(latestAttendance);
      
      final attendance = Attendance(
        employeeId: employee.id,
        employeeName: employee.name,
        siteId: site.id,
        timestamp: DateTime.now(),
        type: attendanceType,
      );

      debugPrint(
        '[MVP_ATTENDANCE] Saving ${attendanceType.displayName} employee=${employee.name}(${employee.id}) '
        'site=${site.id} ts=${attendance.timestamp.toIso8601String()}',
      );

      await _attendanceRepository.saveAttendance(attendance);

      debugPrint(
        '[MVP_ATTENDANCE] Saved ${attendanceType.displayName} employee=${employee.name}(${employee.id}) '
        'site=${site.id} ts=${attendance.timestamp.toIso8601String()}',
      );

      setStatus('${attendanceType.displayName} recorded for ${employee.name}');
      
      // Navigate to dashboard (would be handled by view)
      Get.toNamed(AppRoutes.dashboard, arguments: {
        'employee': employee,
        'attendance': attendance,
      });
      
    } catch (e) {
      errorMessage.value = 'Failed to record attendance: $e';
    }
  }

  AttendanceType _determineAttendanceType(Attendance? latestAttendance) {
    if (latestAttendance == null) {
      return AttendanceType.timeInMorning;
    }

    final now = DateTime.now();
    final isAfternoon = now.hour >= 12;

    switch (latestAttendance.type) {
      case AttendanceType.timeInMorning:
        return isAfternoon 
            ? AttendanceType.timeInAfternoon 
            : AttendanceType.timeOutMorning;
      case AttendanceType.timeOutMorning:
        return AttendanceType.timeInAfternoon;
      case AttendanceType.timeInAfternoon:
        return AttendanceType.timeOutAfternoon;
      case AttendanceType.timeOutAfternoon:
        return AttendanceType.timeInMorning; // Next day
    }
  }

  // AUTO SYNC
  void _startAutoSync() {
    _syncTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (!isSyncing.value) {
        await _backgroundSync();
      }
    });
  }

  Future<void> _backgroundSync() async {
    try {
      // Sync pending attendance to server
      await _attendanceRepository.syncPendingAttendanceToApi();
      
      // Update last sync time
      setLastDbSync();
    } catch (e) {
      // Silent fail for background sync
      debugPrint('Background sync failed: $e');
    }
  }

  // UTILITY METHODS
  void setStatus(String status) {
    statusMessage.value = status;
  }

  void setLastDbSync([DateTime? syncedAt]) {
    final dateTime = syncedAt ?? DateTime.now();
    final hour12 = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    lastDbSyncLabel.value =
        'Last DB Sync: ${hour12.toString().padLeft(2, '0')}:$minute:$second $period';
  }

  void clearError() {
    errorMessage.value = '';
  }

  // MANUAL ACTIONS
  Future<void> manualSync() async {
    await syncEmployees();
  }

  Future<void> restartScanning() async {
    await stopScanning();
    await Future.delayed(const Duration(milliseconds: 500));
    await startScanning();
  }
}