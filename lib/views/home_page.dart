import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/local_db.dart';
import '../controllers/home_page_controller.dart';
import '../zkfp/zkteco_usb.dart';
import 'dashboard_page.dart';
import 'enrollment_page.dart';
import 'loading_page.dart';
import 'navigation_drawer.dart' as custom;

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

class _ScanActionGate {
  const _ScanActionGate({
    required this.blocked,
    this.label,
    this.message,
  });

  final bool blocked;
  final String? label;
  final String? message;
}

enum _HomeUiMode { scanner, portal }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
  Timer? _deviceHealthTimer;
  bool _isLiveSyncRunning = false;
  int _portalSessionToken = 0;
  String? _lastHrisError;
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
        // Keep API → SQLite sync running when scanner disconnects.
        _stopScanLoop();
      };
      _device.onTemplateExtracted = (template, size) {
        if (_controller.isScanning.value) _onTemplateReady(template);
      };
    }

    // Keep controller state aligned with the actual device connection for all platforms
    _deviceHealthTimer?.cancel();
    _deviceHealthTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final actualConnected = _device.isConnected;
      final uiConnected = _controller.biometricConnected.value;
      if (uiConnected != actualConnected) {
        _controller.setConnected(actualConnected);
        if (!actualConnected) {
          _controller.setStatus('Disconnected - Biometric device not found');
          _stopScanLoop();
        }
      }
    });
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

      return list
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
        'Cannot load site list. Please check API connection.',
      );
      return;
    }
    _controller.setStatus('');

    // Step 2 — let the user choose their work site
    final selected = await _showSiteSelectionDialog(requiredSelection: true);
    if (!mounted || selected == null) return;

    setState(() => _selectedSiteId = selected);
    await LocalDb.pruneToSite(selected);
    _controller.setStatus(
      'Selected site: ${_siteNameById(selected) ?? selected}',
    );

    // Step 3 — NOW show the loading screen while connecting + syncing data
    if (!mounted) return;
    final syncFuture = _connectAndSync();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoadingPage(loadFuture: syncFuture),
        fullscreenDialog: true,
      ),
    );
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
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
                                  side: const BorderSide(
                                    color: Color(0xFFD6DBE5),
                                  ),
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
                                onPressed: () =>
                                    Navigator.of(context).pop(selectedId),
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
    _deviceHealthTimer?.cancel();
    _deviceHealthTimer = null;
    _device.dispose();
    if (Get.isRegistered<HomePageController>()) {
      Get.delete<HomePageController>();
    }
    super.dispose();
  }

  /// Pure async connect + sync — NO dialogs, NO Navigator calls.
  /// Safe to run as the loadFuture inside LoadingPage.
  Future<void> _connectAndSync() async {
    // Server sync does not require the biometric device. Run first so employees
    // / timelogs / queued HRIS replay work even if USB open fails.
    final siteId = _selectedSiteId;
    if (siteId != null && siteId.isNotEmpty) {
      await _runBackgroundSyncTick();
      _startLiveDbSync();
    }

    _controller.startSearching('Searching for device...');
    try {
      if (ZKTecoUSB.isAndroidPlatform) {
        final env = await _device.getAndroidSdkEnvironment();
        if (env['canUseSdk'] != true) {
          _controller.stopSearching(
            env['reason']?.toString() ??
                'SDK not compatible. Ensure a physical Android device with the scanner attached.',
          );
          return;
        }
        // USB list does not require native SDK; fail fast if nothing is on the bus.
        final countUsb = await _device.getDeviceCountAsync();
        if (countUsb == 0) {
          _controller.stopSearching(
            'No ZKTeco reader on USB. Use OTG, try another cable/port, '
            'and grant permission when Android prompts.',
          );
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
        _controller.stopSearching(
          ZKTecoUSB.isAndroidPlatform
              ? 'Reader not detected after SDK init. Reconnect USB and retry.'
              : 'No device found. Plug in the scanner and retry.',
        );
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
        true,
        status: 'Connected: ${serial ?? "Unknown"}$siteText',
      );

      // Push latest API employees into SQLite and register on scanner.
      await _loadAndRegisterTemplates();
    } on PlatformException catch (e) {
      _controller.stopSearching(
        e.message != null && e.message!.isNotEmpty
            ? '${e.code}: ${e.message}'
            : e.code,
      );
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
        'Cannot load site list. Please check API connection.',
      );
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
    _controller.setStatus(
      'Selected site: ${_siteNameById(selected) ?? selected}',
    );

    // Step 3 — ONLY NOW show the loading screen (connect + sync)
    if (!mounted) return;
    final syncFuture = _connectAndSync();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoadingPage(loadFuture: syncFuture),
        fullscreenDialog: true,
      ),
    );
    if (mounted) _startScanLoop();
  }

  // ==================== Template Loading & Scan Loop ====================

  Future<void> _loadAndRegisterTemplates() async {
    if (!mounted) return;
    final siteId = _selectedSiteId;
    if (siteId == null) {
      // No site selected, do not proceed.
      return;
    }

    // Removed status text about syncing fingerprint data to local database.
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
      final rows = _extractSiteRows(decoded);

      int totalEmps = 0;
      int skippedEmps = 0;
      int savedFingerprints = 0;
      int skippedTemplates = 0;
      final templatesToSave = <Map<String, dynamic>>[];
      for (final row in rows) {
        totalEmps++;
        final empId =
            (row['employee_id'] ?? row['emp_id'] ?? row['id'] ?? row['EMPID'])
                ?.toString()
                .trim();
        final firstName = (row['FIRSTNAME'] ?? row['first_name'])
            ?.toString()
            .trim();
        final middleName = (row['MIDDLENAME'] ?? row['middle_name'])
            ?.toString()
            .trim();
        final lastName = (row['LASTNAME'] ?? row['last_name'])
            ?.toString()
            .trim();
        final fullNameParts = [firstName, middleName, lastName]
            .whereType<String>()
            .where((part) => part.isNotEmpty && part.toLowerCase() != 'null')
            .toList();
        final empName =
            (row['employee_name'] ?? row['full_name'] ?? row['name'])
                ?.toString()
                .trim();
        final resolvedName = fullNameParts.isNotEmpty
            ? fullNameParts.join(' ')
            : ((empName != null &&
                      empName.isNotEmpty &&
                      empName.toLowerCase() != 'null')
                  ? empName
                  : null);

        if (empId == null || empId.isEmpty) {
          skippedEmps++;
          continue;
        }

        final thumbTemplates = <String, String?>{
          'left':
              (row['LEFTFINGERTHUMB'] ??
                      row['leftFingerThumb'] ??
                      row['left_thumb'])
                  ?.toString(),
          'right':
              (row['RIGHTFINGERTHUMB'] ??
                      row['rightFingerThumb'] ??
                      row['right_thumb'])
                  ?.toString(),
          'default':
              (row['finger_template'] ?? row['template'] ?? row['fingerprint'])
                  ?.toString(),
        };

        for (final entry in thumbTemplates.entries) {
          final templateB64 = entry.value?.trim();
          if (templateB64 == null ||
              templateB64.isEmpty ||
              templateB64.toLowerCase() == 'null') {
            skippedTemplates++;
            continue;
          }

          try {
            final fid = _stableFingerprintId(empId, entry.key);
            templatesToSave.add({
              'fid': fid,
              'employee_id': empId,
              'employee_name': resolvedName,
              'finger_template': base64Decode(templateB64),
            });
            savedFingerprints++;
          } catch (_) {
            skippedTemplates++;
          }
        }
      }

      await LocalDb.replaceEmployeesBySite(
        siteId: siteId,
        employees: templatesToSave,
      );

      final dbCount = await LocalDb.getEmployeeCountBySite(siteId);
      debugPrint(
        '[SYNC_DEBUG] site=$siteId employees=$totalEmps skippedEmployees=$skippedEmps '
        'savedTemplates=$savedFingerprints skippedTemplates=$skippedTemplates dbCount=$dbCount',
      );
      _controller.setLastDbSync();
    } catch (e) {
      debugPrint('_syncEmployeesFromApiToLocalDb: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// Sync employees + timelogs + HRIS queue from server; load templates onto
  /// the scanner only while the device is connected.
  Future<void> _runBackgroundSyncTick() async {
    if (!mounted || _isLiveSyncRunning) return;
    final siteId = _selectedSiteId;
    if (siteId == null || siteId.isEmpty) return;

    _isLiveSyncRunning = true;
    try {
      await _syncEmployeesFromApiToLocalDb(siteId);
      await _fetchAndCacheSiteTimeLogs();
      await _syncPendingHrisQueue();
      if (_device.isConnected) {
        await _loadFromLocalDb(siteId);
      }
    } catch (e) {
      debugPrint('_runBackgroundSyncTick: $e');
    } finally {
      _isLiveSyncRunning = false;
    }
  }

  void _startLiveDbSync() {
    _liveSyncTimer?.cancel();
    // First sync is awaited in _connectAndSync; timer only repeats.
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(_runBackgroundSyncTick());
    });
  }

  void _stopLiveDbSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
    _isLiveSyncRunning = false;
  }

  Future<void> _loadFromLocalDb(String siteId) async {
    if (!_device.isConnected) return;
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
        final entry = _EmployeeEntry(id: empId, name: empName ?? empId);
        _employeeDb[fid] = entry;
        _employeeDbByFid[fid.toString()] = entry;
        registered++;
      }

      if (!mounted) return;
      // Status message about loading from local DB removed as requested.
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
        final request = await client.getUrl(
          Uri.parse('$_timelogPerSiteApiUrl$siteId'),
        );
        final basicToken = base64Encode(
          utf8.encode('$_apiUsername:$_apiPassword'),
        );
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic $basicToken',
        );

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode < 200 || response.statusCode > 299) {
          throw Exception('HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(body);
        final rows = _extractSiteRows(decoded);
        if (rows.isEmpty) {
          // Avoid wiping local cache when server temporarily returns no rows.
          return;
        }
        final mappableRows = rows.where((row) {
          final employeeId = (row['employee_id'] ??
                  row['employeeID'] ??
                  row['employeeId'] ??
                  row['employeeid'] ??
                  row['companyID'] ??
                  row['companyId'] ??
                  row['company_id'] ??
                  row['emp_id'] ??
                  row['empid'] ??
                  row['EMPID'])
              ?.toString()
              .trim();
          return employeeId != null && employeeId.isNotEmpty;
        }).length;
        if (mappableRows == 0) {
          // Endpoint payload shape changed or incomplete; keep previous cache.
          return;
        }
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
    _scanTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
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

  void _restartScanWhileOnDashboard() {
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted || !_device.isConnected) return;
      // Keep scanner active even while portal/dashboard is visible so
      // immediate second scans can be validated (e.g. ALREADY TIME IN).
      _startScanLoop();
    });
  }

  void _scheduleScannerResume() {
    _portalAutoReturnTimer?.cancel();
    final token = ++_portalSessionToken;
    _portalAutoReturnTimer = Timer(const Duration(seconds: 50), () {
      if (token != _portalSessionToken) return;
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
    // Fail-safe in case timer callback is skipped during heavy UI work.
    Future<void>.delayed(const Duration(seconds: 65), () {
      if (!mounted) return;
      if (token != _portalSessionToken) return;
      if (_uiMode != _HomeUiMode.portal) return;
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
      unawaited(_fetchAndCacheSiteTimeLogs());
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
        '${employee.name} — ${attendanceType ?? 'RECORDED'}',
      );
      _restartScanWhileOnDashboard();
    } else {
      _displayResult(
        _ScanResult(
          success: false,
          timestamp: DateTime.now(),
          errorMessage: fid != null
              ? 'Employee not on record'
              : 'Fingerprint not registered',
        ),
      );
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
            .timeout(
              const Duration(milliseconds: 180),
              onTimeout: () {
                return (match: false, score: null);
              },
            );
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
    _lastHrisError = null;

    // Pull latest server timelog first so pending IN/OUT decision uses
    // current HRIS state (including multi-device usage).
    await _fetchAndCacheSiteTimeLogs().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );

    var pending = await _buildPendingTimeLog(
      employeeId: employeeId,
      siteId: siteId,
      now: DateTime.now(),
    );
    debugPrint('Attempting time log with code: ${pending.code}');
    final gate = _scanActionGate(pending, DateTime.now());
    if (gate.blocked) {
      return gate.label ?? 'ALREADY TIME IN';
    }

    var requests = _buildAttendanceRequests(
      siteId: siteId,
      employeeId: employeeId,
      pending: pending,
    );

    // First request is the critical write (timeIn/timeOut).
    final primary = requests.first;
    final primarySent = await _sendHrisRequest(
      endpoint: primary.$1,
      queryParams: primary.$2,
    ).timeout(const Duration(seconds: 5), onTimeout: () => false);

    var attendanceSaved = primarySent;
    if (!attendanceSaved) {
      // Some deployments require a timelog row to exist before update/timeIn|Out.
      // Bootstrap by inserting the timelog, then retry the primary update once.
      final seed = requests.where((r) => r.$1 == _insertTimeLogApiEndpoint);
      if (seed.isNotEmpty) {
        final seeded = await _sendHrisRequest(
          endpoint: seed.first.$1,
          queryParams: seed.first.$2,
        ).timeout(const Duration(seconds: 5), onTimeout: () => false);
        if (seeded) {
          // Refresh after insert because server may assign/normalize timelogID.
          await _fetchAndCacheSiteTimeLogs();
          pending = await _buildPendingTimeLog(
            employeeId: employeeId,
            siteId: siteId,
            now: DateTime.now(),
          );
          requests = _buildAttendanceRequests(
            siteId: siteId,
            employeeId: employeeId,
            pending: pending,
          );
          final retriedPrimary = requests.first;
          attendanceSaved = await _sendHrisRequest(
            endpoint: retriedPrimary.$1,
            queryParams: retriedPrimary.$2,
          ).timeout(const Duration(seconds: 5), onTimeout: () => false);
        }
      }
    }

    if (attendanceSaved) {
      // Secondary requests (logs/audit) are important but should not change
      // the UI result when the core attendance record is already saved.
      for (final request in requests.skip(1)) {
        if (request.$1 == _insertTimeLogApiEndpoint && !primarySent) {
          // Already inserted during bootstrap step above.
          continue;
        }
        final sent = await _sendHrisRequest(
          endpoint: request.$1,
          queryParams: request.$2,
        ).timeout(const Duration(seconds: 5), onTimeout: () => false);
        if (!sent) {
          await LocalDb.queueHrisRequest(
            endpoint: request.$1,
            queryParams: request.$2,
          );
        }
      }
      final attendanceLabel = pending.code.startsWith('IN')
          ? 'TIME IN'
          : 'TIME OUT';
      await LocalDb.pushRealtimeTimelog(
        siteId: siteId,
        employeeId: employeeId,
        row: {
          'employee_id': employeeId,
          'companyID': employeeId,
          'timelogID': pending.timeLogId,
          'timelog': pending.timeLogDate,
          'remarks': pending.remarks,
          'schedule': pending.schedule,
          'timeInMorning': pending.timeInMorning ?? '',
          'timeOutMorning': pending.timeOutMorning ?? '',
          'timeInAfternoon': pending.timeInAfternoon ?? '',
          'timeOutAfternoon': pending.timeOutAfternoon ?? '',
          'code': pending.code,
        },
      );
      return attendanceLabel;
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
    ).timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (legacyType != null) {
      return legacyType;
    }

    if (_lastHrisError != null && _lastHrisError!.isNotEmpty) {
      _controller.setStatus(_lastHrisError!);
    }
    return pending.code.startsWith('IN')
        ? 'TIME IN UNSUCCESSFUL'
        : 'TIME OUT UNSUCCESSFUL';
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
    final cachedDateText =
        (cached?['timelog'] ??
                cached?['timeLogDate'] ??
                cached?['timelog_date'] ??
                cached?['datecaptured'] ??
                cached?['datelog'] ??
                '')
            .toString();
    final cachedDateOnly = _normalizeDateOnly(cachedDateText);
    final useTodayCache = cachedDateOnly == date;

    final timeLogId =
        (useTodayCache
                    ? (cached?['timelogID'] ??
                        cached?['timeLogID'] ??
                        cached?['timelog_id'])
                    : null) ??
            '$employeeId-$date'
            .toString();
    final remarks = (cached?['remarks'] ?? cached?['remark'] ?? '').toString();
    final schedule = ((cached?['schedule'] ?? cached?['schedCode']) ?? '')
        .toString();

    final existingInMorning = (!useTodayCache)
        ? null
        : (_pickFirstValue(cached, const [
            'timeInMorning',
            'timeinmorning',
            'time_in_morning',
            'time_in',
          ]));
    final existingOutMorning = (!useTodayCache)
        ? null
        : (_pickFirstValue(cached, const [
            'timeOutMorning',
            'timeoutmorning',
            'time_out_morning',
            'time_out',
          ]));
    final existingInAfternoon = (!useTodayCache)
        ? null
        : (_pickFirstValue(cached, const [
            'timeInAfternoon',
            'timeinafternoon',
            'time_in_afternoon',
          ]));
    final existingOutAfternoon = (!useTodayCache)
        ? null
        : (_pickFirstValue(cached, const [
            'timeOutAfternoon',
            'timeoutafternoon',
            'time_out_afternoon',
          ]));

    final existingIn = existingInMorning ?? existingInAfternoon;
    final existingOut = existingOutMorning ?? existingOutAfternoon;

    if (existingIn == null) {
      return _PendingTimeLog(
        timeLogId: timeLogId,
        timeLogDate: date,
        remarks: remarks,
        schedule: schedule,
        code: 'IN_AM',
        timeInMorning: time,
        timeOutMorning: null,
        timeInAfternoon: null,
        timeOutAfternoon: null,
      );
    }

    if (existingOut == null) {
      return _PendingTimeLog(
        timeLogId: timeLogId,
        timeLogDate: date,
        remarks: remarks,
        schedule: schedule,
        code: 'OUT_PM',
        timeInMorning: existingIn,
        timeOutMorning: time,
        timeInAfternoon: null,
        timeOutAfternoon: null,
      );
    }

    return _PendingTimeLog(
      timeLogId: timeLogId,
      timeLogDate: date,
      remarks: remarks,
      schedule: schedule,
      code: 'ALREADY_OUT',
      timeInMorning: existingIn,
      timeOutMorning: existingOut,
      timeInAfternoon: null,
      timeOutAfternoon: null,
    );
  }

  _ScanActionGate _scanActionGate(_PendingTimeLog pending, DateTime now) {
    if (pending.code == 'OUT_PM') {
      final parsedIn = _parseClockTimeToday(
        pending.timeInMorning ?? pending.timeInAfternoon,
        now,
      );
      if (parsedIn != null && now.difference(parsedIn).inMinutes < 20) {
        return const _ScanActionGate(
          blocked: true,
          label: 'ALREADY TIME IN',
          message: 'Please wait 20 minutes before time out.',
        );
      }
    }
    if (pending.code == 'ALREADY_OUT') {
      return const _ScanActionGate(
        blocked: true,
        label: 'ALREADY TIME OUT',
        message: 'You already timed out for today.',
      );
    }
    return const _ScanActionGate(blocked: false);
  }

  DateTime? _parseClockTimeToday(String? text, DateTime now) {
    if (text == null) return null;
    final clean = text.trim();
    if (clean.isEmpty) return null;
    final parts = clean.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    if (hour == null || minute == null) return null;
    return DateTime(now.year, now.month, now.day, hour, minute, second);
  }

  String? _pickFirstValue(Map<String, dynamic>? row, List<String> keys) {
    if (row == null) return null;
    for (final key in keys) {
      final raw = row[key];
      if (_isBlank(raw)) continue;
      return '$raw';
    }
    return null;
  }

  String _normalizeDateOnly(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return '';
    final parsed = DateTime.tryParse(input);
    if (parsed != null) return _formatDateOnly(parsed);
    if (input.contains(' ')) {
      final first = input.split(' ').first.trim();
      final parsedFirst = DateTime.tryParse(first);
      if (parsedFirst != null) return _formatDateOnly(parsedFirst);
    }
    if (input.contains('T')) {
      final first = input.split('T').first.trim();
      final parsedFirst = DateTime.tryParse(first);
      if (parsedFirst != null) return _formatDateOnly(parsedFirst);
    }
    return input.length >= 10 ? input.substring(0, 10) : input;
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
    final baseUri = Uri.parse('$_apiBaseUrl$endpoint');
    final getUri = baseUri.replace(queryParameters: queryParams);

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 12);
      try {
        final request = await client.getUrl(getUri);
        final basicToken = base64Encode(
          utf8.encode('$_apiUsername:$_apiPassword'),
        );
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic $basicToken',
        );
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final ok = response.statusCode >= 200 && response.statusCode < 300;
        if (!ok &&
            response.statusCode == 405 &&
            body.toUpperCase().contains('POST')) {
          // Backend requires POST for this endpoint; retry automatically.
          final postRequest = await client.postUrl(getUri);
          postRequest.headers.set(HttpHeaders.acceptHeader, 'application/json');
          postRequest.headers.set(
            HttpHeaders.userAgentHeader,
            'FAST-Attendance/1.0',
          );
          postRequest.headers.set(
            HttpHeaders.authorizationHeader,
            'Basic $basicToken',
          );
          postRequest.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json',
          );
          final payload = jsonEncode(queryParams);
          postRequest.contentLength = utf8.encode(payload).length;
          postRequest.write(payload);
          final postResponse = await postRequest.close();
          final postBody = await postResponse.transform(utf8.decoder).join();
          final postOk =
              postResponse.statusCode >= 200 && postResponse.statusCode < 300;
          if (!postOk) {
            final compactBody = postBody.replaceAll(RegExp(r'\s+'), ' ').trim();
            final shortBody = compactBody.length > 220
                ? '${compactBody.substring(0, 220)}...'
                : compactBody;
            _lastHrisError =
                'HRIS $endpoint POST failed (${postResponse.statusCode}): $shortBody';
            debugPrint(_lastHrisError);
          }
          if (postOk &&
              (endpoint == _timeInApiEndpoint ||
                  endpoint == _timeOutApiEndpoint)) {
            debugPrint('HRIS $endpoint POST success: $queryParams');
          }
          return postOk;
        }
        if (!ok) {
          final compactBody = body.replaceAll(RegExp(r'\s+'), ' ').trim();
          final shortBody = compactBody.length > 220
              ? '${compactBody.substring(0, 220)}...'
              : compactBody;
          _lastHrisError =
              'HRIS $endpoint failed (${response.statusCode}): $shortBody';
          debugPrint(_lastHrisError);
        }
        if (ok &&
            (endpoint == _timeInApiEndpoint ||
                endpoint == _timeOutApiEndpoint)) {
          debugPrint('HRIS $endpoint success: $queryParams');
        }
        return ok;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _lastHrisError = 'HRIS $endpoint error: $e';
      debugPrint(_lastHrisError);
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

  String _normalizeEmployeeId(String raw) {
    final trimmed = raw.trim().toUpperCase();
    if (trimmed.isEmpty) return '';
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isNotEmpty) {
      final noLeadingZeros = digitsOnly.replaceFirst(RegExp(r'^0+'), '');
      return noLeadingZeros.isEmpty ? '0' : noLeadingZeros;
    }
    return trimmed.replaceAll(RegExp(r'\s+'), '');
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
        final request = await client.postUrl(
          Uri.parse(_legacyAttendanceApiUrl),
        );
        final basicToken = base64Encode(
          utf8.encode('$_apiUsername:$_apiPassword'),
        );
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic $basicToken',
        );

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
          final type =
              decoded['attendance_type'] ??
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
    return '${months[currentTime.month - 1]} ${currentTime.day}, ${currentTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    if (_uiMode == _HomeUiMode.portal) {
      return DashboardPage(
        employeeId: _matchedEmployee?.id,
        employeeName: _matchedEmployee?.name,
        attendanceType: _matchedAttendanceType,
        matchedAt: _matchedAt,
        siteId: _selectedSiteId,
        onPortalTap: () {
          _portalAutoReturnTimer?.cancel();
          setState(() {
            _uiMode = _HomeUiMode.scanner;
            _matchedEmployee = null;
            _matchedAt = null;
            _matchedAttendanceType = null;
          });
          if (_device.isConnected) _startScanLoop();
        },
        onEnrollNowTap: () {
          _portalAutoReturnTimer?.cancel();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EnrollmentPage(
                employeeId: _matchedEmployee?.id,
                employeeName: _matchedEmployee?.name,
                siteId: _selectedSiteId,
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(
              Icons.menu,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const SizedBox.shrink(),
        centerTitle: true,
      ),
      drawer: custom.NavigationDrawer(
        selectedSiteId: _selectedSiteId,
      ),
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
          child: (_selectedSiteId == null)
              ? const SizedBox.shrink()
              : Padding(
                  padding: EdgeInsets.only(
                    left: screenW * 0.015,
                    right: screenW * 0.015,
                    bottom: screenH * 0.015,
                  ),
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: screenH - (screenH * 0.03) - kToolbarHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // ADD USER button moved to navigation drawer
                              ],
                            ),
                            SizedBox(height: screenH * 0.018),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: _buildMainCard(screenW, screenH),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildMainCard(double screenW, double screenH) {
    final cardPadH = screenW * 0.03;
    final cardPadV = screenH * 0.1;

    return Stack(
      children: [
        // Card background with FAST logo inside
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(screenW * 0.08), // much more radiused
              topRight: Radius.circular(screenW * 0.015),
              bottomLeft: Radius.circular(screenW * 0.015),
              bottomRight: Radius.circular(screenW * 0.015),
            ),
            child: Stack(
              children: [
                Image.asset(
                  'assets/images/cardmodified123.png',
                  fit: BoxFit.cover,
                ),
                Positioned(
                  left: screenW * 0.025,
                  top: screenH * 0.001,
                  child: Image.asset(
                    'assets/images/FastLogo.png',
                    width: screenW * 0.18,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Animated square particles (same style as loading page)
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(screenW * 0.015),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cw = constraints.maxWidth;
                final ch = constraints.maxHeight;
                final ps = (cw * 0.06).clamp(32.0, 56.0);
                return Stack(
                  children: [
                    _cardParticle(cw, ch, 0.08, 0.15, ps * 1.2, 0),
                    _cardParticle(cw, ch, 0.12, 0.08, ps * 0.5, 0.3),
                    _cardParticle(cw, ch, 0.18, 0.5, ps * 0.9, 0.6),
                    _cardParticle(cw, ch, 0.75, 0.45, ps * 1.1, 0.2),
                    _cardParticle(cw, ch, 0.5, 0.2, ps * 0.55, 0.5),
                    _cardParticle(cw, ch, 0.08, 0.7, ps * 1.0, 0.8),
                    _cardParticle(cw, ch, 0.28, 0.35, ps * 0.45, 0.15),
                    _cardParticle(cw, ch, 0.72, 0.3, ps * 0.9, 0.45),
                    _cardParticle(cw, ch, 0.38, 0.78, ps * 0.6, 0.7),
                    _cardParticle(cw, ch, 0.88, 0.6, ps * 1.15, 0.25),
                    _cardParticle(cw, ch, 0.05, 0.42, ps * 0.5, 0.9),
                    _cardParticle(cw, ch, 0.62, 0.48, ps * 0.75, 0.35),
                  ],
                );
              },
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
                    // ── Time & date — bottom-right transparent area ──
                    Positioned(
                      right: 0,
                      bottom: cardH * 0.045,
                      child: Obx(
                        () => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _timeString,
                              style: TextStyle(
                                fontFamily: 'CEORUSE',
                                fontSize: cardW * 0.07,
                                color: Colors.white,
                                letterSpacing: 4,
                                height: 1,
                              ),
                            ),
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

                    // ── Fingerprint icon — top-right ──
                    Positioned(
                      top: cardH * 0.005,
                      right: cardW * 0.01,
                      bottom: cardH * 0.20,
                      width: cardW * 0.30,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Obx(
                          () => Image.asset(
                            _controller.biometricConnected.value
                                ? 'assets/images/HIRSLogo-scanner-connected.png'
                                : 'assets/images/HIRSLogo-scanner-unconnected.png',
                            fit: BoxFit.contain,
                          ),
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
                            fontSize: cardW * 0.06,
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
                          crossAxisAlignment: CrossAxisAlignment.center,
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
                              onTap:
                                  (_controller.isSearching.value ||
                                      _device.isConnected)
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
                                textColor:
                                    (_controller.isSearching.value ||
                                        _controller.isScanning.value)
                                    ? const Color(0xFFFFB74D)
                                    : Colors.white,
                                cardW: cardW,
                                cardH: cardH,
                                showLoading:
                                    _controller.isSearching.value ||
                                    _controller.isScanning.value,
                              ),
                            ),
                            if (_controller.statusMessage.value.isNotEmpty) ...[
                              // Status message below the button removed as requested.
                            ],
                            if (_controller
                                .lastDbSyncLabel
                                .value
                                .isNotEmpty) ...[
                              SizedBox(height: cardH * 0.01),
                              SizedBox(
                                width: cardW * 0.43,
                                child: Opacity(
                                  opacity: 0.0,
                                  child: Text(
                                    _controller.lastDbSyncLabel.value,
                                    style: TextStyle(
                                      fontFamily: 'CEORUSE',
                                      fontSize: cardW * 0.0105,
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                      letterSpacing: 0.8,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
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

  Widget _cardParticle(
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
      child: _CardRisingFadeParticle(
        size: sizePx,
        phase: phase,
        assetPath: 'assets/icons/square-particles-fx.svg',
      ),
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
      width: cardW * 0.47,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
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
              textAlign: TextAlign.center,
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
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF7A9BBD), fontSize: 13),
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
    
    // Navigate to enrollment page for manual registration
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EnrollmentPage(
          siteId: _selectedSiteId,
          // Don't pass employeeId/employeeName - let user input their own
        ),
      ),
    );
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
        final uri = Uri.parse(
          '$_apiBaseUrl$_thumbDetailsApiEndpoint',
        ).replace(queryParameters: {'employeeID': employeeId});
        final request = await client.putUrl(uri);
        final basicToken = base64Encode(
          utf8.encode('$_apiUsername:$_apiPassword'),
        );
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic $basicToken',
        );
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

class _CardRisingFadeParticle extends StatefulWidget {
  const _CardRisingFadeParticle({
    required this.size,
    required this.assetPath,
    this.phase = 0.0,
  });

  final double size;
  final String assetPath;
  final double phase;

  @override
  State<_CardRisingFadeParticle> createState() =>
      _CardRisingFadeParticleState();
}

class _CardRisingFadeParticleState extends State<_CardRisingFadeParticle>
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
    _opacity = Tween<double>(begin: 0.7, end: 0.0).animate(curve);
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
