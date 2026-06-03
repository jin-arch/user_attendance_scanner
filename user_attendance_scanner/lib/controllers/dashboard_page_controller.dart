import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../constants/date_time_formats.dart';
import '../zkfp/zkteco_usb.dart';
import '../services/hris_push_policy.dart';
import '../services/local_db.dart';
import '../services/pending_sync_service.dart';

class DashboardPageController extends GetxController {
  final now = DateTime.now().obs;
  final profilePhoto = Rxn<Uint8List>();
  final alreadyTimedIn = false.obs;
  final rows = <DashboardRowVm>[].obs;
  final isLoadingRows = true.obs;
  final showNavBar = false.obs;
  final navBarOpacity = 0.0.obs;

  Timer? _clockTimer;
  Timer? _afkTimer;
  Timer? _scanTimer;
  DateTime? _lastActivityTime;
  DateTime? _lastTemplateHandledAt;
  static const int _afkTimeoutSeconds = 60;
  bool _isProcessingTemplate = false;
  bool _ownsTemplateCallback = false;
  bool _isActiveRoute = true;
  bool _isSyncingTimelogs = false;
  DateTime? _lastTimelogSyncAt;
  static const Duration _timelogSyncCooldown = Duration(minutes: 2);
  void Function(Uint8List template, int size)? _templateHandler;

  final Map<int, DashboardEmployeeEntry> _employeeDb = {};
  final Map<String, DashboardEmployeeEntry> _employeeDbByFid = {};

  @override
  void onClose() {
    stopSession();
    super.onClose();
  }

  Future<void> refreshData() async {
    // Refresh dashboard data
    await loadDashboardRows();
  }

  Future<void> loadDashboardRows() async {
    try {
      isLoadingRows.value = true;
      // Load dashboard rows from database or API
      // This is a placeholder - implement actual data loading logic
      await Future.delayed(const Duration(seconds: 1));
      rows.clear();
    } catch (e) {
      print('Error loading dashboard rows: $e');
    } finally {
      isLoadingRows.value = false;
    }
  }

