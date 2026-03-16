import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/local_db.dart';
import '../controllers/home_page_controller.dart';
import '../zkfp/zkteco_usb.dart';
import 'loading_page.dart';

class _SiteOption {
  const _SiteOption({required this.id, required this.name});

  final String id;
  final String name;
}

class _EmployeeEntry {
  const _EmployeeEntry({required this.id, required this.name});

  final String id;
  final String name;
}

class _ScanResult {
  const _ScanResult({
    required this.success,
    required this.timestamp,
    this.errorMessage,
  });

  final bool success;
  final DateTime timestamp;
  final String? errorMessage;
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

enum _HomeUiMode { scanner, portal, enroll }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _apiBaseUrl =
    'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/';
  static const String _siteApiUrl =
    '${_apiBaseUrl}get/site/all';
  static const String _employeesApiUrl =
    '${_apiBaseUrl}get/employee/perSite?siteID=';
  static const String _timelogPerSiteApiUrl =
    '${_apiBaseUrl}get/timelog/lastweek/perSite?siteID=';
  static const String _timeInApiEndpoint = 'update/timeLog/timeIn';
  static const String _timeOutApiEndpoint = 'update/timeLog/timeOut';
  static const String _insertHrisLogsApiEndpoint =
    'insert/hris/logs/transaction';
  static const String _insertTimeLogApiEndpoint = 'insert/timeLog';
  static const String _thumbDetailsApiEndpoint =
    'update/employee/thumbDetails';
  static const String _legacyAttendanceApiUrl =
    '${_apiBaseUrl}post/attendance/add';
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';
  static const String _deviceSitePrefsKey = 'device_site_map_v1';

  bool _isLoadingSites = false;
  String? _selectedSiteId;
  List<_SiteOption> _sites = const [];
  final Map<String, String> _deviceSiteMap = {};
  
  final ZKTecoUSB _device = ZKTecoUSB();
  late final HomePageController _controller;

  // Scan loop state
  Timer? _scanTimer;
  Timer? _liveSyncTimer;
  Timer? _portalAutoReturnTimer;
  bool _isLiveSyncRunning = false;
  _ScanResult? _lastResult;
  bool _showResult = false;
  final Map<int, _EmployeeEntry> _employeeDb = {};
  final Map<String, _EmployeeEntry> _employeeDbByFid = {};
  _HomeUiMode _uiMode = _HomeUiMode.scanner;
  _EmployeeEntry? _matchedEmployee;
  String? _matchedAttendanceType;
  DateTime? _matchedAt;

