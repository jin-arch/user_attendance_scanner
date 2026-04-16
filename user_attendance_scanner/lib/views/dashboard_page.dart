// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../legacy_home_page_controller.dart';
import '../route_observer.dart';
import '../services/local_db.dart';
import '../zkfp/zkteco_usb.dart';
import 'enrollment_page.dart';

class DashboardPage extends StatefulWidget {
  final String? resultType; // 'timeInSuccess', 'timeOutSuccess', 'alreadyTimedIn', etc.
  final String? timeIn; // Actual time in value to display
  final String? timeOut; // Actual time out value to display

  const DashboardPage({
    super.key,
    this.employeeId,
    this.employeeName,
    this.attendanceType,
    this.matchedAt,
    this.siteId,
    this.onPortalTap,
    this.onEnrollNowTap,
    this.resultType,
    this.timeIn,
    this.timeOut,
  });

  final String? employeeId;
  final String? employeeName;
  final String? attendanceType;
  final DateTime? matchedAt;
  final String? siteId;
  final VoidCallback? onPortalTap;
  final VoidCallback? onEnrollNowTap;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with RouteAware {
  // Device and scanning
  final ZKTecoUSB _device = ZKTecoUSB();
  late final LegacyHomePageController _controller;
  Timer? _scanTimer;
  bool _ownsTemplateCallback = false;
  bool _isProcessingTemplate = false;
  DateTime? _lastTemplateHandledAt;
  bool _routeSubscribed = false;
  bool _isActiveRoute = true;
  void Function(Uint8List template, int size)? _templateHandler;
  
  // Employee database for fingerprint matching
  final Map<int, _EmployeeEntry> _employeeDb = {};
  final Map<String, _EmployeeEntry> _employeeDbByFid = {};
  
  List<_DashboardRow> _rows = const [];
  bool _loadingRows = true;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  Timer? _afkTimer;
  DateTime? _lastActivityTime;
  static const int _afkTimeoutSeconds = 60; // 1 minute AFK timeout
  
  bool _alreadyTimedIn = false;
  Uint8List? _profilePhoto;

  bool get _isPortalMode => widget.onPortalTap != null;

  // Dashboard is display + actions (Portal + Enroll Now). Fingerprint scanning/identify
  // happens on HomePage (scan) and EnrollmentPage (enroll/reset).
  bool get _enableScanning => true;

  String _initialsFromName(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed.toUpperCase() == 'UNKNOWN USER') return '';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  Future<void> _loadProfilePhoto() async {
    final employeeId = widget.employeeId?.trim();
    if (employeeId == null || employeeId.isEmpty) {
      if (_profilePhoto != null && mounted) {
        setState(() => _profilePhoto = null);
      }
      return;
    }
    final siteId = widget.siteId ?? 'default';
    final photo = await LocalDb.getEmployeePhoto(
      employeeId: employeeId,
      siteId: siteId,
    );
    if (!mounted) return;
    setState(() => _profilePhoto = photo);
  }

  @override
  void initState() {
    super.initState();
    
    // Controller is provided by AppBinding (MVP-style DI)
    _controller = Get.find<LegacyHomePageController>();
    
    // Only set up device callbacks and scanning if this Dashboard instance is
    // intended to be a scanning surface (standalone, not result display).
    if (_enableScanning) {
      if (ZKTecoUSB.isAndroidPlatform) {
        _ownsTemplateCallback = true;
        _templateHandler = (template, size) {
          _handleAndroidTemplate(template);
        };
        _device.onTemplateExtracted = _templateHandler;
      }
    }
    
    // Defer loading to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadRows();
        if (_enableScanning) {
          _loadEmployeeDatabase();
        }
        _loadProfilePhoto();
      }
    });
    
    _lastActivityTime = DateTime.now();
    _startAfkTimer();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    
    // Start scanning if device is connected (deferred) - only when scanning is enabled
    if (_enableScanning && _device.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Reset scanning state to ensure scan loop can start fresh
          _controller.setScanning(false);
          _startScanLoop();
        }
      });
    }
    
    // Show result modal if resultType is provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showResultModalIfNeeded();
    });
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.employeeId != widget.employeeId ||
        oldWidget.siteId != widget.siteId ||
        oldWidget.attendanceType != widget.attendanceType ||
        oldWidget.matchedAt != widget.matchedAt ||
        oldWidget.resultType != widget.resultType;
    if (changed) {
      // Use addPostFrameCallback to avoid calling setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadRows();
        _loadProfilePhoto();
        _showResultModalIfNeeded();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_routeSubscribed) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) {
        routeObserver.subscribe(this, route);
        _routeSubscribed = true;
        _isActiveRoute = route.isCurrent;
      }
    }
    // Reload data when page becomes visible (deferred to avoid setState during build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadRows();
        _loadProfilePhoto();
        if (_enableScanning && _device.isConnected && _isActiveRoute) {
          _startScanLoop();
        }
      }
    });
  }

  @override
  void didPushNext() {
    _isActiveRoute = false;
    _stopScanLoop();
    if (_ownsTemplateCallback && ZKTecoUSB.isAndroidPlatform) {
      if (_device.onTemplateExtracted == _templateHandler) {
        _device.onTemplateExtracted = null;
      }
    }
  }

  @override
  void didPopNext() {
    _isActiveRoute = true;
    if (_ownsTemplateCallback && ZKTecoUSB.isAndroidPlatform) {
      _templateHandler ??= (template, size) {
        _handleAndroidTemplate(template);
      };
      _device.onTemplateExtracted = _templateHandler;
    }
    if (_enableScanning && _device.isConnected) {
      _controller.setScanning(false);
      _startScanLoop();
    }
  }

  @override
  void dispose() {
    // Only stop scan loop if scanning was enabled for this instance.
    if (_enableScanning) {
      _stopScanLoop();
    }

    // Only clear callback if this page owned it.
    if (_ownsTemplateCallback && ZKTecoUSB.isAndroidPlatform) {
      if (_device.onTemplateExtracted == _templateHandler) {
        _device.onTemplateExtracted = null;
      }
    }
    if (_routeSubscribed) {
      routeObserver.unsubscribe(this);
    }
    _afkTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }
  
  // ==================== Fingerprint Scanning ====================
  
  void _handleAndroidTemplate(Uint8List template) {
    if (!mounted) return;
    if (!ZKTecoUSB.isAndroidPlatform) return;
    if (!_isActiveRoute) return;
    if (!_device.isConnected) return;
    
    final now = DateTime.now();
    final lastAt = _lastTemplateHandledAt;
    if (lastAt != null && now.difference(lastAt).inMilliseconds < 800) return;
    if (_isProcessingTemplate) return;
    
    _lastTemplateHandledAt = now;
    _isProcessingTemplate = true;
    
    Future(() async {
      try {
        await _onTemplateReady(template);
      } finally {
        if (mounted && _device.isConnected && _isActiveRoute) {
          _controller.setScanning(true);
        }
        _isProcessingTemplate = false;
      }
    });
  }
  
  Future<void> _loadEmployeeDatabase() async {
    try {
      final siteId = widget.siteId;
      if (siteId == null) return;
      print('[DASHBOARD_SCAN] Loading employees for site: $siteId');
      final rows = await LocalDb.getEmployeesBySite(siteId);
      print('[DASHBOARD_SCAN] Found ${rows.length} employee rows from DB');
      _employeeDb.clear();
      _employeeDbByFid.clear();
      
      for (final row in rows) {
        // Correct column names from DB: fid, employee_id, employee_name, finger_template
        final fid = row['fid'] as int?;
        final empId = row['employee_id']?.toString() ?? '';
        final empName = row['employee_name']?.toString() ?? '';
        final templateBytes = row['finger_template'] as Uint8List?;
        
        print('[DASHBOARD_SCAN] Employee row: fid=$fid, empId=$empId, name=$empName, hasTemplate=${templateBytes != null}');
        
        if (fid != null && empId.isNotEmpty && templateBytes != null) {
          try {
            await _device.registerFingerprint(fid, templateBytes);
            final entry = _EmployeeEntry(id: empId, name: empName);
            _employeeDb[fid] = entry;
            _employeeDbByFid[fid.toString()] = entry;
            print('[DASHBOARD_SCAN] Registered fingerprint for fid=$fid');
          } catch (e) {
            print('[DASHBOARD_SCAN] Error registering fingerprint for fid=$fid: $e');
          }
        }
      }
      print('[DASHBOARD_SCAN] Loaded ${_employeeDb.length} employees');
    } catch (e) {
      print('[DASHBOARD_SCAN] Error loading employees: $e');
    }
  }
  
  void _startScanLoop() {
    if (!_isActiveRoute) return;
    if (_controller.isScanning.value || !_device.isConnected) return;
    
    // Use addPostFrameCallback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.setScanning(true);
    });
    
    if (ZKTecoUSB.isAndroidPlatform) {
      // Android is event-driven via onTemplateExtracted callback
      return;
    }
    
    // Windows: poll the sensor every 250ms
    _scanTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _captureAndMatch();
    });
  }
  
  void _stopScanLoop() {
    _scanTimer?.cancel();
    _scanTimer = null;
    // Use addPostFrameCallback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.setScanning(false);
    });
  }
  
  Future<void> _captureAndMatch() async {
    if (!_controller.isScanning.value || !_device.isConnected) {
      _scanTimer?.cancel();
      _scanTimer = null;
      // Use addPostFrameCallback to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.setScanning(false);
      });
      return;
    }
    final result = _device.acquireFingerprintOnce();
    if (result.template != null) {
      _scanTimer?.cancel();
      _scanTimer = null;
      _onTemplateReady(result.template!);
    }
  }
  
  Future<void> _onTemplateReady(Uint8List template) async {
    print('[DASHBOARD_SCAN] _onTemplateReady called');
    if (!mounted || !_device.isConnected) {
      print('[DASHBOARD_SCAN] Early return: mounted=$mounted, isConnected=${_device.isConnected}');
      return;
    }
    
    // Use addPostFrameCallback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.setScanning(false);
    });
    
    String? fid;
    if (ZKTecoUSB.isAndroidPlatform) {
      print('[DASHBOARD_SCAN] Calling identifyFingerprint...');
      final res = await _device.identifyFingerprint();
      print('[DASHBOARD_SCAN] identifyFingerprint result: found=${res.found}, fid=${res.fid}');
      if (res.found) fid = res.fid;
    } else {
      final res = _device.identifyTemplate(template);
      if (res.fingerId != null) fid = res.fingerId.toString();
    }
    
    print('[DASHBOARD_SCAN] Employee DB size: ${_employeeDb.length}, ByFid size: ${_employeeDbByFid.length}');
    print('[DASHBOARD_SCAN] Looking for fid: "$fid"');
    
    final fingerId = fid != null ? int.tryParse(fid.trim()) : null;
    _EmployeeEntry? employee =
        (fid != null ? _employeeDbByFid[fid.trim()] : null) ??
        (fingerId != null ? _employeeDb[fingerId] : null) ??
        (fingerId != null ? _employeeDbByFid[fingerId.toString()] : null);
    
    print('[DASHBOARD_SCAN] Employee found: ${employee != null}, id=${employee?.id}, name=${employee?.name}');
    
    if (employee == null) {
      print('[DASHBOARD_SCAN] Employee not found - showing fingerprint not recognized');
      // Show fingerprint not recognized error
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _isActiveRoute = false;
          _stopScanLoop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardPage(
                siteId: widget.siteId,
                resultType: 'fingerprintNotRecognized',
              ),
            ),
          );
        }
      });
      return;
    }
    
    // Record attendance
    print('[DASHBOARD_SCAN] Recording attendance for employee: ${employee.id}');
    final attendanceType = await _recordAttendance(employee.id);
    print('[DASHBOARD_SCAN] Attendance result: $attendanceType');
    
    if (attendanceType == 'TIME IN' || attendanceType == 'TIME OUT') {
      final resultTypeStr = attendanceType == 'TIME OUT' 
          ? 'timeOutSuccess' 
          : 'timeInSuccess';
      final now = DateTime.now();
      
      // Navigate to dashboard with new attendance info
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _isActiveRoute = false;
          _stopScanLoop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardPage(
                employeeId: employee.id,
                employeeName: employee.name,
                attendanceType: attendanceType,
                matchedAt: now,
                siteId: widget.siteId,
                resultType: resultTypeStr,
                timeIn: attendanceType == 'TIME OUT' ? null : _formatTimeOnly(now),
                timeOut: attendanceType == 'TIME OUT' ? _formatTimeOnly(now) : null,
              ),
            ),
          );
        });
      }
    } else {
      // Handle error cases - map error strings to result types like HomePage does
      String resultTypeStr;
      print('[DASHBOARD_ERROR] attendanceType=$attendanceType');
      if (attendanceType == 'ALREADY IN') {
        resultTypeStr = 'alreadyTimedIn';
      } else if (attendanceType == 'ALREADY OUT - Come back tomorrow') {
        resultTypeStr = 'alreadyTimedOut';
      } else if (attendanceType?.startsWith('IN') == true) {
        resultTypeStr = 'timeInUnsuccessful';
      } else if (attendanceType?.startsWith('OUT') == true) {
        resultTypeStr = 'timeOutUnsuccessful';
      } else {
        resultTypeStr = 'timeInUnsuccessful';
      }
      print('[DASHBOARD_ERROR] resultTypeStr=$resultTypeStr');
      
      // Navigate to dashboard with error result type to show modal
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _isActiveRoute = false;
          _stopScanLoop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardPage(
                employeeId: employee.id,
                employeeName: employee.name,
                attendanceType: attendanceType,
                matchedAt: DateTime.now(),
                siteId: widget.siteId,
                resultType: resultTypeStr,
              ),
            ),
          );
        });
      }
    }
  }
  
  Future<String?> _recordAttendance(String employeeId) async {
    final siteId = widget.siteId?.toString();
    print('[RECORD] ========================================');
    print('[RECORD] siteId=$siteId employeeId=$employeeId');
    print('[RECORD] ========================================');
    if (siteId == null || siteId.isEmpty) return 'NO SITE';
    
    try {
      print('[DASHBOARD_RECORD] Calling _buildPendingTimeLog...');
      final pending = await _buildPendingTimeLog(
        employeeId: employeeId,
        siteId: siteId,
        now: DateTime.now(),
      );
      
      print('[DASHBOARD_RECORD] _buildPendingTimeLog returned code: ${pending.code}');
      print(
        '[DASHBOARD_RECORD] pending fields: date=${pending.timeLogDate} code=${pending.code} '
        'inAM=${pending.timeInMorning} outAM=${pending.timeOutMorning} '
        'inPM=${pending.timeInAfternoon} outPM=${pending.timeOutAfternoon}',
      );
      
      print('[DASHBOARD_RECORD] Saving timelog with siteId=$siteId, employeeId=$employeeId');
      await LocalDb.saveTimelog(
        siteId: siteId,
        employeeId: employeeId,
        timelogData: {
          'timelogID': pending.timeLogId,
          'timelog': pending.timeLogDate,
          'timeLogDate': pending.timeLogDate,
          'timeInMorning': pending.timeInMorning,
          'timeOutMorning': pending.timeOutMorning,
          'timeInAfternoon': pending.timeInAfternoon,
          'timeOutAfternoon': pending.timeOutAfternoon,
          'remarks': pending.remarks,
          'schedule': pending.schedule,
          'code': pending.code,
        },
      );
      
      // Add a small delay to ensure database write completes
      await Future.delayed(Duration(milliseconds: 500));
      
      print('[DASHBOARD_RECORD] SUCCESS: code=${pending.code}');
      return pending.code.startsWith('IN') ? 'TIME IN' : 'TIME OUT';
    } catch (e) {
      final errorMsg = e.toString();
      print('[DASHBOARD_RECORD] Caught exception: $errorMsg');
      if (errorMsg.contains('ALREADY_OUT_TODAY')) {
        return 'ALREADY OUT - Come back tomorrow';
      } else if (errorMsg.contains('ALREADY_IN')) {
        print('[DASHBOARD_RECORD] Returning: ALREADY IN');
        return 'ALREADY IN';
      }
      print('[DASHBOARD_RECORD] Returning: TIME IN UNSUCCESSFUL');
      return 'TIME IN UNSUCCESSFUL';
    }
  }
  
  String _formatDateOnly(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
  
  String _formatTimeOnly(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    final s = date.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _getDayName(DateTime date) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
  
  Future<_PendingTimeLog> _buildPendingTimeLog({
    required String employeeId,
    required String siteId,
    required DateTime now,
  }) async {
    final date = _formatDateOnly(now);
    final time = _formatTimeOnly(now);
    
    print('[TIMELOG] ===== START employeeId=$employeeId siteId=$siteId date=$date =====');
    
    // Dump all records for debugging
    await LocalDb.debugDumpAllTimelogs();
    
    final cached = await LocalDb.getLatestTimelogForEmployee(
      siteId: siteId,
      employeeId: employeeId,
    );
    
    print('[TIMELOG] cached from DB: ${cached != null ? "FOUND" : "NULL"}');
    if (cached != null) {
      print('[TIMELOG] cached keys: ${cached.keys}');
      print('[TIMELOG] cached full data: $cached');
      print('[TIMELOG] timeInMorning value: "${cached['timeInMorning']}"');
    }
    
    // Check if cached data is from today
    final cachedDate = cached?['timeLogDate']?.toString() ?? cached?['timelog']?.toString() ?? '';
    final isToday = cachedDate == date;
    print('[TIMELOG] cachedDate=$cachedDate, today=$date, isToday=$isToday');
    
    // Only use cached data if it's from today
    final todayCache = isToday ? cached : null;
    
    // FALLBACK: If we have a recent record with timeInMorning, check it regardless of date
    // This is a temporary fix to handle the 3-scan issue
    if (cached != null && !isToday) {
      final recentTimeIn = cached['timeInMorning']?.toString();
      if (recentTimeIn != null && recentTimeIn.isNotEmpty && recentTimeIn != '00:00:00') {
        print('[TIMELOG] FALLBACK: Found recent timeInMorning, checking if within 5 minutes');
        final recentDate = cached['timeLogDate']?.toString() ?? cached['timelog']?.toString() ?? '';
        if (recentDate.isNotEmpty) {
          try {
            final recentDateTime = DateTime.tryParse('${recentDate}T$recentTimeIn');
            if (recentDateTime != null) {
              final diffMinutes = now.difference(recentDateTime).inMinutes;
              print('[TIMELOG] FALLBACK: diffMinutes=$diffMinutes');
              if (diffMinutes < 30) { // Within 30 minutes, treat as already timed in
                print('[TIMELOG] FALLBACK: THROWING ALREADY_IN (recent scan within 30 min)');
                throw Exception('ALREADY_IN');
              }
            }
          } catch (e) {
            print('[TIMELOG] FALLBACK: Error parsing recent time: $e');
          }
        }
      }
    }
    
    final timeLogId = (todayCache?['timelogID'] ?? todayCache?['remark'] ?? '').toString();
    final remarks = (todayCache?['remarks'] ?? todayCache?['remark'] ?? '').toString();
    final schedule = (todayCache?['schedule'] ?? todayCache?['schedCode'] ?? '')
        .toString();

    print('[DASHBOARD_TIMELOG] Raw cached values (today only):');
    print('  timeInMorning: ${todayCache?['timeInMorning']}');
    print('  timeOutMorning: ${todayCache?['timeOutMorning']}');
    print('  timeInAfternoon: ${todayCache?['timeInAfternoon']}');
    print('  timeOutAfternoon: ${todayCache?['timeOutAfternoon']}');
    
    final rawInMorning = todayCache?['timeInMorning']?.toString() ?? '';
    final rawOutMorning = todayCache?['timeOutMorning']?.toString() ?? '';
    final rawInAfternoon = todayCache?['timeInAfternoon']?.toString() ?? '';
    final rawOutAfternoon = todayCache?['timeOutAfternoon']?.toString() ?? '';
    
    print('[DASHBOARD_TIMELOG] Raw strings: inM="$rawInMorning", outM="$rawOutMorning", inA="$rawInAfternoon", outA="$rawOutAfternoon"');
    print('[DASHBOARD_TIMELOG] _isBlank checks: inM=${_isBlank(rawInMorning)}, outM=${_isBlank(rawOutMorning)}, inA=${_isBlank(rawInAfternoon)}, outA=${_isBlank(rawOutAfternoon)}');

    final existingInMorning = _isBlank(rawInMorning) ? null : rawInMorning;
    final existingOutMorning = _isBlank(rawOutMorning) ? null : rawOutMorning;
    final existingInAfternoon = _isBlank(rawInAfternoon) ? null : rawInAfternoon;
    final existingOutAfternoon = _isBlank(rawOutAfternoon) ? null : rawOutAfternoon;

    print('[DASHBOARD_TIMELOG] Parsed existing values: inM=$existingInMorning, outM=$existingOutMorning, inA=$existingInAfternoon, outA=$existingOutAfternoon');

    // If there is any TIME OUT recorded today (AM or PM), the day is complete.
    // The next TIME IN is only allowed on a new day.
    if (existingOutMorning != null || existingOutAfternoon != null) {
      print('[DASHBOARD_TIMELOG] THROWING ALREADY_OUT_TODAY');
      throw Exception('ALREADY_OUT_TODAY');
    }

    // Cooldown applies only when we are about to do a TIME OUT.
    DateTime? lastTimeInForCooldown;
    if (existingInMorning != null && existingOutMorning == null) {
      lastTimeInForCooldown = DateTime.tryParse('${date}T$existingInMorning');
    } else if (existingInAfternoon != null && existingOutAfternoon == null) {
      lastTimeInForCooldown = DateTime.tryParse('${date}T$existingInAfternoon');
    }

    if (lastTimeInForCooldown != null) {
      final diffMinutes = now.difference(lastTimeInForCooldown).inMinutes;
      print('[DASHBOARD_TIMELOG] Time since last time-in: $diffMinutes minutes');
      if (diffMinutes < 5) {
        print('[DASHBOARD_TIMELOG] THROWING ALREADY_IN (within 5 min cooldown)');
        throw Exception('ALREADY_IN');
      }
    }

    print('[DASHBOARD_TIMELOG] Decision path check: existingInMorning=$existingInMorning, existingOutMorning=$existingOutMorning');

    if (existingInMorning == null) {
      print('[DASHBOARD_TIMELOG] DECISION: Returning IN_AM');
      return _PendingTimeLog(
        timeLogId: timeLogId,
        timeLogDate: date,
        remarks: remarks,
        schedule: schedule,
        code: 'IN_AM',
        timeInMorning: time,
        timeOutMorning: existingOutMorning,
        timeInAfternoon: existingInAfternoon,
        timeOutAfternoon: existingOutAfternoon,
      );
    }
    if (existingOutMorning == null) {
      print('[DASHBOARD_TIMELOG] Decision: Returning OUT_AM because existingOutMorning is null');
      return _PendingTimeLog(
        timeLogId: timeLogId,
        timeLogDate: date,
        remarks: remarks,
        schedule: schedule,
        code: 'OUT_AM',
        timeInMorning: existingInMorning,
        timeOutMorning: time,
        timeInAfternoon: existingInAfternoon,
        timeOutAfternoon: existingOutAfternoon,
      );
    }
    if (existingInAfternoon == null) {
      print('[DASHBOARD_TIMELOG] Returning IN_PM');
      return _PendingTimeLog(
        timeLogId: timeLogId,
        timeLogDate: date,
        remarks: remarks,
        schedule: schedule,
        code: 'IN_PM',
        timeInMorning: existingInMorning,
        timeOutMorning: existingOutMorning,
        timeInAfternoon: time,
        timeOutAfternoon: existingOutAfternoon,
      );
    }

    print('[DASHBOARD_TIMELOG] Returning OUT_PM');
    return _PendingTimeLog(
      timeLogId: timeLogId,
      timeLogDate: date,
      remarks: remarks,
      schedule: schedule,
      code: 'OUT_PM',
      timeInMorning: existingInMorning,
      timeOutMorning: existingOutMorning,
      timeInAfternoon: existingInAfternoon,
      timeOutAfternoon: time,
    );
  }
  
  void _showResultModalIfNeeded() {
    final type = widget.resultType;
    if (type == null || type.isEmpty) return;
    
    String title;
    String subtitle;
    String buttonText;
    Color buttonColor;
    Color iconBgColor;
    Color iconColor;
    IconData iconData;
    
    switch (type) {
      case 'timeInSuccess':
        title = 'TIME IN SUCCESSFUL';
        subtitle = 'Your time in has been recorded successfully. Wishing you a productive day!';
        buttonText = 'PROCEED';
        buttonColor = const Color(0xFF90EE90);
        iconBgColor = const Color(0xFF90EE90).withValues(alpha: 0.3);
        iconColor = const Color(0xFF2E7D32);
        iconData = Icons.check_circle;
        break;
      case 'timeOutSuccess':
        title = 'TIME OUT SUCCESSFUL';
        subtitle = 'Your time out has been recorded successfully. Wishing you a productive day!';
        buttonText = 'PROCEED';
        buttonColor = const Color(0xFF90EE90);
        iconBgColor = const Color(0xFF90EE90).withValues(alpha: 0.3);
        iconColor = const Color(0xFF2E7D32);
        iconData = Icons.check_circle;
        break;
      case 'alreadyTimedIn':
        title = 'ALREADY TIMED IN';
        subtitle = 'You have already timed in. Please wait 5 minutes to time out.';
        buttonText = 'Close';
        buttonColor = const Color(0xFFA3C9FF);
        iconBgColor = const Color(0xFFA3C9FF).withValues(alpha: 0.3);
        iconColor = const Color(0xFF1565C0);
        iconData = Icons.info;
        break;
      case 'alreadyTimedOut':
        title = 'ALREADY TIMED OUT';
        subtitle = 'You have already timed out for today. Please come back tomorrow.';
        buttonText = 'Close';
        buttonColor = const Color(0xFFA3C9FF);
        iconBgColor = const Color(0xFFA3C9FF).withValues(alpha: 0.3);
        iconColor = const Color(0xFF1565C0);
        iconData = Icons.info;
        break;
      case 'wait5Minutes':
        title = 'PLEASE WAIT';
        subtitle = 'You must wait 5 minutes after time in before you can time out.';
        buttonText = 'Close';
        buttonColor = const Color(0xFFFFB74D);
        iconBgColor = const Color(0xFFFFB74D).withValues(alpha: 0.3);
        iconColor = const Color(0xFFEF6C00);
        iconData = Icons.access_time;
        break;
      case 'timeInUnsuccessful':
        title = 'TIME IN UNSUCCESSFUL';
        subtitle = "We couldn't process your request. Please try again.";
        buttonText = 'RETRY';
        buttonColor = const Color(0xFFFFA0A0);
        iconBgColor = const Color(0xFFFFA0A0).withValues(alpha: 0.3);
        iconColor = const Color(0xFFC62828);
        iconData = Icons.error;
        break;
      case 'timeOutUnsuccessful':
        title = 'TIME OUT UNSUCCESSFUL';
        subtitle = "We couldn't process your request. Please try again.";
        buttonText = 'RETRY';
        buttonColor = const Color(0xFFFFA0A0);
        iconBgColor = const Color(0xFFFFA0A0).withValues(alpha: 0.3);
        iconColor = const Color(0xFFC62828);
        iconData = Icons.error;
        break;
      case 'fingerprintNotRecognized':
      default:
        title = 'FINGERPRINT NOT RECOGNIZED';
        subtitle = "We couldn't recognize your fingerprint. Please try again.";
        buttonText = 'RETRY';
        buttonColor = const Color(0xFFFFE4D6);
        iconBgColor = const Color(0xFFFFE4D6).withValues(alpha: 0.3);
        iconColor = const Color(0xFFEF6C00);
        iconData = Icons.fingerprint;
        break;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    iconData,
                    color: iconColor,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 120,
                  height: 32,
                    child: ElevatedButton(
                      onPressed: () {
                        _resetAfkTimer(); // Reset AFK timer when user interacts
                        Navigator.of(context).pop();
                        if (_enableScanning && _device.isConnected) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _controller.setScanning(false);
                              _startScanLoop();
                            }
                          });
                        }
                      },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonColor,
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      buttonText,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  void _startAfkTimer() {
    _afkTimer?.cancel();
    _afkTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lastActivityTime != null) {
        final elapsed = DateTime.now().difference(_lastActivityTime!).inSeconds;
        if (elapsed >= _afkTimeoutSeconds) {
          _afkTimer?.cancel();
          if (mounted) {
            _returnToScanner();
          }
        }
      }
    });
  }
  
  void _returnToScanner() {
    // Show brief message before returning
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Returning to scanner...'),
        duration: Duration(milliseconds: 800),
        backgroundColor: Colors.blue,
      ),
    );
    
    // Small delay then navigate back
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        // Pop back to home page (which is now safely in the navigation stack)
        Navigator.of(context).pop();
      }
    });
  }
  
  void _resetAfkTimer() {
    setState(() => _lastActivityTime = DateTime.now());
  }
  
  Future<void> _checkAlreadyTimedIn() async {
    // Disabled - no "already timed in" warning needed
    setState(() {
      _alreadyTimedIn = false;
    });
  }

  Future<void> _loadRows() async {
    final siteId = widget.siteId;
    // ...
    final employeeId = widget.employeeId;
    if (siteId == null ||
        siteId.isEmpty ||
        employeeId == null ||
        employeeId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _loadingRows = false;
      });
      return;
    }

    // Longer delay to ensure any pending save completes
    await Future.delayed(const Duration(milliseconds: 1000));

    try {
      print('[DASHBOARD_LOAD] ===== LOADING HISTORY =====');
      print('[DASHBOARD_LOAD] siteId="$siteId" employeeId="$employeeId"');
      
      // First dump all records to see what's in the database
      await LocalDb.debugDumpAllTimelogs();
      
      final history = await LocalDb.getTimelogHistoryForEmployee(
        siteId: siteId,
        employeeId: employeeId,
        limit: 10,
      );
      print('[DASHBOARD_LOAD] Loaded ${history.length} rows for employeeId="$employeeId" on siteId="$siteId"');
      for (var row in history) {
        print('[DASHBOARD_LOAD] Row raw: $row');
      }
      if (!mounted) return;
      
      final rows = history.map(_rowFromTimelog).toList();
      
      // Check if today's row exists and update/create as needed
      final today = _formatDateOnly(DateTime.now());
      final todayIndex = rows.indexWhere((r) => r.rawDate == today);
      
      if (todayIndex >= 0) {
        // Today's row exists - update it with passed values if needed
        final todayRow = rows[todayIndex];
        final todayLog = todayRow.timeLogs.split('|');
        String timeIn = todayLog.isNotEmpty ? todayLog.first.trim() : '-';
        String timeOut = todayLog.length > 1 ? todayLog[1].trim() : '-';
        
        // Override with passed values if they exist
        if (widget.timeIn != null) timeIn = widget.timeIn!;
        if (widget.timeOut != null) timeOut = widget.timeOut!;
        
        final hasIn = timeIn != '-' && timeIn.isNotEmpty;
        final hasOut = timeOut != '-' && timeOut.isNotEmpty;
        final status = hasIn && hasOut ? 'COMPLETE' : (hasIn ? 'INCOMPLETE' : 'NO LOG');
        
        rows[todayIndex] = _DashboardRow(
          rawDate: todayRow.rawDate,
          date: todayRow.date,
          day: todayRow.day,
          shift: todayRow.shift,
          timeLogs: '$timeIn | $timeOut',
          status: status,
          isComplete: status == 'COMPLETE',
        );
        print('[DASHBOARD_LOAD] Updated today row at index $todayIndex with status $status');
      } else if (widget.timeIn != null || widget.timeOut != null) {
        // No today's row but we have passed values - create one
        final timeIn = widget.timeIn ?? '-';
        final timeOut = widget.timeOut ?? '-';
        final hasIn = timeIn != '-' && timeIn.isNotEmpty;
        final hasOut = timeOut != '-' && timeOut.isNotEmpty;
        final status = hasIn && hasOut ? 'COMPLETE' : (hasIn ? 'INCOMPLETE' : 'NO LOG');
        
        rows.insert(0, _DashboardRow(
          rawDate: today,
          date: _formatDate(DateTime.now()),
          day: _getDayName(DateTime.now()).toUpperCase(),
          shift: '-',
          timeLogs: '$timeIn | $timeOut',
          status: status,
          isComplete: status == 'COMPLETE',
        ));
        print('[DASHBOARD_LOAD] Created today row with status $status');
      }
      
      setState(() {
        _rows = rows;
        _loadingRows = false;
      });
      
      // Disabled - no "already timed in" warning needed
      await _checkAlreadyTimedIn();
    } catch (e) {
      print('[DASHBOARD_LOAD] Error: $e');
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _loadingRows = false;
      });
    }
  }

  String _pickFirst(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return '';
  }

  bool _isBlank(String value) {
    final text = value.trim();
    return text.isEmpty ||
        text == '00:00:00' ||
        text == '0' ||
        text.toLowerCase() == 'null';
  }

  DateTime? _parseDate(String text) =>
      text.isEmpty ? null : DateTime.tryParse(text);

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _rowDateKey(_DashboardRow row) {
    final parsed = DateTime.tryParse(row.rawDate);
    if (parsed != null) return _dateKey(parsed);
    if (row.rawDate.length >= 10) return row.rawDate.substring(0, 10);
    return row.rawDate;
  }

  String _formatDate(DateTime date) {
    const months = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDay(DateTime date) {
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    return days[date.weekday - 1];
  }

  _DashboardRow _rowFromTimelog(Map<String, dynamic> row) {
    final dateText = _pickFirst(row, [
      'timelog',
      'timeLogDate',
      'timelog_date',
      'datecaptured',
      'datelog',
    ]);
    final parsedDate = _parseDate(dateText);
    final timeInMorning = _pickFirst(row, ['timeInMorning', 'timeinmorning']);
    final timeOutMorning = _pickFirst(row, [
      'timeOutMorning',
      'timeoutmorning',
    ]);
    final timeInAfternoon = _pickFirst(row, [
      'timeInAfternoon',
      'timeinafternoon',
    ]);
    final timeOutAfternoon = _pickFirst(row, [
      'timeOutAfternoon',
      'timeoutafternoon',
    ]);
    final firstIn = !_isBlank(timeInMorning)
        ? timeInMorning
        : (!_isBlank(timeInAfternoon) ? timeInAfternoon : '-');
    final lastOut = !_isBlank(timeOutAfternoon)
        ? timeOutAfternoon
        : (!_isBlank(timeOutMorning) ? timeOutMorning : '-');
    final hasIn = !_isBlank(timeInMorning) || !_isBlank(timeInAfternoon);
    final hasOut = !_isBlank(timeOutMorning) || !_isBlank(timeOutAfternoon);
    final status = hasIn && hasOut
        ? 'COMPLETE'
        : (hasIn ? 'INCOMPLETE' : 'NO LOG');

    return _DashboardRow(
      rawDate: dateText,
      date: parsedDate != null
          ? _formatDate(parsedDate)
          : (dateText.isEmpty ? '-' : dateText),
      day: parsedDate != null ? _formatDay(parsedDate) : '-',
      shift: _pickFirst(row, ['schedule', 'schedCode']).isEmpty
          ? '-'
          : _pickFirst(row, ['schedule', 'schedCode']),
      timeLogs: '$firstIn | $lastOut',
      status: status,
      isComplete: status == 'COMPLETE',
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final outerRadius = BorderRadius.circular(w * 0.035);

    return Scaffold(
      backgroundColor: Colors.black,
      // Navigation bar removed - auto-return to home after AFK timeout
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/Main BG.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(w * 0.005),
            child: ClipRRect(
              borderRadius: outerRadius,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/Main BG.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final cw = constraints.maxWidth;
                        final ch = constraints.maxHeight;
                        final ps = (cw * 0.06).clamp(32.0, 56.0);
                        return Stack(
                          children: [
                            _particle(cw, ch, 0.08, 0.15, ps * 1.2, 0),
                            _particle(cw, ch, 0.12, 0.08, ps * 0.5, 0.3),
                            _particle(cw, ch, 0.18, 0.5, ps * 0.9, 0.6),
                            _particle(cw, ch, 0.75, 0.45, ps * 1.1, 0.2),
                            _particle(cw, ch, 0.5, 0.2, ps * 0.55, 0.5),
                            _particle(cw, ch, 0.08, 0.7, ps * 1.0, 0.8),
                            _particle(cw, ch, 0.28, 0.35, ps * 0.45, 0.15),
                            _particle(cw, ch, 0.72, 0.3, ps * 0.9, 0.45),
                            _particle(cw, ch, 0.38, 0.78, ps * 0.6, 0.7),
                            _particle(cw, ch, 0.88, 0.6, ps * 1.15, 0.25),
                            _particle(cw, ch, 0.05, 0.42, ps * 0.5, 0.9),
                            _particle(cw, ch, 0.62, 0.48, ps * 0.75, 0.35),
                            _particle(cw, ch, 0.15, 0.85, ps * 0.7, 0.12),
                            _particle(cw, ch, 0.95, 0.12, ps * 0.8, 0.55),
                            _particle(cw, ch, 0.33, 0.11, ps * 0.6, 0.77),
                            _particle(cw, ch, 0.60, 0.88, ps * 1.0, 0.41),
                            _particle(cw, ch, 0.81, 0.22, ps * 0.5, 0.63),
                            _particle(cw, ch, 0.44, 0.59, ps * 0.9, 0.29),
                            _particle(cw, ch, 0.21, 0.66, ps * 0.8, 0.84),
                            _particle(cw, ch, 0.57, 0.33, ps * 0.7, 0.18),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: w * 0.02,
                      vertical: h * 0.025,
                    ),
                    child: Column(
                      children: [
                        Expanded(flex: 3, child: _buildTopRow(w, h)),
                        SizedBox(height: h * 0.022),
                        Expanded(flex: 2, child: _buildBottomTable(w, h)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _particle(
    double w,
    double h,
    double fracLeft,
    double fracTop,
    double sizePx,
    double phase,
  ) {
    return Positioned(
      left: w * fracLeft - sizePx / 2,
      top: h * fracTop - sizePx / 2,
      width: sizePx,
      height: sizePx,
      child: _DashboardRisingFadeParticle(
        size: sizePx,
        phase: phase,
        assetPath: 'assets/icons/square-particles-fx.svg',
      ),
    );
  }

  Widget _buildTopRow(double w, double h) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileCard(w, h),
        SizedBox(width: w * 0.010),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTimePanel(w, h),
              SizedBox(height: h * 0.03),
              _buildTodayLogCard(w, h),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(double w, double h) {
    final cardRadius = BorderRadius.circular(w * 0.023);
    final expandedPanelColor = const Color(0xFF092238).withValues(alpha: 0.50);

    return ClipRRect(
      borderRadius: cardRadius,
      child: Container(
        width: w * 0.55,
        height: double.infinity,
        color: Colors.transparent,
        child: Row(
          children: [
            Container(
              width: w * 0.2,
              decoration: BoxDecoration(
                color: const Color(0xFF092238).withValues(alpha: 0.7),
                borderRadius: BorderRadius.only(
                  topLeft: cardRadius.topLeft,
                  bottomLeft: cardRadius.bottomLeft,
                  topRight: cardRadius.topRight,
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                     width: w * 0.11,
                     height: w * 0.11,
                     decoration: BoxDecoration(
                       shape: BoxShape.circle,
                       border: Border.all(
                         color: Colors.white.withValues(alpha: 0.85),
                         width: 3,
                       ),
                      gradient: _profilePhoto == null
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF3FA9F5), Color(0xFF1B75BB)],
                            )
                          : null,
                      image: _profilePhoto != null
                          ? DecorationImage(
                              image: MemoryImage(_profilePhoto!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _profilePhoto == null
                        ? Builder(
                            builder: (_) {
                              final initials =
                                  _initialsFromName(widget.employeeName);
                              if (initials.isNotEmpty) {
                                return Text(
                                  initials,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: w * 0.030,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 2,
                                  ),
                                );
                              }
                              return const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 40,
                              );
                            },
                          )
                        : null,
                  ),
                  SizedBox(height: h * 0.012),
                  Text(
                    'PROFILE',
                    style: TextStyle(
                      fontFamily: 'CEORUSE',
                      fontSize: w * 0.012,
                      color: Colors.white.withValues(alpha: 0.8),
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      w * 0.010,
                      h * 0.016,
                      w * 0.005,
                      h * 0.024,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 1,
                          child: GestureDetector(
                            onTap: () {
                              _resetAfkTimer();
                              if (widget.onPortalTap != null) {
                                widget.onPortalTap!();
                              } else {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              }
                            },
                            child: _buildTopPill(
                              w,
                              label: 'PORTAL',
                              active: false,
                            ),
                          ),
                        ),
                        SizedBox(width: w * 0.005),
                        Expanded(
                          flex: 1,
                          child: GestureDetector(
                            onTap: () {
                              _resetAfkTimer();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => EnrollmentPage(
                                    siteId: widget.siteId,
                                    isEditMode: true,
                                    employeeId: widget.employeeId,
                                    employeeName: widget.employeeName,
                                  ),
                                ),
                              );
                            },
                            child: _buildTopPill(
                              w,
                              label: 'ENROLL NOW',
                              active: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: -(w * 0.02),
                          left: 0.1,
                          child: ClipPath(
                            clipper: const _TopLeftCurvedNotchClipper(),
                            child: Container(
                              width: w * 0.039,
                              height: w * 0.020,
                              color: expandedPanelColor,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: expandedPanelColor,
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(w * 0.03),
                                bottomRight: Radius.circular(w * 0.03),
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                w * 0.022,
                                h * 0.016,
                                w * 0.022,
                                h * 0.024,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (widget.employeeName ?? 'UNKNOWN USER')
                                        .toUpperCase(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'TRTCENZODEMO',
                                      fontSize: w * 0.027,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 1.3,
                                    ),
                                  ),
                                  SizedBox(height: h * 0.012),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: w * 0.013,
                                      vertical: h * 0.004,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1D7CFF),
                                      borderRadius: BorderRadius.circular(
                                        w * 0.013,
                                      ),
                                    ),
                                    child: Text(
                                      widget.employeeId ?? 'N/A',
                                      style: TextStyle(
                                        fontFamily: 'CEORUSE',
                                        fontSize: w * 0.013,
                                        color: Colors.white,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: h * 0.012),
                                  Text(
                                    widget.attendanceType ?? 'RECORDED',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontStyle: FontStyle.italic,
                                      fontSize: w * 0.015,
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                  if (_alreadyTimedIn) ...[
                                    SizedBox(height: h * 0.008),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: w * 0.010,
                                        vertical: h * 0.004,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.8),
                                        borderRadius: BorderRadius.circular(w * 0.008),
                                      ),
                                      child: Text(
                                        'ALREADY TIMED IN (within 20 min)',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: w * 0.011,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                  SizedBox(height: h * 0.006),
                                  Text(
                                    'INFORMATION TECHNOLOGY | FAST\nDISTRIBUTION CORPORATION',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: w * 0.014,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 1.7,
                                      height: 1.25,
                                    ),
                                  ),
                                  const Spacer(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPill(
    double w, {
    required String label,
    bool active = false,
    VoidCallback? onTap,
  }) {
    final radius = BorderRadius.circular(w * 0.018);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.01, vertical: w * 0.01),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: active
            ? const Color(0xFF0E1F33).withValues(alpha: 0.50)
            : const Color(0xFF0E1F33).withValues(alpha: 0.50),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'CEORUSE',
            fontSize: w * 0.012,
            color: Colors.white,
            letterSpacing: 0.9,
          ),
        ),
      ),
    );
  }

  Widget _buildTimePanel(double w, double h) {
    final now = _now;
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.020, vertical: h * 0.050),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${hour.toString().padLeft(2, '0')}:$minute $period',
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: w * 0.042,
                  color: Colors.white,
                  letterSpacing: 4,
                  height: 1,
                ),
              ),
              SizedBox(height: h * 0.006),
              Text(
                _formatDate(now),
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: w * 0.020,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 3,
                  height: 1.1,
                ),
              ),
              SizedBox(height: h * 0.002),
              Text(
                _formatDay(now),
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: w * 0.014,
                  color: Colors.white.withValues(alpha: 0.7),
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayLogCard(double w, double h) {
    final now = widget.matchedAt ?? DateTime.now();
    final todayDate = _formatDate(now);
    final todayKey = _dateKey(now);
    final todayRow = _rows.firstWhere(
      (row) => _rowDateKey(row) == todayKey,
      orElse: () => _rows.isNotEmpty
          ? _rows.first
          : const _DashboardRow(
              rawDate: '',
              date: '-',
              day: '-',
              shift: '-',
              timeLogs: '- | -',
              status: 'NO LOG',
              isComplete: false,
            ),
    );
    
    // Use passed timeIn/timeOut if available, otherwise from loaded rows
    final passedTimeIn = widget.timeIn;
    final passedTimeOut = widget.timeOut;
    
    final todayLog = todayRow.timeLogs.split('|');
    final rowTimeIn = todayLog.isNotEmpty ? todayLog.first.trim() : '-';
    final rowTimeOut = todayLog.length > 1 ? todayLog[1].trim() : '-';
    
    // Prioritize passed values over loaded values
    final todayIn = passedTimeIn ?? (rowTimeIn != '-' ? rowTimeIn : '-');
    final todayOut = passedTimeOut ?? (rowTimeOut != '-' ? rowTimeOut : '-');
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: w * 0.38,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(w * 0.028),
            color: const Color(0xFF0B2742).withValues(alpha: 0.70),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: h * 0.014),
                child: Text(
                  'TODAYS LOG',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: w * 0.020,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ),
              Container(
                color: const Color(0xFF081A2E).withValues(alpha: 0.50),
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.014,
                  vertical: h * 0.016,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Date',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.014,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'IN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.014,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'OUT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.014,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.014,
                  vertical: h * 0.018,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 255, 255).withValues(alpha: 0.40),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(w * 0.028),
                    bottomRight: Radius.circular(w * 0.028),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        todayDate,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.010,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        todayIn,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.010,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        todayOut,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.010,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomTable(double w, double h) {
    final headerStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: w * 0.014,
      fontWeight: FontWeight.bold,
      color: Colors.white.withValues(alpha: 0.85),
      letterSpacing: 2,
    );

    final cellStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: w * 0.013,
      color: Colors.white,
      letterSpacing: 1.4,
    );

    final rows = _rows;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.028),
        color: const Color.fromRGBO(4, 17, 27, 1).withValues(alpha: 0.50),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF05080C).withValues(alpha: 0.30),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(w * 0.028),
                topRight: Radius.circular(w * 0.028),
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.024,
              vertical: h * 0.016,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(flex: 3, child: Text('Date', style: headerStyle)),
                Expanded(flex: 2, child: Text('Day', style: headerStyle)),
                Expanded(flex: 3, child: Text('Workhours', style: headerStyle)),
                Expanded(flex: 3, child: Text('Time Logs', style: headerStyle)),
                Expanded(flex: 2, child: Text('Status', style: headerStyle)),
              ],
            ),
          ),
          Expanded(
            child: _loadingRows
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                ? Center(
                    child: Text(
                      'No timelog history found',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: w * 0.014,
                        color: Colors.white70,
                        letterSpacing: 1.2,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: index.isEven
                              ? const Color(0xFF071A2B).withValues(alpha: 0.50)
                              : const Color.fromARGB(255, 147, 158, 168).withValues(alpha: 0.30),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: w * 0.024,
                          vertical: h * 0.008,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(row.date, style: cellStyle),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(row.day, style: cellStyle),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(row.shift, style: cellStyle),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(row.timeLogs, style: cellStyle),
                            ),
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _buildStatusChip(w, row),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox.shrink(),
                    itemCount: rows.length,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(double w, _DashboardRow row) {
    final color = row.isComplete
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFFC107);
    final bg = row.isComplete
        ? const Color(0xFF162D1D)
        : const Color(0xFF2E2611);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.015, vertical: w * 0.005),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.018),
        color: bg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w * 0.01,
            height: w * 0.01,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          SizedBox(width: w * 0.008),
          Text(
            row.status,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.010,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardRow {
  const _DashboardRow({
    required this.rawDate,
    required this.date,
    required this.day,
    required this.shift,
    required this.timeLogs,
    required this.status,
    required this.isComplete,
  });

  final String rawDate;
  final String date;
  final String day;
  final String shift;
  final String timeLogs;
  final String status;
  final bool isComplete;
}

class _TopLeftCurvedNotchClipper extends CustomClipper<Path> {
  const _TopLeftCurvedNotchClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..quadraticBezierTo(size.width * 0.10, size.height * 0.92, 0, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _DashboardRisingFadeParticle extends StatefulWidget {
  const _DashboardRisingFadeParticle({
    required this.size,
    required this.assetPath,
    this.phase = 0.0,
  });

  final double size;
  final String assetPath;
  final double phase;

  @override
  State<_DashboardRisingFadeParticle> createState() =>
      _DashboardRisingFadeParticleState();
}

class _DashboardRisingFadeParticleState
    extends State<_DashboardRisingFadeParticle>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _opacity;
  Animation<double>? _translateY;
  Animation<double>? _scale;

  static const double _riseDistance = 48.0;
  static const Duration _duration = Duration(milliseconds: 2600);

  @override
  void initState() {
    super.initState();
    final controller = AnimationController(vsync: this, duration: _duration);
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeOut);
    _controller = controller;
    _opacity = Tween<double>(begin: 0.50, end: 0.0).animate(curve);
    _translateY = Tween<double>(begin: 0.0, end: -_riseDistance).animate(curve);
    _scale = Tween<double>(begin: 1.0, end: 0.8).animate(curve);
    controller.value = widget.phase;
    controller.repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final opacity = _opacity;
    final translateY = _translateY;
    final scale = _scale;
    if (controller == null ||
        opacity == null ||
        translateY == null ||
        scale == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, translateY.value),
          child: Opacity(
            opacity: opacity.value,
            child: Transform.scale(
              scale: scale.value,
              alignment: Alignment.center,
              child: SvgPicture.asset(
                widget.assetPath,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF5FCFFF),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Helper classes for fingerprint scanning
class _EmployeeEntry {
  final String id;
  final String name;
  
  const _EmployeeEntry({required this.id, required this.name});
}

class _PendingTimeLog {
  final String timeLogId;
  final String timeLogDate;
  final String remarks;
  final String schedule;
  final String code;
  final String? timeInMorning;
  final String? timeOutMorning;
  final String? timeInAfternoon;
  final String? timeOutAfternoon;
  
  const _PendingTimeLog({
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
}