  void startSession({required void Function() onAfkTimeout}) {
    _lastActivityTime = DateTime.now();

    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      now.value = DateTime.now();
    });

    _afkTimer?.cancel();
    _afkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final lastActivity = _lastActivityTime;
      if (lastActivity == null) return;
      final elapsed = DateTime.now().difference(lastActivity).inSeconds;
      if (elapsed >= _afkTimeoutSeconds) {
        _afkTimer?.cancel();
        onAfkTimeout();
      }
    });
  }

  void stopSession() {
    try {
      _afkTimer?.cancel();
      _afkTimer = null;
      _clockTimer?.cancel();
      _clockTimer = null;
      _scanTimer?.cancel();
      _scanTimer = null;
    } catch (e) {
      print('[DASHBOARD] Error stopping session: $e');
    }
  }

  void resetAfkTimer() {
    _lastActivityTime = DateTime.now();
  }

  void toggleShowNavBar() {
    showNavBar.value = true;
    navBarOpacity.value = 1.0;
  }

  void toggleHideNavBar() {
    showNavBar.value = false;
    navBarOpacity.value = 0.0;
  }

  void setRouteActive(bool isActive) {
    _isActiveRoute = isActive;
  }

  Future<String?> resolveSiteId(String? siteId) async {
    final incoming = siteId?.trim();
    if (incoming != null && incoming.isNotEmpty) {
      return incoming;
    }

    final selectedSite = await LocalDb.getSelectedSite();
    final selectedId = selectedSite?['selected_site_id']?.toString().trim();
    if (selectedId == null || selectedId.isEmpty) {
      return null;
    }
    return selectedId;
  }

  Future<void> loadEmployeeDatabase({
    required String? siteId,
    required ZKTecoUSB device,
  }) async {
    try {
      if (siteId == null || siteId.isEmpty) return;
      print('[DASHBOARD_SCAN] Loading employees for site: $siteId');
      final rows = await LocalDb.getEmployeesBySite(
        siteId,
        includeFingerTemplates: false,
      );
      print('[DASHBOARD_SCAN] Found ${rows.length} employee rows from DB');
      _employeeDb.clear();
      _employeeDbByFid.clear();

      for (final row in rows) {
        final fid = row['fid'] as int?;
        final empId = row['employee_id']?.toString() ?? '';
        final empName = row['employee_name']?.toString() ?? '';
        final templateBytes = fid == null
            ? null
            : await LocalDb.getFingerTemplateByFid(fid: fid, siteId: siteId);

        print('[DASHBOARD_SCAN] Employee row: fid=$fid, empId=$empId, name=$empName, hasTemplate=${templateBytes != null}');

        if (fid != null && empId.isNotEmpty && templateBytes != null) {
          try {
            await device.registerFingerprint(fid, templateBytes);
            final entry = DashboardEmployeeEntry(id: empId, name: empName);
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

  void attachAndroidTemplateCallback({
    required ZKTecoUSB device,
    required Future<void> Function(Uint8List template) onTemplateReady,
    required void Function(bool isScanning) setScanning,
    required bool Function() isMounted,
  }) {
    if (!ZKTecoUSB.isAndroidPlatform) return;

    _ownsTemplateCallback = true;
    _templateHandler = (template, size) {
      _handleAndroidTemplate(
        template: template,
        device: device,
        onTemplateReady: onTemplateReady,
        setScanning: setScanning,
        isMounted: isMounted,
      );
    };
    device.onTemplateExtracted = _templateHandler;
  }

  void clearAndroidTemplateCallback({required ZKTecoUSB device}) {
    if (_ownsTemplateCallback && ZKTecoUSB.isAndroidPlatform) {
      if (device.onTemplateExtracted == _templateHandler) {
        device.onTemplateExtracted = null;
      }
    }
  }

  void startScanLoop({
    required ZKTecoUSB device,
    required bool Function() isScanning,
    required void Function(bool isScanning) setScanning,
    required Future<void> Function(Uint8List template) onTemplateReady,
  }) {
    if (!_isActiveRoute) return;
    if (isScanning() || !device.isConnected) return;

    setScanning(true);

    if (ZKTecoUSB.isAndroidPlatform) {
      return;
    }

    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      // Only scan if device is connected and scanning is active
      if (!isScanning()) return;
      
      // Prevent duplicate scans within 2 seconds
      final now = DateTime.now();
      if (_lastTemplateHandledAt != null && 
          now.difference(_lastTemplateHandledAt!).inMilliseconds < 2000) {
        return;
      }
      
      _captureAndMatch(
        device: device,
        isScanning: isScanning,
        setScanning: setScanning,
        onTemplateReady: onTemplateReady,
      );
    });
  }

  void stopScanLoop({
    required void Function(bool isScanning) setScanning,
  }) {
    _scanTimer?.cancel();
    _scanTimer = null;
    setScanning(false);
  }

  Future<DashboardEmployeeEntry?> resolveEmployeeFromTemplate({
    required ZKTecoUSB device,
    required Uint8List template,
  }) async {
    String? fid;
    if (ZKTecoUSB.isAndroidPlatform) {
      print('[DASHBOARD_SCAN] Calling identifyFingerprint...');
      final res = await device.identifyFingerprint();
      print('[DASHBOARD_SCAN] identifyFingerprint result: found=${res.found}, fid=${res.fid}');
      if (res.found) fid = res.fid;
    } else {
      final res = device.identifyTemplate(template);
      if (res.fingerId != null) fid = res.fingerId.toString();
    }

    print('[DASHBOARD_SCAN] Employee DB size: ${_employeeDb.length}, ByFid size: ${_employeeDbByFid.length}');
    print('[DASHBOARD_SCAN] Looking for fid: "$fid"');

    final fingerId = fid != null ? int.tryParse(fid.trim()) : null;
    final employee = (fid != null ? _employeeDbByFid[fid.trim()] : null) ??
        (fingerId != null ? _employeeDb[fingerId] : null) ??
        (fingerId != null ? _employeeDbByFid[fingerId.toString()] : null);

    print('[DASHBOARD_SCAN] Employee found: ${employee != null}, id=${employee?.id}, name=${employee?.name}');
    return employee;
  }

  void _captureAndMatch({
    required ZKTecoUSB device,
    required bool Function() isScanning,
    required void Function(bool isScanning) setScanning,
    required Future<void> Function(Uint8List template) onTemplateReady,
  }) {
    if (!isScanning() || !device.isConnected) {
      _scanTimer?.cancel();
      _scanTimer = null;
      setScanning(false);
      return;
    }

    final result = device.acquireFingerprintOnce();
    if (result.template != null) {
      _scanTimer?.cancel();
      _scanTimer = null;
      _lastTemplateHandledAt = DateTime.now();
      onTemplateReady(result.template!);
    }
  }

  void _handleAndroidTemplate({
    required Uint8List template,
    required ZKTecoUSB device,
    required Future<void> Function(Uint8List template) onTemplateReady,
    required void Function(bool isScanning) setScanning,
    required bool Function() isMounted,
  }) {
    if (!ZKTecoUSB.isAndroidPlatform) return;
    if (!_isActiveRoute) return;
    if (!device.isConnected) return;

    final now = DateTime.now();
    final lastAt = _lastTemplateHandledAt;
    if (lastAt != null && now.difference(lastAt).inMilliseconds < 800) return;
    if (_isProcessingTemplate) return;

    _lastTemplateHandledAt = now;
    _isProcessingTemplate = true;

    Future(() async {
      try {
        await onTemplateReady(template);
      } finally {
        if (isMounted() && device.isConnected && _isActiveRoute) {
          setScanning(true);
        }
        _isProcessingTemplate = false;
      }
    });
  }

  Future<Uint8List?> loadProfilePhoto({
    required String? employeeId,
    required String? siteId,
  }) async {
    final trimmedId = employeeId?.trim();
    if (trimmedId == null || trimmedId.isEmpty) {
      profilePhoto.value = null;
      return null;
    }

    final resolvedSiteId = (siteId == null || siteId.isEmpty) ? 'default' : siteId;
    final photo = await LocalDb.getEmployeePhoto(
      employeeId: trimmedId,
      siteId: resolvedSiteId,
    );
    profilePhoto.value = photo;
    return photo;
  }

  /// Dashboard history table: show full available local history.
  static const int _dashboardHistoryMaxRows = 10000;

  Future<List<Map<String, dynamic>>> loadTimelogHistory({
    required String siteId,
    required String employeeId,
    int limit = _dashboardHistoryMaxRows,
  }) async {
    print('[DASHBOARD_LOAD] ===== LOADING HISTORY =====');
    print('[DASHBOARD_LOAD] siteId="$siteId" employeeId="$employeeId"');

    // Commented out debug dump to improve performance
    // await LocalDb.debugDumpAllTimelogs();

    final history = await LocalDb.getTimelogHistoryForEmployee(
      siteId: siteId,
      employeeId: employeeId,
      limit: limit,
    );

    print('[DASHBOARD_LOAD] Loaded ${history.length} rows for employeeId="$employeeId" on siteId="$siteId"');
    // Commented out row-by-row debug printing to improve performance
    // for (final row in history) {
    //   print('[DASHBOARD_LOAD] Row raw: $row');
    // }

    return history;
  }

  List<DashboardRowVm> _mapTimelogHistoryToRows({
    required List<Map<String, dynamic>> history,
    required String? overrideTimeIn,
    required String? overrideTimeOut,
  }) {
    // Group entries by date to prevent duplicates
    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (final entry in history) {
      final dateText = _pickFirst(entry, [
        'timeLogDate',
        'timelog_date',
        'datecaptured',
        'DATECAPTURED',
        'datelog',
        'timelog',
        'TIMELOG',
      ]);
      if (dateText.isNotEmpty) {
        final normalizedDate = dateText.length >= 10
            ? dateText.substring(0, 10).replaceAll('/', '-')
            : dateText.replaceAll('/', '-');
        groupedByDate.putIfAbsent(normalizedDate, () => []).add(entry);
      }
    }

    // Consolidate entries for each date across the full fetched history.
    final sortedDates = groupedByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final consolidatedRows = <Map<String, dynamic>>[];
    for (final dateText in sortedDates) {
      final entries = groupedByDate[dateText]!;
      if (entries.length == 1) {
        consolidatedRows.add(entries.first);
      } else {
        // Merge multiple entries for the same date
        final merged = <String, dynamic>{};
        String? bestTimeIn;
        String? bestTimeOut;

        for (final entry in entries) {
          // Merge all fields, prioritizing non-null values
          for (final key in entry.keys) {
            if (entry[key] != null && entry[key].toString().isNotEmpty) {
              merged[key] = entry[key];
            }
          }

          // Find the earliest time-in and latest time-out
          final timeIn = DateTimeFormats.formatTimeFromApi(_pickFirst(entry, [
            'timeInMorning',
            'timeinmorning',
            'TIMEINMORNING',
            'timeInAfternoon',
            'TIMEINAFTERNOON',
          ]));
          final timeOut = DateTimeFormats.formatTimeFromApi(_pickFirst(entry, [
            'timeOutMorning',
            'timeoutmorning',
            'TIMEOUTMORNING',
            'timeOutAfternoon',
            'TIMEOUTAFTERNOON',
          ]));

          if (timeIn.isNotEmpty && timeIn != '-') {
            if (bestTimeIn == null || timeIn.compareTo(bestTimeIn) < 0) {
              bestTimeIn = timeIn;
            }
          }
          if (timeOut.isNotEmpty && timeOut != '-') {
            if (bestTimeOut == null || timeOut.compareTo(bestTimeOut) > 0) {
              bestTimeOut = timeOut;
            }
          }
        }

        // Update merged entry with best times
        if (bestTimeIn != null) {
          merged['timeInMorning'] = bestTimeIn;
          merged['timeinmorning'] = bestTimeIn;
        }
        if (bestTimeOut != null) {
          merged['timeOutMorning'] = bestTimeOut;
          merged['timeoutmorning'] = bestTimeOut;
        }

        consolidatedRows.add(merged);
        print('[DASHBOARD_LOAD] Consolidated ${entries.length} entries for date $dateText');
      }
    }

    final mappedRows = consolidatedRows.map(_rowFromTimelog).toList();

    final today = DateTimeFormats.dateOnly(DateTime.now());
    final todayIndex = mappedRows.indexWhere((row) => row.rawDate == today);

    if (todayIndex >= 0) {
      final todayRow = mappedRows[todayIndex];
      final todayLog = todayRow.timeLogs.split('|');
      var timeIn = todayLog.isNotEmpty ? todayLog.first.trim() : '-';
      var timeOut = todayLog.length > 1 ? todayLog[1].trim() : '-';

      if (overrideTimeIn != null) timeIn = overrideTimeIn;
      if (overrideTimeOut != null) timeOut = overrideTimeOut;

      final hasIn = timeIn != '-' && timeIn.isNotEmpty;
      final hasOut = timeOut != '-' && timeOut.isNotEmpty;
      final status = hasIn && hasOut
          ? 'COMPLETE'
          : (hasIn ? 'INCOMPLETE' : 'NO LOG');

      mappedRows[todayIndex] = DashboardRowVm(
        rawDate: todayRow.rawDate,
        date: todayRow.date,
        day: todayRow.day,
        shift: todayRow.shift,
        timeLogs: '$timeIn | $timeOut',
        status: status,
        isComplete: status == 'COMPLETE',
      );
      print('[DASHBOARD_LOAD] Updated today row at index $todayIndex with status $status');
    } else if (overrideTimeIn != null || overrideTimeOut != null) {
      // Only create today row if it doesn't exist AND we have override times
      // This prevents creating duplicate entries when scanning from homepage
      final timeIn = overrideTimeIn ?? '-';
      final timeOut = overrideTimeOut ?? '-';
      final hasIn = timeIn != '-' && timeIn.isNotEmpty;
      final hasOut = timeOut != '-' && timeOut.isNotEmpty;
      final status = hasIn && hasOut
          ? 'COMPLETE'
          : (hasIn ? 'INCOMPLETE' : 'NO LOG');

      mappedRows.insert(
        0,
        DashboardRowVm(
          rawDate: today,
          date: DateTimeFormats.dateLongUpper(DateTime.now()),
          day: DateTimeFormats.dayShort(DateTime.now()).toUpperCase(),
          shift: '-',
          timeLogs: '$timeIn | $timeOut',
          status: status,
          isComplete: status == 'COMPLETE',
        ),
      );
      print('[DASHBOARD_LOAD] Created today row with status $status');
    }

    return mappedRows;
  }

  void _refreshTimelogsInBackground({
    required String siteId,
    required String employeeId,
    required String? overrideTimeIn,
    required String? overrideTimeOut,
  }) {
    Future.microtask(() async {
      if (_isSyncingTimelogs) return;
      final now = DateTime.now();
      final lastSync = _lastTimelogSyncAt;
      if (lastSync != null &&
          now.difference(lastSync) < _timelogSyncCooldown) {
        return;
      }

      _isSyncingTimelogs = true;
      try {
        if (!await HrisPushPolicy.shouldPushToHrisApi()) {
          return;
        }
        _lastTimelogSyncAt = DateTime.now();
        await LocalDb.syncTimelogsForEmployeeFromApi(
          siteId: siteId,
          employeeId: employeeId,
        );
        await LocalDb.linkTimelogProfilesForSite(siteId);

        final history = await loadTimelogHistory(
          siteId: siteId,
          employeeId: employeeId,
          limit: _dashboardHistoryMaxRows,
        );
        final mappedRows = _mapTimelogHistoryToRows(
          history: history,
          overrideTimeIn: overrideTimeIn,
          overrideTimeOut: overrideTimeOut,
        );
        if (_isActiveRoute) {
          rows.value = mappedRows;
        }
      } catch (e) {
        debugPrint('[DASHBOARD_LOAD] Timelog refresh from API failed: $e');
      } finally {
        _isSyncingTimelogs = false;
      }
    });
  }

  Future<void> loadRows({
    required String? siteId,
    required String? employeeId,
    required String? overrideTimeIn,
    required String? overrideTimeOut,
  }) async {
    if (siteId == null ||
        siteId.isEmpty ||
        employeeId == null ||
        employeeId.isEmpty) {
      rows.value = const [];
      isLoadingRows.value = false;
      return;
    }

    isLoadingRows.value = true;

    try {
      final history = await loadTimelogHistory(
        siteId: siteId,
        employeeId: employeeId,
        limit: _dashboardHistoryMaxRows,
      );
      rows.value = _mapTimelogHistoryToRows(
        history: history,
        overrideTimeIn: overrideTimeIn,
        overrideTimeOut: overrideTimeOut,
      );
    } catch (e) {
      print('[DASHBOARD_LOAD] Error: $e');
      rows.value = const [];
    } finally {
      isLoadingRows.value = false;
      alreadyTimedIn.value = false;
    }

    _refreshTimelogsInBackground(
      siteId: siteId,
      employeeId: employeeId,
      overrideTimeIn: overrideTimeIn,
      overrideTimeOut: overrideTimeOut,
    );
  }

  Future<String?> recordAttendance({
    required String employeeId,
    required String? siteId,
  }) async {
    print('[RECORD] ========================================');
    print('[RECORD] siteId=$siteId employeeId=$employeeId');
    print('[RECORD] ========================================');

    if (siteId == null || siteId.isEmpty) {
      return 'NO SITE';
    }

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

      final wasQueued = await _submitOrQueuePendingAttendance(
        employeeId: employeeId,
        siteId: siteId,
        pending: pending,
      );

      if (wasQueued) {
        return pending.code.startsWith('IN')
            ? 'QUEUED TIME IN'
            : 'QUEUED TIME OUT';
      }

      await Future.delayed(const Duration(milliseconds: 500));

      print('[DASHBOARD_RECORD] SUCCESS: code=${pending.code}');
      return pending.code.startsWith('IN') ? 'TIME IN' : 'TIME OUT';
    } catch (e) {
      final errorMsg = e.toString();
      print('[DASHBOARD_RECORD] Caught exception: $errorMsg');
      if (errorMsg.contains('ALREADY_OUT_TODAY')) {
        return 'ALREADY OUT - Come back tomorrow';
      }
      if (errorMsg.contains('ALREADY_IN')) {
        return 'ALREADY IN - Wait 5 minutes';
      }
      return 'ERROR: $errorMsg';
    }
  }

  Future<_PendingTimeLog> _buildPendingTimeLog({
    required String employeeId,
    required String siteId,
    required DateTime now,
  }) async {
    try {
      final date = DateTimeFormats.dateOnly(now);
      final time = DateTimeFormats.timeOnly(now);

      print('[TIMELOG] ===== START employeeId=$employeeId siteId=$siteId date=$date =====');

      // Commented out debug dump to improve performance
      // await LocalDb.debugDumpAllTimelogs();

      // Offline-first: only today's row drives in/out (never yesterday's latest row).
      final todayCache = await LocalDb.getTimelogForEmployeeOnDate(
        siteId: siteId,
        employeeId: employeeId,
        date: date,
      );

      print('[TIMELOG] today cache from offline DB: ${todayCache != null ? "FOUND" : "NULL"}');

      var timeLogId = (todayCache?['timelogID'] ??
              todayCache?['timeLogID'] ??
              todayCache?['remark'] ??
              '')
          .toString()
          .trim();
      if (timeLogId.isEmpty) {
        timeLogId = 'tl_${now.millisecondsSinceEpoch}';
      }
      final remarks = (todayCache?['remarks'] ?? todayCache?['remark'] ?? '').toString();
      final schedule = (todayCache?['schedule'] ?? todayCache?['schedCode'] ?? '').toString();

      // Commented out verbose debug printing to improve performance
      // print('[DASHBOARD_TIMELOG] Raw cached values (today only):');
      // print('  timeInMorning: ${todayCache?['timeInMorning']}');
      // print('  timeOutMorning: ${todayCache?['timeOutMorning']}');
      // print('  timeInAfternoon: ${todayCache?['timeInAfternoon']}');
      // print('  timeOutAfternoon: ${todayCache?['timeOutAfternoon']}');

      final rawInMorning = todayCache?['timeInMorning']?.toString() ?? '';
      final rawOutMorning = todayCache?['timeOutMorning']?.toString() ?? '';
      final rawInAfternoon = todayCache?['timeInAfternoon']?.toString() ?? '';
      final rawOutAfternoon = todayCache?['timeOutAfternoon']?.toString() ?? '';

      // Commented out verbose debug printing to improve performance
      // print('[DASHBOARD_TIMELOG] Raw strings: inM="$rawInMorning", outM="$rawOutMorning", inA="$rawInAfternoon", outA="$rawOutAfternoon"');
      // print('[DASHBOARD_TIMELOG] _isBlank checks: inM=${_isBlank(rawInMorning)}, outM=${_isBlank(rawOutMorning)}, inA=${_isBlank(rawInAfternoon)}, outA=${_isBlank(rawOutAfternoon)}');
      // 
      // // Additional debug: Check all possible time field names
      // print('[DASHBOARD_TIMELOG] All todayCache keys: ${todayCache?.keys.toList()}');
      // print('[DASHBOARD_TIMELOG] todayCache full data: $todayCache');

      final existingInMorning = _isBlank(rawInMorning) ? null : rawInMorning;
      final existingOutMorning = _isBlank(rawOutMorning) ? null : rawOutMorning;
      final existingInAfternoon = _isBlank(rawInAfternoon) ? null : rawInAfternoon;
      final existingOutAfternoon = _isBlank(rawOutAfternoon) ? null : rawOutAfternoon;

      // Commented out verbose debug printing to improve performance
      // print('[DASHBOARD_TIMELOG] Parsed existing values: inM=$existingInMorning, outM=$existingOutMorning, inA=$existingInAfternoon, outA=$existingOutAfternoon');

      if (existingOutMorning != null || existingOutAfternoon != null) {
        print('[DASHBOARD_TIMELOG] THROWING ALREADY_OUT_TODAY');
        throw Exception('ALREADY_OUT_TODAY');
      }

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

      // Commented out verbose debug printing to improve performance
      // print('[DASHBOARD_TIMELOG] Decision path check: existingInMorning=$existingInMorning, existingOutMorning=$existingOutMorning');

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
    } catch (e) {
      print('[TIMELOG] ERROR in _buildPendingTimeLog: $e');
      rethrow;
    }
  }

  Future<bool> _submitOrQueuePendingAttendance({
    required String employeeId,
    required String siteId,
    required _PendingTimeLog pending,
  }) async {
    // Offline-first: local timelog is already saved; queue then push to HRIS.
    final timestamp = _pendingAttendanceTimestamp(pending);
    final payload = _pendingTimeLogPayload(pending);
    final queueId = await _queuePendingAttendance(
      employeeId: employeeId,
      siteId: siteId,
      timestamp: timestamp,
      payloadJson: jsonEncode(payload),
    );

    if (!Get.isRegistered<PendingSyncService>()) {
      Get.put(PendingSyncService());
    }
    final syncService = Get.find<PendingSyncService>();

    if (await syncService.shouldPushToHrisApi()) {
      try {
        await syncService.uploadAttendancePayload(
          siteId: siteId,
          employeeId: employeeId,
          payload: payload,
        );
        await LocalDb.markAttendanceSynced(queueId);
        debugPrint(
          '[DASHBOARD_RECORD] HRIS upload OK employee=$employeeId code=${pending.code}',
        );
        return false;
      } catch (e) {
        debugPrint(
          '[DASHBOARD_RECORD] Immediate HRIS upload failed (will retry): $e',
        );
      }

      unawaited(
        syncService.syncAllPending(siteId: siteId).catchError(
          (Object e) {
            debugPrint('[DASHBOARD_RECORD] Background HRIS upload: $e');
            return (synced: 0, failed: 0);
          },
        ),
      );
      return true;
    }

    debugPrint(
      '[DASHBOARD_RECORD] HRIS upload deferred (Offline UI mode — queued)',
    );
    return true;
  }

  Map<String, dynamic> _pendingTimeLogPayload(_PendingTimeLog pending) {
    return {
      'timeLogId': pending.timeLogId,
      'timeLogDate': pending.timeLogDate,
      'remarks': pending.remarks,
      'schedule': pending.schedule,
      'code': pending.code,
      'timeInMorning': pending.timeInMorning,
      'timeOutMorning': pending.timeOutMorning,
      'timeInAfternoon': pending.timeInAfternoon,
      'timeOutAfternoon': pending.timeOutAfternoon,
    };
  }

  Future<int> _queuePendingAttendance({
    required String employeeId,
    required String siteId,
    required DateTime timestamp,
    required String payloadJson,
  }) async {
    final queueId = await LocalDb.queueAttendance(
      employeeId: employeeId,
      siteId: siteId,
      attendanceTime: DateTime.now().toIso8601String(),
      recordType: LocalDb.pendingTimelogRecordType,
      payloadJson: payloadJson,
    );
    debugPrint(
      '[DASHBOARD_RECORD] Queued pending attendance id=$queueId employee=$employeeId site=$siteId ts=$timestamp',
    );
    return queueId;
  }

  DateTime _pendingAttendanceTimestamp(_PendingTimeLog pending) {
    String? time;
    switch (pending.code) {
      case 'IN_AM':
        time = pending.timeInMorning;
        break;
      case 'OUT_AM':
        time = pending.timeOutMorning;
        break;
      case 'IN_PM':
        time = pending.timeInAfternoon;
        break;
      case 'OUT_PM':
        time = pending.timeOutAfternoon;
        break;
      default:
        time = pending.timeInMorning ??
            pending.timeOutMorning ??
            pending.timeInAfternoon ??
            pending.timeOutAfternoon;
        break;
    }

    final parsed = time != null && time.isNotEmpty
        ? DateTime.tryParse('${pending.timeLogDate}T$time')
        : null;
    return parsed ?? DateTime.now();
  }

  bool _isBlank(String value) {
    final text = value.trim();
    return text.isEmpty ||
           text == '00:00:00' ||
           text == '00:00' ||
           text == '0' ||
           text == '-' ||
           text.toLowerCase() == 'null' ||
           text.toLowerCase() == 'n/a' ||
           text.toLowerCase() == 'na' ||
           text.toLowerCase() == 'none' ||
           text.toLowerCase() == 'empty';
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

  DateTime? _parseDate(String text) =>
      text.isEmpty ? null : DateTime.tryParse(text);

  DashboardRowVm _rowFromTimelog(Map<String, dynamic> row) {
    final dateText = _pickFirst(row, [
      'timeLogDate',
      'timelog_date',
      'datecaptured',
      'DATECAPTURED',
      'datelog',
      'timelog',
      'TIMELOG',
    ]);
    final dateOnly =
        DateTimeFormats.dateFromApiValue(dateText) ?? dateText.replaceAll('/', '-');
    final parsedDate = _parseDate(dateOnly);
    final timeInMorning = DateTimeFormats.formatTimeFromApi(_pickFirst(row, [
      'timeInMorning',
      'timeinmorning',
      'TIMEINMORNING',
    ]));
    final timeOutMorning = DateTimeFormats.formatTimeFromApi(_pickFirst(row, [
      'timeOutMorning',
      'timeoutmorning',
      'TIMEOUTMORNING',
    ]));
    final timeInAfternoon = DateTimeFormats.formatTimeFromApi(_pickFirst(row, [
      'timeInAfternoon',
      'timeinafternoon',
      'TIMEINAFTERNOON',
    ]));
    final timeOutAfternoon = DateTimeFormats.formatTimeFromApi(_pickFirst(row, [
      'timeOutAfternoon',
      'timeoutafternoon',
      'TIMEOUTAFTERNOON',
    ]));
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

    return DashboardRowVm(
      rawDate: dateOnly,
      date: parsedDate != null
          ? DateTimeFormats.dateLongUpper(parsedDate)
          : (dateOnly.isEmpty ? '-' : dateOnly),
        day: parsedDate != null ? DateTimeFormats.dayLongUpper(parsedDate) : '-',
      shift: _pickFirst(row, ['schedule', 'schedCode']).isEmpty
          ? '-'
          : _pickFirst(row, ['schedule', 'schedCode']),
      timeLogs: '$firstIn | $lastOut',
      status: status,
      isComplete: status == 'COMPLETE',
    );
  }
}

class DashboardEmployeeEntry {
  const DashboardEmployeeEntry({required this.id, required this.name});

  final String id;
  final String name;
}

class DashboardRowVm {
  const DashboardRowVm({
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

class _PendingTimeLog {
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