  @override
  void initState() {
    super.initState();
    _controller = Get.isRegistered<HomePageController>()
        ? Get.find<HomePageController>()
        : Get.put(HomePageController());
    _loadDeviceSiteMap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requireSiteSelectionOnStartup();
    });

    // Set up Android callbacks
    if (ZKTecoUSB.isAndroidPlatform) {
      _device.onDeviceAttached = () {
        _controller.setStatus('Device attached!');
      };
      _device.onDeviceDetached = () {
        _controller.setConnected(false, status: 'Device detached');
        _employeeDb.clear();
        _employeeDbByFid.clear();
        _portalAutoReturnTimer?.cancel();
        _stopLiveDbSync();
        _stopScanLoop();
      };
      _device.onTemplateExtracted = (template, size) {
        if (_controller.isScanning.value) _onTemplateReady(template);
      };
    }
  }

  Future<void> _loadDeviceSiteMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deviceSitePrefsKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _deviceSiteMap
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, '$v')));
      }
    } catch (_) {}
  }

  Future<void> _saveDeviceSiteMap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceSitePrefsKey, jsonEncode(_deviceSiteMap));
  }

  Future<List<_SiteOption>> _fetchSites() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(_siteApiUrl));
        final basicToken =
          base64Encode(utf8.encode('$_apiUsername:$_apiPassword'));
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

      return list
          .map((site) {
            final name =
            site['site_name'] ??
            site['SITENAME'] ??
            site['name'] ??
            site['site'] ??
            site['title'];
            final id = site['site_id'] ??
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

            return _SiteOption(id: value, name: label);
          })
          .whereType<_SiteOption>()
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  List<Map<String, dynamic>> _extractSiteRows(dynamic decoded) {
    dynamic data = decoded;
    if (decoded is Map<String, dynamic>) {
      data = decoded['data'] ??
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
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }

    return const [];
  }

  int _stableFingerprintId(String employeeId, String thumbKey) {
    var hash = 0x811C9DC5;
    final input = '$employeeId:$thumbKey';
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<void> _ensureSitesLoaded() async {
    if (_sites.isNotEmpty || _isLoadingSites) return;

    setState(() => _isLoadingSites = true);
    try {
      final fetched = await _fetchSites();
      if (!mounted) return;
      setState(() {
        _sites = fetched;
      });
    } catch (e) {
      if (!mounted) return;
      _controller.setStatus('Connected, but site list failed to load: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingSites = false);
      }
    }
  }

  Future<void> _requireSiteSelectionOnStartup() async {
    if (!mounted) return;

    // Step 1 — fetch site list quietly (status bar only, no loading screen)
    _controller.setStatus('Loading site list...');
    await _ensureSitesLoaded();
    if (!mounted) return;

    if (_sites.isEmpty) {
      _controller.setStatus(
          'Cannot load site list. Please check API connection.');
      return;
    }
    _controller.setStatus('');

    // Step 2 — let the user choose their work site
    final selected = await _showSiteSelectionDialog(requiredSelection: true);
    if (!mounted || selected == null) return;

    setState(() => _selectedSiteId = selected);
    await LocalDb.pruneToSite(selected);
    _controller
        .setStatus('Selected site: ${_siteNameById(selected) ?? selected}');

    // Step 3 — NOW show the loading screen while connecting + syncing data
    if (!mounted) return;
    final syncFuture = _connectAndSync();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LoadingPage(loadFuture: syncFuture),
      fullscreenDialog: true,
    ));
    if (mounted) _startScanLoop();
  }

  Future<String?> _showSiteSelectionDialog({
    bool requiredSelection = false,
    String? initialSiteId,
  }) async {
    if (_sites.isEmpty) return null;

    String selectedId = initialSiteId ?? _sites.first.id;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: !requiredSelection,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                backgroundColor: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE7F0FD),
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFC8DDFB),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.home_work_outlined,
                            size: 18,
                            color: Color(0xFF3E7DDD),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Select Your Work Site',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E2430),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please select the site where you are currently working to\nrecord your attendance.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          color: Color(0xFF6B7280),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFD6DBE5)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: selectedId,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            prefixIcon: Icon(
                              Icons.business_outlined,
                              color: Color(0xFF9AA3B2),
                            ),
                          ),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          items: _sites
                              .map(
                                (site) => DropdownMenuItem<String>(
                                  value: site.id,
                                  child: Text(
                                    site.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => selectedId = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton(
                                onPressed: requiredSelection
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFD6DBE5)),
                                  foregroundColor: const Color(0xFF9CA3AF),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(selectedId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3E7DDD),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Proceed'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String? _siteNameById(String? id) {
    if (id == null) return null;
    for (final site in _sites) {
      if (site.id == id) {
        return site.name;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _portalAutoReturnTimer?.cancel();
    _stopLiveDbSync();
    _device.dispose();
    if (Get.isRegistered<HomePageController>()) {
      Get.delete<HomePageController>();
    }
    super.dispose();
  }
  
  /// Pure async connect + sync — NO dialogs, NO Navigator calls.
  /// Safe to run as the loadFuture inside LoadingPage.
  Future<void> _connectAndSync() async {
    _controller.startSearching('Searching for device...');
    try {
      if (ZKTecoUSB.isAndroidPlatform) {
        final env = await _device.getAndroidSdkEnvironment();
        if (env['canUseSdk'] != true) {
          _controller.stopSearching(
              env['reason']?.toString() ??
                  'SDK not compatible. Ensure a physical Android device with the scanner attached.');
          return;
        }
      }

      final sdkInit = await _device.initSdk();
      if (!sdkInit) {
        _controller.stopSearching(
          ZKTecoUSB.isAndroidPlatform
              ? 'SDK init failed. Plug in the scanner and retry.'
              : 'SDK init failed.',
        );
        return;
      }

      final count = await _device.getDeviceCountAsync();
      if (count == 0) {
        _controller.stopSearching('No device found. Plug in the scanner and retry.');
        await _device.terminateSdk();
        return;
      }

      _controller.setStatus('Found $count device(s). Connecting...');

      final opened = await _device.openDevice(0);
      if (!opened) {
        _controller.stopSearching('Failed to open device.');
        await _device.terminateSdk();
        return;
      }

      final serial = await _device.getSerialNumber();

      // Persist serial → site mapping (no dialog — site was already chosen)
      if (serial != null && serial.isNotEmpty && _selectedSiteId != null) {
        _deviceSiteMap[serial] = _selectedSiteId!;
        await _saveDeviceSiteMap();
      }

      final siteName = _siteNameById(_selectedSiteId);
      final siteText = siteName != null ? ' | Site: $siteName' : '';
      _controller.stopSearching();
      _controller.setConnected(
          true, status: 'Connected: ${serial ?? "Unknown"}$siteText');

      // Sync API -> SQLite, then always load/register from SQLite.
      await _loadAndRegisterTemplates();
      await _fetchAndCacheSiteTimeLogs();
      await _syncPendingHrisQueue();
      _startLiveDbSync();
    } catch (e) {
      _controller.stopSearching('Error: $e');
    }
  }

  Future<void> _searchAndConnect() async {
    if (_controller.isSearching.value) return;
    if (!mounted) return;

    // Step 1 — ensure site list is available (silent, no loading screen)
    if (_sites.isEmpty) {
      _controller.setStatus('Loading site list...');
      await _ensureSitesLoaded();
      if (!mounted) return;
    }

    if (_sites.isEmpty) {
      _controller.setStatus(
          'Cannot load site list. Please check API connection.');
      return;
    }
    _controller.setStatus('');

    // Step 2 — show site-selection dialog (Cancel IS allowed here)
    final selected = await _showSiteSelectionDialog(
      requiredSelection: false,
      initialSiteId: _selectedSiteId ?? _sites.first.id,
    );
    if (!mounted || selected == null) return;

    setState(() => _selectedSiteId = selected);
    await LocalDb.pruneToSite(selected);
    _controller
        .setStatus('Selected site: ${_siteNameById(selected) ?? selected}');

    // Step 3 — ONLY NOW show the loading screen (connect + sync)
    if (!mounted) return;
    final syncFuture = _connectAndSync();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LoadingPage(loadFuture: syncFuture),
      fullscreenDialog: true,
    ));
    if (mounted) _startScanLoop();
  }

  // ==================== Template Loading & Scan Loop ====================

  Future<void> _loadAndRegisterTemplates() async {
    if (!mounted) return;
    final siteId = _selectedSiteId;
    if (siteId == null) {
      _controller.setStatus('No site selected — cannot load fingerprints.');
      return;
    }

    _controller.setStatus('Syncing fingerprint data to local database...');
    await _syncEmployeesFromApiToLocalDb(siteId);
    await _loadFromLocalDb(siteId);
  }

  Future<void> _syncEmployeesFromApiToLocalDb(String siteId) async {
    await LocalDb.pruneToSite(siteId);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final urlStr = '$_employeesApiUrl$siteId';
      final request = await client.getUrl(Uri.parse(urlStr));
      final basicToken = base64Encode(utf8.encode('$_apiUsername:$_apiPassword'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
      final rows = _extractSiteRows(decoded);

      await LocalDb.deleteEmployeesBySite(siteId);
      for (final row in rows) {
        final empId =
            (row['employee_id'] ?? row['emp_id'] ?? row['id'] ?? row['EMPID'])
                ?.toString()
                .trim();
        final firstName = (row['FIRSTNAME'] ?? row['first_name'])?.toString().trim();
        final middleName = (row['MIDDLENAME'] ?? row['middle_name'])?.toString().trim();
        final lastName = (row['LASTNAME'] ?? row['last_name'])?.toString().trim();
        final fullNameParts = [firstName, middleName, lastName]
            .whereType<String>()
            .where((part) => part.isNotEmpty && part.toLowerCase() != 'null')
            .toList();
        final empName =
            (row['employee_name'] ?? row['full_name'] ?? row['name'])?.toString().trim();
        final resolvedName = fullNameParts.isNotEmpty
            ? fullNameParts.join(' ')
            : ((empName != null && empName.isNotEmpty && empName.toLowerCase() != 'null')
                ? empName
                : null);

        if (empId == null || empId.isEmpty) {
          continue;
        }

        final thumbTemplates = <String, String?>{
          'left': (row['LEFTFINGERTHUMB'] ?? row['leftFingerThumb'] ?? row['left_thumb'])
              ?.toString(),
          'right': (row['RIGHTFINGERTHUMB'] ?? row['rightFingerThumb'] ?? row['right_thumb'])
              ?.toString(),
          'default': (row['finger_template'] ?? row['template'] ?? row['fingerprint'])
              ?.toString(),
        };

        for (final entry in thumbTemplates.entries) {
          final templateB64 = entry.value?.trim();
          if (templateB64 == null ||
              templateB64.isEmpty ||
              templateB64.toLowerCase() == 'null') {
            continue;
          }

          try {
            final rawFid = row['finger_id'] ?? row['fid'] ?? row['fingerprint_id'];
            final fid = int.tryParse(rawFid?.toString() ?? '') ??
                _stableFingerprintId(empId, entry.key);
            await LocalDb.upsertEmployee(
              fid: fid,
              employeeId: empId,
              employeeName: resolvedName,
              template: base64Decode(templateB64),
              siteId: siteId,
            );
          } catch (_) {}
        }
      }
      _controller.setLastDbSync();
    } catch (e) {
      debugPrint('_syncEmployeesFromApiToLocalDb: $e');
    } finally {
      client.close(force: true);
    }
  }

  void _startLiveDbSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (!mounted || _isLiveSyncRunning || !_device.isConnected) return;
      final siteId = _selectedSiteId;
      if (siteId == null || siteId.isEmpty) return;

      _isLiveSyncRunning = true;
      try {
        await _syncEmployeesFromApiToLocalDb(siteId);
        await _loadFromLocalDb(siteId);
        await _fetchAndCacheSiteTimeLogs();
        await _syncPendingHrisQueue();
      } catch (e) {
        debugPrint('_startLiveDbSync tick: $e');
      } finally {
        _isLiveSyncRunning = false;
      }
    });
  }

  void _stopLiveDbSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
    _isLiveSyncRunning = false;
  }

  Future<void> _loadFromLocalDb(String siteId) async {
    try {
      final rows = await LocalDb.getEmployeesBySite(siteId);
      _employeeDb.clear();
      _employeeDbByFid.clear();
      int registered = 0;

      for (final row in rows) {
        final fid = row['fid'] as int;
        final empId = row['employee_id'] as String;
        final empName = row['employee_name'] as String?;
        final templateBytes = row['finger_template'] as Uint8List;

        await _device.registerFingerprint(fid, templateBytes);
        final entry = _EmployeeEntry(
          id: empId,
          name: empName ?? empId,
        );
        _employeeDb[fid] = entry;
        _employeeDbByFid[fid.toString()] = entry;
        registered++;
      }

      if (!mounted) return;
      _controller.setStatus(
        registered > 0
        ? 'Ready - $registered fingerprint(s) loaded from biometric_scanner.db'
            : 'No cached fingerprints. Connect to internet and sync.',
      );
    } catch (e) {
      if (!mounted) return;
      _controller.setStatus('Ready — place finger on scanner');
      debugPrint('_loadFromLocalDb error: $e');
    }
  }

  Future<void> _fetchAndCacheSiteTimeLogs() async {
    final siteId = _selectedSiteId;
    if (siteId == null) return;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      try {
        final request = await client.getUrl(Uri.parse('$_timelogPerSiteApiUrl$siteId'));
        final basicToken =
            base64Encode(utf8.encode('$_apiUsername:$_apiPassword'));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
        request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode < 200 || response.statusCode > 299) {
          throw Exception('HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(body);
        final rows = _extractSiteRows(decoded);
        await LocalDb.replaceTimelogCache(siteId: siteId, rows: rows);
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('_fetchAndCacheSiteTimeLogs: $e');
    }
  }

  void _startScanLoop() {
    if (_controller.isScanning.value || !_device.isConnected) return;
    _controller.setScanning(true);

    if (ZKTecoUSB.isAndroidPlatform) {
      // Android is event-driven via onTemplateExtracted callback
      return;
    }

    // Windows: poll the sensor every 250ms
    _scanTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_controller.isScanning.value || !_device.isConnected) {
        _stopScanLoop();
        return;
      }
      final result = _device.acquireFingerprintOnce();
      if (result.template != null) {
        _scanTimer?.cancel();
        _scanTimer = null;
        _onTemplateReady(result.template!);
      }
    });
  }

  void _stopScanLoop() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _controller.setScanning(false);
  }

  void _scheduleScannerResume() {
    _portalAutoReturnTimer?.cancel();
    _portalAutoReturnTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() {
        _uiMode = _HomeUiMode.scanner;
        _matchedEmployee = null;
        _matchedAt = null;
        _matchedAttendanceType = null;
      });
      if (_device.isConnected) {
        _startScanLoop();
      }
    });
  }

  Future<void> _onTemplateReady(Uint8List template) async {
    if (!mounted || !_device.isConnected) return;
    _controller.setScanning(false);

    String? fid;
    if (ZKTecoUSB.isAndroidPlatform) {
      final res = await _device.identifyFingerprint();
      if (res.found) fid = res.fid;
    } else {
      final res = _device.identifyTemplate(template);
      if (res.fingerId != null) fid = res.fingerId.toString();
    }

    final fingerId = _parseFingerId(fid);
    _EmployeeEntry? employee =
        (fid != null ? _employeeDbByFid[fid.trim()] : null) ??
            (fingerId != null ? _employeeDb[fingerId] : null) ??
            (fingerId != null ? _employeeDbByFid[fingerId.toString()] : null);

    if (employee == null && ZKTecoUSB.isAndroidPlatform) {
      employee = await _resolveEmployeeByVerificationFallback();
    }

    if (employee != null) {
      final attendanceType = await _recordAttendance(employee.id);
      if (!mounted) return;
      setState(() {
        _matchedEmployee = employee;
        _matchedAttendanceType = attendanceType ?? 'RECORDED';
        _matchedAt = DateTime.now();
        _uiMode = _HomeUiMode.portal;
        _showResult = false;
      });
      _scheduleScannerResume();
      _controller.setStatus(
          '${employee.name} — ${attendanceType ?? 'RECORDED'}');
    } else {
      _displayResult(_ScanResult(
        success: false,
        timestamp: DateTime.now(),
        errorMessage: fid != null
            ? 'Employee not on record'
            : 'Fingerprint not registered',
      ));
    }
  }

  Future<_EmployeeEntry?> _resolveEmployeeByVerificationFallback() async {
    if (!ZKTecoUSB.isAndroidPlatform || _employeeDbByFid.isEmpty) {
      return null;
    }

    // Fallback for cases where Android identify() misses but verify(fid) works.
    // Cap the loop so UI does not stall on very large datasets.
    final entries = _employeeDbByFid.entries.toList();
    final maxChecks = entries.length > 180 ? 180 : entries.length;

    for (var index = 0; index < maxChecks; index++) {
      final entry = entries[index];
      try {
        final verify = await _device
            .verifyFingerprint(entry.key)
            .timeout(const Duration(milliseconds: 180), onTimeout: () {
          return (match: false, score: null);
        });
        if (verify.match) {
          return entry.value;
        }
      } catch (_) {}
    }

    return null;
  }

  Future<String?> _recordAttendance(String employeeId) async {
    final siteId = _selectedSiteId;
    if (siteId == null) {
      return 'NO SITE';
    }

    final pending = await _buildPendingTimeLog(
      employeeId: employeeId,
      siteId: siteId,
      now: DateTime.now(),
    );

    final requests = _buildAttendanceRequests(
      siteId: siteId,
      employeeId: employeeId,
      pending: pending,
    );

    // First request is the critical write (timeIn/timeOut).
    final primary = requests.first;
    final primarySent = await _sendHrisRequest(
      endpoint: primary.$1,
      queryParams: primary.$2,
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );

    if (primarySent) {
      // Secondary requests (logs/audit) are important but should not change
      // the UI result when the core attendance record is already saved.
      for (final request in requests.skip(1)) {
        final sent = await _sendHrisRequest(
          endpoint: request.$1,
          queryParams: request.$2,
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );
        if (!sent) {
          await LocalDb.queueHrisRequest(
            endpoint: request.$1,
            queryParams: request.$2,
          );
        }
      }
      return pending.code.startsWith('IN') ? 'TIME IN' : 'TIME OUT';
    }

    // Primary write failed: queue everything for retry.
    for (final request in requests) {
      await LocalDb.queueHrisRequest(
        endpoint: request.$1,
        queryParams: request.$2,
      );
    }

    // Fallback: keep attendance working with the legacy endpoint
    final legacyType = await _sendLegacyAttendance(
      employeeId: employeeId,
      siteId: siteId,
      timestamp: DateTime.now().toIso8601String(),
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    if (legacyType != null) {
      return legacyType;
    }

    return 'QUEUED OFFLINE';
  }

  Future<_PendingTimeLog> _buildPendingTimeLog({
    required String employeeId,
    required String siteId,
    required DateTime now,
  }) async {
    final date = _formatDateOnly(now);
    final time = _formatTimeOnly(now);
    final cached = await LocalDb.getLatestTimelogForEmployee(
      siteId: siteId,
      employeeId: employeeId,
    );

    final timeLogId = (cached?['timelogID'] ??
            cached?['timeLogID'] ??
            cached?['timelog_id'] ??
            '$employeeId-$date')
        .toString();
    final remarks =
        (cached?['remarks'] ?? cached?['remark'] ?? '').toString();
    final schedule =
        (cached?['schedule'] ?? cached?['schedCode'] ?? '').toString();

    final existingInMorning =
        _isBlank(cached?['timeInMorning']) ? null : '${cached?['timeInMorning']}';
    final existingOutMorning =
        _isBlank(cached?['timeOutMorning']) ? null : '${cached?['timeOutMorning']}';
    final existingInAfternoon =
        _isBlank(cached?['timeInAfternoon']) ? null : '${cached?['timeInAfternoon']}';
    final existingOutAfternoon =
        _isBlank(cached?['timeOutAfternoon']) ? null : '${cached?['timeOutAfternoon']}';

    if (existingInMorning == null) {
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

  List<(String, Map<String, String>)> _buildAttendanceRequests({
    required String siteId,
    required String employeeId,
    required _PendingTimeLog pending,
  }) {
    final timeEndpoint = pending.code.startsWith('IN')
        ? _timeInApiEndpoint
        : _timeOutApiEndpoint;

    final timeParams = <String, String>{
      'passedID': 'null',
      'timelogID': pending.timeLogId,
      'timelog': pending.timeLogDate,
      'remarks': pending.remarks,
      'code': pending.code,
    };

    if (pending.timeInMorning != null) {
      timeParams['timeInMorning'] = pending.timeInMorning!;
    }
    if (pending.timeInAfternoon != null) {
      timeParams['timeInAfternoon'] = pending.timeInAfternoon!;
    }
    if (pending.timeOutMorning != null) {
      timeParams['timeOutMorning'] = pending.timeOutMorning!;
    }
    if (pending.timeOutAfternoon != null) {
      timeParams['timeOutAfternoon'] = pending.timeOutAfternoon!;
    }

    final logsParams = <String, String>{
      'passedID': 'null',
      'companyID': employeeId,
      'datelog': pending.timeLogDate,
      'log_time': _formatTimeOnly(DateTime.now()),
      'log_type': pending.code,
      'logID': pending.timeLogId,
    };

    final insertTimeLogParams = <String, String>{
      'siteID': siteId,
      'employeeID': employeeId,
      'timelogID': pending.timeLogId,
      'timelog': pending.timeLogDate,
      'remarks': pending.remarks,
      'schedule': pending.schedule,
      'timeinmorning': pending.timeInMorning ?? '',
      'timeinafternoon': pending.timeInAfternoon ?? '',
      'timeoutmorning': pending.timeOutMorning ?? '',
      'timeoutafternoon': pending.timeOutAfternoon ?? '',
      'datecaptured': pending.timeLogDate,
      'code': pending.code,
    };

    return [
      (timeEndpoint, timeParams),
      (_insertHrisLogsApiEndpoint, logsParams),
      (_insertTimeLogApiEndpoint, insertTimeLogParams),
    ];
  }

  Future<bool> _sendHrisRequest({
    required String endpoint,
    required Map<String, String> queryParams,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl$endpoint').replace(
      queryParameters: queryParams,
    );

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 12);
      try {
        final request = await client.getUrl(uri);
        final basicToken =
            base64Encode(utf8.encode('$_apiUsername:$_apiPassword'));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
        request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');
        final response = await request.close();
        await response.transform(utf8.decoder).join();
        return response.statusCode >= 200 && response.statusCode < 300;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('_sendHrisRequest($endpoint): $e');
      return false;
    }
  }

  Future<void> _syncPendingHrisQueue() async {
    try {
      final pendingRows = await LocalDb.getPendingHrisRequests();
      if (pendingRows.isEmpty) return;

      for (final row in pendingRows) {
        final id = row['id'] as int;
        final endpoint = row['endpoint'] as String;
        final rawParams = row['query_params'] as String? ?? '{}';
        final decoded = jsonDecode(rawParams);
        final queryParams = decoded is Map<String, dynamic>
            ? decoded.map((k, v) => MapEntry(k, '$v'))
            : <String, String>{};

        final sent = await _sendHrisRequest(
          endpoint: endpoint,
          queryParams: queryParams,
        );
        if (sent) {
          await LocalDb.markHrisRequestSynced(id);
        }
      }
    } catch (e) {
      debugPrint('_syncPendingHrisQueue: $e');
    }
  }

  String _formatDateOnly(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatTimeOnly(DateTime dateTime) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    final s = dateTime.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  bool _isBlank(dynamic value) {
    if (value == null) return true;
    final text = value.toString().trim();
    return text.isEmpty ||
        text == 'null' ||
        text == '00:00:00' ||
        text == '0' ||
        text.toUpperCase() == 'N/A';
  }

  int? _parseFingerId(String? rawFid) {
    if (rawFid == null) return null;
    final normalized = rawFid.trim();
    if (normalized.isEmpty) return null;

    final direct = int.tryParse(normalized);
    if (direct != null) return direct;

    if (normalized.contains('.')) {
      final beforeDot = normalized.split('.').first.trim();
      final parsed = int.tryParse(beforeDot);
      if (parsed != null) return parsed;
    }

    final digitsMatch = RegExp(r'\d+').firstMatch(normalized);
    if (digitsMatch != null) {
      return int.tryParse(digitsMatch.group(0)!);
    }
    return null;
  }

  Future<String?> _sendLegacyAttendance({
    required String employeeId,
    required String siteId,
    required String timestamp,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      try {
        final request = await client.postUrl(Uri.parse(_legacyAttendanceApiUrl));
        final basicToken =
            base64Encode(utf8.encode('$_apiUsername:$_apiPassword'));
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');

        final payload = jsonEncode({
          'employee_id': employeeId,
          'site_id': siteId,
          'timestamp': timestamp,
        });
        request.contentLength = utf8.encode(payload).length;
        request.write(payload);

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode < 200 || response.statusCode > 299) {
          return null;
        }

        try {
          final decoded = jsonDecode(body);
          final type = decoded['attendance_type'] ??
              decoded['type'] ??
              decoded['status'] ??
              decoded['log_type'];
          return type?.toString().toUpperCase() ?? 'RECORDED';
        } catch (_) {
          return 'RECORDED';
        }
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('_sendLegacyAttendance: $e');
      return null;
    }
  }

  void _displayResult(_ScanResult result) {
    if (!mounted) return;
    setState(() {
      _lastResult = result;
      _showResult = true;
    });
    _controller.setStatus(
      result.success ? 'RECORDED' : (result.errorMessage ?? 'Scan failed'),
    );
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _showResult = false);
      if (_device.isConnected) _startScanLoop();
    });
  }

  String get _timeString {
    final currentTime = _controller.now.value;
    final hour = currentTime.hour > 12
        ? currentTime.hour - 12
        : (currentTime.hour == 0 ? 12 : currentTime.hour);
    final minute = currentTime.minute.toString().padLeft(2, '0');
    final period = currentTime.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  String get _dateString {
    final currentTime = _controller.now.value;
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    return '${months[currentTime.month - 1]} ${currentTime.day}, ${currentTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    if (_uiMode != _HomeUiMode.scanner && _matchedEmployee != null) {
      return Scaffold(
        body: _buildMatchedScreen(screenW, screenH),
      );
    }

    return Scaffold(
      body: Container(
        width: screenW,
        height: screenH,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/Main BG.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: screenW * 0.025,
              vertical: screenH * 0.025,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/FastLogo.png',
                      height: screenH * 0.065,
                      fit: BoxFit.contain,
                    ),
                    const Spacer(),
                    Obx(
                      () => _controller.biometricConnected.value
                          ? GestureDetector(
                              onTap: _showAddUserDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0x223E7DDD),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF3E7DDD),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.person_add_outlined,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'ADD USER',
                                      style: TextStyle(
                                        fontFamily: 'CEORUSE',
                                        fontSize: 11,
                                        color: Colors.white,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
                SizedBox(height: screenH * 0.018),
                Expanded(child: _buildMainCard(screenW, screenH)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatchedScreen(double screenW, double screenH) {
    final employee = _matchedEmployee!;
    final isEnrollMode = _uiMode == _HomeUiMode.enroll;

    return Container(
      width: screenW,
      height: screenH,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/Main BG.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenW * 0.025,
            vertical: screenH * 0.025,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: const Color(0xCC0C2F69),
              border: Border.all(color: const Color(0xFF7AB4FF), width: 2),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildTopActionButton(
                      label: 'PORTAL',
                      active: !isEnrollMode,
                      onTap: () {
                        setState(() => _uiMode = _HomeUiMode.portal);
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildTopActionButton(
                      label: isEnrollMode ? 'LOGIN' : 'ENROLL NOW',
                      active: isEnrollMode,
                      onTap: () {
                        if (isEnrollMode) {
                          _portalAutoReturnTimer?.cancel();
                          setState(() {
                            _uiMode = _HomeUiMode.scanner;
                            _matchedEmployee = null;
                            _matchedAt = null;
                            _matchedAttendanceType = null;
                          });
                          if (_device.isConnected) _startScanLoop();
                        } else {
                          setState(() => _uiMode = _HomeUiMode.enroll);
                        }
                      },
                    ),
                    const Spacer(),
                    Text(
                      _timeString,
                      style: const TextStyle(
                        fontFamily: 'CEORUSE',
                        fontSize: 44,
                        color: Colors.white,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: isEnrollMode
                      ? _buildEnrollPortalBody(employee)
                      : _buildProfilePortalBody(employee),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopActionButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        width: 210,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1A4EA6) : const Color(0x66233D68),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFF77A8F9)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'CEORUSE',
            color: Colors.white,
            letterSpacing: 2,
            fontSize: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildProfilePortalBody(_EmployeeEntry employee) {
    final date = _matchedAt ?? DateTime.now();
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0x66223D68),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF6EA3F2)),
          ),
          child: Row(
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/images/Finger Print Icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'CEORUSE',
                        color: Colors.white,
                        fontSize: 32,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A89E8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        employee.id,
                        style: const TextStyle(
                          fontFamily: 'CEORUSE',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'TODAY: ${_matchedAttendanceType ?? 'RECORDED'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      _formatDateOnly(date),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x66223D68),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF6EA3F2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TODAY\'S LOG',
                  style: TextStyle(
                    fontFamily: 'CEORUSE',
                    color: Colors.white,
                    fontSize: 18,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                _buildLogRow('DATE', _formatDateOnly(date), true),
                _buildLogRow('TIME', _formatTimeOnly(date), false),
                _buildLogRow('STATUS', _matchedAttendanceType ?? 'RECORDED', false),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnrollPortalBody(_EmployeeEntry employee) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0x66223D68),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF6EA3F2)),
            ),
            child: const Text(
              'Enrollment Guide\n\nOpen Settings → Biometrics → Add Fingerprint, then place your finger on the sensor and lift it repeatedly until the scan is complete.\n\nPress PORTAL to go back to the employee home page.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                height: 1.4,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0x66223D68),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF6EA3F2)),
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: Colors.white,
                    size: 160,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildLogRow('EMPLOYEE', employee.name, false),
              _buildLogRow('ID', employee.id, false),
              _buildLogRow('STATUS', 'READY TO ENROLL', false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogRow(String label, String value, bool header) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: header ? const Color(0x774A89E8) : const Color(0x44223D68),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard(double screenW, double screenH) {
    final cardPadH = screenW * 0.03;
    final cardPadV = screenH * 0.04;

    return Stack(
      children: [
        // Card background
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(screenW * 0.015),
            child: Image.asset(
              'assets/images/card.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        // Card content
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: cardPadH,
              vertical: cardPadV,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardW = constraints.maxWidth;
                final cardH = constraints.maxHeight;

                return Stack(
                  children: [
                    // ── Fingerprint icon — top-right ──
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: cardH * 0.2,
                      width: cardW * 0.25,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Image.asset(
                          'assets/images/Finger Print Icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),

                    // ── Title — left, vertically centered ──
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: cardH * 0.22,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'AUTOMATED TIME\nAND ATTENDANCE\nSYSTEM',
                          style: TextStyle(
                            fontFamily: 'TRTCENZODEMO',
                            fontWeight: FontWeight.w600,
                            fontSize: cardW * 0.04,
                            color: Colors.white,
                            height: 1.15,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),

                    // ── Bottom-left: status buttons ──
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: Obx(
                        () => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStatusButton(
                              label: _controller.biometricConnected.value
                                  ? 'BIOMETRIC CONNECTED'
                                  : 'BIOMETRIC NOT CONNECTED',
                              textColor: _controller.biometricConnected.value
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFE53935),
                              cardW: cardW,
                              cardH: cardH,
                            ),
                            SizedBox(height: cardH * 0.02),
                            GestureDetector(
                              onTap: (_controller.isSearching.value ||
                                      _controller.biometricConnected.value)
                                  ? null
                                  : _searchAndConnect,
                              child: _buildStatusButton(
                                label: _controller.isSearching.value
                                    ? 'SEARCHING...'
                                    : _controller.isScanning.value
                                        ? 'SCANNING...'
                                        : _controller.biometricConnected.value
                                            ? 'ACTIVE'
                                            : 'SEARCH MODE',
                                textColor: (_controller.isSearching.value ||
                                        _controller.isScanning.value)
                                    ? const Color(0xFFFFB74D)
                                    : Colors.white,
                                cardW: cardW,
                                cardH: cardH,
                                showLoading: _controller.isSearching.value ||
                                    _controller.isScanning.value,
                              ),
                            ),
                            if (_controller.statusMessage.value.isNotEmpty) ...[
                              SizedBox(height: cardH * 0.015),
                              SizedBox(
                                width: cardW * 0.32,
                                child: Text(
                                  _controller.statusMessage.value,
                                  style: TextStyle(
                                    fontFamily: 'CEORUSE',
                                    fontSize: cardW * 0.012,
                                    color: Colors.white.withValues(alpha: 0.7),
                                    letterSpacing: 1,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            if (_controller.lastDbSyncLabel.value.isNotEmpty) ...[
                              SizedBox(height: cardH * 0.01),
                              SizedBox(
                                width: cardW * 0.32,
                                child: Text(
                                  _controller.lastDbSyncLabel.value,
                                  style: TextStyle(
                                    fontFamily: 'CEORUSE',
                                    fontSize: cardW * 0.0105,
                                    color: Colors.white.withValues(alpha: 0.6),
                                    letterSpacing: 0.8,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // ── Bottom-right: time & date ──
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Obx(
                        () => Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _timeString,
                              style: TextStyle(
                                fontFamily: 'CEORUSE',
                                fontSize: cardW * 0.055,
                                color: Colors.white,
                                letterSpacing: 4,
                                height: 1,
                              ),
                            ),
                            SizedBox(height: cardH * 0.01),
                            Text(
                              _dateString,
                              style: TextStyle(
                                fontFamily: 'CEORUSE',
                                fontSize: cardW * 0.024,
                                color: Colors.white.withValues(alpha: 0.85),
                                letterSpacing: 3,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Scan result overlay ──
                    _buildResultOverlay(cardW, cardH),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusButton({
    required String label,
    required Color textColor,
    required double cardW,
    required double cardH,
    bool showLoading = false,
  }) {
    return Container(
      width: cardW * 0.32,
      padding: EdgeInsets.symmetric(
        horizontal: cardW * 0.018,
        vertical: cardH * 0.028,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cardW * 0.01),
        border: Border.all(
          color: const Color(0xFF6B8CC4).withValues(alpha: 0.45),
          width: 1.2,
        ),
        image: const DecorationImage(
          image: AssetImage('assets/images/Main BG.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLoading) ...[
            SizedBox(
              width: cardW * 0.015,
              height: cardW * 0.015,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(textColor),
              ),
            ),
            SizedBox(width: cardW * 0.01),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'CEORUSE',
                fontSize: cardW * 0.016,
                color: textColor,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultOverlay(double cardW, double cardH) {
    if (!_showResult || _lastResult == null) return const SizedBox.shrink();

    final result = _lastResult!;
    final isSuccess = result.success;
    final overlayColor = isSuccess
        ? const Color(0xFF1B5E20).withValues(alpha: 0.93)
        : const Color(0xFFB71C1C).withValues(alpha: 0.93);

    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cardW * 0.015),
        child: Container(
          color: overlayColor,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSuccess
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  color: Colors.white,
                  size: cardW * 0.07,
                ),
                SizedBox(height: cardH * 0.025),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: cardW * 0.025,
                    vertical: cardH * 0.012,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isSuccess
                        ? 'RECORDED'
                        : (result.errorMessage ?? 'UNREGISTERED'),
                    style: TextStyle(
                      fontFamily: 'CEORUSE',
                      fontSize: cardW * 0.028,
                      color: Colors.white,
                      letterSpacing: 3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Add User (enrollment) ────────────────────────────────────────────────

  Widget _enrollTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: Color(0xFF7A9BBD), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF7A9BBD), size: 18),
        filled: true,
        fillColor: const Color(0xFF162233),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3E5A7A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3E5A7A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3E7DDD)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2A3A4A)),
        ),
      ),
    );
  }

  Future<void> _showAddUserDialog() async {
    if (!mounted) return;
    if (!_device.isConnected) {
      _controller.setStatus('Biometric not connected. Connect scanner first.');
      return;
    }
    _stopScanLoop();

    final empIdCtrl = TextEditingController();
    final empNameCtrl = TextEditingController();
    int captureCount = 0;
    bool isCapturing = false;
    bool isComplete = false;
    String statusMsg = 'Enter employee details, then press CAPTURE.';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (_, setDlg) {
            Future<void> doCapture() async {
              final empId = empIdCtrl.text.trim();
              if (empId.isEmpty) {
                setDlg(() => statusMsg = 'Employee ID is required.');
                return;
              }

              final digits = empId.replaceAll(RegExp(r'\D'), '');
              final fid = int.tryParse(
                    digits.length > 8
                        ? digits.substring(digits.length - 8)
                        : digits,
                  ) ??
                  (empId.hashCode.abs() % 999997 + 1);
              final siteId = _selectedSiteId;

              Future<void> finalizeEnrollment(
                Uint8List mergedTemplate,
                int enrolledFid,
              ) async {
                await _device.registerFingerprint(enrolledFid, mergedTemplate);
                final entry = _EmployeeEntry(
                  id: empId,
                  name: empNameCtrl.text.trim().isNotEmpty
                      ? empNameCtrl.text.trim()
                      : empId,
                );
                _employeeDb[enrolledFid] = entry;
                _employeeDbByFid[enrolledFid.toString()] = entry;

                if (siteId != null) {
                  await LocalDb.upsertEmployee(
                    fid: enrolledFid,
                    employeeId: empId,
                    employeeName: empNameCtrl.text.trim().isNotEmpty
                        ? empNameCtrl.text.trim()
                        : empId,
                    template: mergedTemplate,
                    siteId: siteId,
                  );
                }

                final saved = await _postEnrollment(
                  employeeId: empId,
                  employeeName: empNameCtrl.text.trim(),
                  template: mergedTemplate,
                  fingerId: enrolledFid,
                );

                setDlg(() {
                  isComplete = true;
                  isCapturing = false;
                  statusMsg = saved
                      ? 'Enrollment complete — employee registered.'
                      : 'Saved on scanner, but server update failed.';
                });
              }

              setDlg(() {
                isCapturing = true;
                statusMsg = 'Place finger on scanner (${captureCount + 1}/3)…';
              });

              if (ZKTecoUSB.isAndroidPlatform) {
                final completer = Completer<({
                  bool success,
                  String message,
                  String? fid,
                  Uint8List? template
                })>();
                final prevProgress = _device.onEnrollProgress;
                final prevResult = _device.onEnrollResult;

                _device.onEnrollProgress = (current, total, message) {
                  if (!mounted) return;
                  setDlg(() {
                    captureCount = current;
                    statusMsg = message;
                  });
                };

                _device.onEnrollResult =
                    (success, message, resultFid, template) {
                  if (!completer.isCompleted) {
                    completer.complete((
                      success: success,
                      message: message,
                      fid: resultFid,
                      template: template,
                    ));
                  }
                };

                final started =
                    await _device.startEnrollmentAndroid(fid.toString());
                if (!started) {
                  _device.onEnrollProgress = prevProgress;
                  _device.onEnrollResult = prevResult;
                  setDlg(() {
                    isCapturing = false;
                    statusMsg = 'Unable to start Android enrollment.';
                  });
                  return;
                }

                try {
                  final result = await completer.future.timeout(
                    const Duration(seconds: 35),
                  );
                  if (!result.success || result.template == null) {
                    setDlg(() {
                      isCapturing = false;
                      statusMsg = result.message;
                    });
                    return;
                  }

                  captureCount = 3;
                  final enrolledFid = _parseFingerId(result.fid) ?? fid;
                  await finalizeEnrollment(result.template!, enrolledFid);
                } catch (_) {
                  setDlg(() {
                    isCapturing = false;
                    statusMsg = 'Enrollment timed out. Please try again.';
                  });
                } finally {
                  _device.onEnrollProgress = prevProgress;
                  _device.onEnrollResult = prevResult;
                }
                return;
              }

              if (captureCount == 0) _device.startEnrollment();
              final res = await _device.captureForEnrollment();

              if (res.error != null) {
                setDlg(() {
                  isCapturing = false;
                  statusMsg = res.error!;
                });
                return;
              }

              captureCount = res.count;

              if (res.mergedTemplate != null) {
                await finalizeEnrollment(res.mergedTemplate!, fid);
              } else {
                setDlg(() {
                  isCapturing = false;
                  statusMsg =
                      'Capture $captureCount/3 done. Lift and press CAPTURE again.';
                });
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 26),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2A3B),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF3E5A7A),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ADD EMPLOYEE',
                      style: TextStyle(
                        fontFamily: 'CEORUSE',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Enroll a new employee fingerprint',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF7A9BBD),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _enrollTextField(
                      controller: empIdCtrl,
                      label: 'Employee ID',
                      icon: Icons.badge_outlined,
                      enabled: !isCapturing && !isComplete,
                    ),
                    const SizedBox(height: 10),
                    _enrollTextField(
                      controller: empNameCtrl,
                      label: 'Employee Name (optional)',
                      icon: Icons.person_outline,
                      enabled: !isCapturing && !isComplete,
                    ),
                    const SizedBox(height: 18),
                    // Capture progress dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (i) {
                        final done = i < captureCount;
                        return Container(
                          width: 14,
                          height: 14,
                          margin:
                              const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFF2A3A4A),
                            border: Border.all(
                              color: done
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFF5A7A9A),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    // Status area
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF162233),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          if (isCapturing)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFFFFB74D)),
                              ),
                            )
                          else
                            Icon(
                              isComplete
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                              size: 14,
                              color: isComplete
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFF7A9BBD),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              statusMsg,
                              style: const TextStyle(
                                fontFamily: 'CEORUSE',
                                fontSize: 11,
                                color: Colors.white70,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton(
                              onPressed: isCapturing
                                  ? null
                                  : () => Navigator.of(dlgCtx).pop(),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Color(0xFF3E5A7A)),
                                foregroundColor: const Color(0xFF7A9BBD),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child:
                                  Text(isComplete ? 'DONE' : 'CANCEL'),
                            ),
                          ),
                        ),
                        if (!isComplete) ...[const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: ElevatedButton(
                                onPressed:
                                    isCapturing ? null : doCapture,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF3E7DDD),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(captureCount == 0
                                    ? 'START'
                                    : 'CAPTURE'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    empIdCtrl.dispose();
    empNameCtrl.dispose();
    if (mounted && _device.isConnected) _startScanLoop();
  }

  Future<bool> _postEnrollment({
    required String employeeId,
    required String employeeName,
    required Uint8List template,
    required int fingerId,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      try {
        final uri = Uri.parse('$_apiBaseUrl$_thumbDetailsApiEndpoint').replace(
          queryParameters: {'employeeID': employeeId},
        );
        final request = await client.putUrl(uri);
        final basicToken =
            base64Encode(utf8.encode('$_apiUsername:$_apiPassword'));
        request.headers
            .set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Basic $basicToken');
        final payload = jsonEncode({
          'employeeID': employeeId,
          'leftFingerThumb': base64Encode(template),
          'rightFingerThumb': base64Encode(template),
          'fingerID': fingerId,
          'employeeName': employeeName,
        });
        request.contentLength = utf8.encode(payload).length;
        request.write(payload);
        final response = await request.close();
        await response.transform(utf8.decoder).join();
        return response.statusCode >= 200 && response.statusCode < 300;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('_postEnrollment error: $e');
      return false;
    }
  }
}
