import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/local_db.dart';
import '../legacy_home_page_controller.dart';
import '../zkfp/zkteco_usb.dart';
import '../route_observer.dart';
import 'loading_page.dart';
import 'success_loading_page.dart';
import 'dashboard_page.dart';
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

enum _ScanResultType {
  timeInSuccess,
  timeOutSuccess,
  alreadyTimedIn,
  alreadyTimedOut,
  timeInUnsuccessful,
  timeOutUnsuccessful,
  fingerprintNotRecognized,
}

class _ScanResult {
  const _ScanResult({
    required this.success,
    required this.timestamp,
    this.errorMessage,
    this.type = _ScanResultType.fingerprintNotRecognized,
    this.employeeName,
    this.attendanceType,
  });

  final bool success;
  final DateTime timestamp;
  final String? errorMessage;
  final _ScanResultType type;
  final String? employeeName;
  final String? attendanceType;
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

enum _HomeUiMode { scanner, portal }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
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
  late final LegacyHomePageController _controller;

  // Scan loop state
  Timer? _scanTimer;
  Timer? _liveSyncTimer;
  Timer? _portalAutoReturnTimer;
  bool _isLiveSyncRunning = false;
  void Function(Uint8List template, int size)? _templateHandler;

  // Android template callback can keep firing even when our UI state is stale.
  // Track whether HomePage is the active route and whether we are currently processing a template.
  bool _isActiveRoute = true;
  bool _isProcessingTemplate = false;
  DateTime? _lastTemplateHandledAt;
  bool _routeSubscribed = false;
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
    _isActiveRoute = true;

    // Controller is provided by AppBinding (MVP-style DI)
    _controller = Get.find<LegacyHomePageController>();
    
    _loadDeviceSiteMap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requireSiteSelectionOnStartup();
    });

    // Set up Android callbacks
    if (ZKTecoUSB.isAndroidPlatform) {
      _device.onDeviceAttached = () {
        _controller.setStatus('Device attached!');
        // Auto-connect when device is attached
        _autoConnectIfSiteSelected();
      };
      _device.onDeviceDetached = () {
        _controller.setConnected(false, status: 'Device detached');
        _employeeDb.clear();
        _employeeDbByFid.clear();
        _isProcessingTemplate = false;
        _lastTemplateHandledAt = null;
        _portalAutoReturnTimer?.cancel();
        _stopLiveDbSync();
        _stopScanLoop();
      };
      _templateHandler = (template, size) {
        _handleAndroidTemplate(template, size);
      };
      _device.onTemplateExtracted = _templateHandler;
    }

    // Try to auto-connect if already have site selected
    _autoConnectIfSiteSelected();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_routeSubscribed) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) {
        routeObserver.subscribe(this, route);
        _routeSubscribed = true;
      }
    }
  }

  @override
  void didPopNext() {
    // Returned to HomePage from another route. Resume scanning.
    if (!mounted) return;

    _isActiveRoute = true;
    if (ZKTecoUSB.isAndroidPlatform) {
      _templateHandler ??= (template, size) {
        _handleAndroidTemplate(template, size);
      };
      _device.onTemplateExtracted = _templateHandler;
    }

    if (_selectedSiteId != null) {
      _reloadEmployeesForCurrentSite();
    }

    if (_device.isConnected && _uiMode == _HomeUiMode.scanner) {
      debugPrint('[HOME_SCAN] didPopNext: restarting scan loop');
      _restartScanningWithFeedback();
    } else if (!_device.isConnected && _selectedSiteId != null) {
      _autoConnectIfSiteSelected();
    }
  }

  @override
  void didPushNext() {
    // Navigating away from HomePage.
    _isActiveRoute = false;
    _stopScanLoop();
    if (ZKTecoUSB.isAndroidPlatform) {
      if (_device.onTemplateExtracted == _templateHandler) {
        _device.onTemplateExtracted = null;
      }
    }
  }
  
  /// Restart scanning with user feedback
  void _restartScanningWithFeedback() {
    try {
      // Force stop any existing scan first
      _stopScanLoop();
      _controller.setScanning(false);
      
      // Small delay then force start
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && _device.isConnected) {
          _startScanLoop();
          
          // Show brief success feedback
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Scanner ready - place finger on scanner'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      });
    } catch (e) {
      debugPrint('[PAGE_FOCUS] Failed to restart scanning: $e');
      
      // Show error feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scanner error: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Reload employee database for the currently selected site
  Future<void> _reloadEmployeesForCurrentSite() async {
    final siteId = _selectedSiteId;
    if (siteId == null || siteId.isEmpty) return;
    
    debugPrint('[RELOAD_EMPLOYEES] Reloading employees for site: $siteId');
    try {
      await _loadFromLocalDb(siteId);
      debugPrint('[RELOAD_EMPLOYEES] Successfully reloaded ${_employeeDb.length} employees');
    } catch (e) {
      debugPrint('[RELOAD_EMPLOYEES] Error reloading employees: $e');
    }
  }

  /// Auto-connect to device if site is already selected
  Future<void> _autoConnectIfSiteSelected() async {
    if (_device.isConnected || _controller.isSearching.value) return;
    
    // Only auto-connect if we have a site selected
    if (_selectedSiteId == null || _selectedSiteId!.isEmpty) return;
    
    debugPrint('[AUTO_CONNECT] Attempting auto-connect for site: $_selectedSiteId');
    
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
      final siteName = _siteNameById(_selectedSiteId);
      final siteText = siteName != null ? ' | Site: $siteName' : '';
      
      _controller.setConnected(
        true,
        status: 'Connected: ${serial ?? 'Unknown'}$siteText',
      );

      debugPrint('[AUTO_CONNECT] Success - loading templates and starting sync');
      
      // Load templates and start background sync
      await _loadAndRegisterTemplates();
      await _fetchAndCacheSiteTimeLogs();
      _startLiveDbSync();
      
      // Start scanning if in scanner mode
      if (_uiMode == _HomeUiMode.scanner && mounted) {
        _startScanLoop();
      }
    } catch (e) {
      debugPrint('[AUTO_CONNECT] Error: $e');
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
    final progress = ValueNotifier<double>(0.0);
    final syncFuture = _connectAndSync(progress: progress);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoadingPage(
            loadFuture: syncFuture,
            onComplete: () {
              // Already on home page, just start scanning
              _startScanLoop();
            },
            progressListenable: progress,
          ),
          fullscreenDialog: true,
        ),
      );
    } finally {
      progress.dispose();
    }
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
    routeObserver.unsubscribe(this);
    _routeSubscribed = false;
    _scanTimer?.cancel();
    _portalAutoReturnTimer?.cancel();
    _stopLiveDbSync();
    if (ZKTecoUSB.isAndroidPlatform) {
      if (_device.onTemplateExtracted == _templateHandler) {
        _device.onTemplateExtracted = null;
      }
    }
    _device.dispose();
    // Note: LegacyHomePageController doesn't need manual cleanup
    super.dispose();
  }

  void _setLoadingProgress(ValueNotifier<double>? progress, double value) {
    if (progress == null) return;
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (clamped > progress.value) {
      progress.value = clamped;
    }
  }

  /// Pure async connect + sync — NO dialogs, NO Navigator calls.
  /// Safe to run as the loadFuture inside LoadingPage.
  Future<void> _connectAndSync({ValueNotifier<double>? progress}) async {
    _setLoadingProgress(progress, 0.05);
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
      _setLoadingProgress(progress, 0.2);

      final count = await _device.getDeviceCountAsync();
      if (count == 0) {
        _controller.stopSearching(
          'No device found. Plug in the scanner and retry.',
        );
        await _device.terminateSdk();
        return;
      }
      _setLoadingProgress(progress, 0.3);

      _controller.setStatus('Found $count device(s). Connecting...');

      final opened = await _device.openDevice(0);
      if (!opened) {
        _controller.stopSearching('Failed to open device.');
        await _device.terminateSdk();
        return;
      }
      _setLoadingProgress(progress, 0.4);

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
      _setLoadingProgress(progress, 0.45);

      // Sync API -> SQLite, then always load/register from SQLite.
      await _loadAndRegisterTemplates(progress: progress);
      _setLoadingProgress(progress, 0.85);
      await _fetchAndCacheSiteTimeLogs();
      _setLoadingProgress(progress, 0.9);
      await _syncPendingHrisQueue();
      _setLoadingProgress(progress, 0.96);
      _startLiveDbSync();
      _setLoadingProgress(progress, 0.98);
      _setLoadingProgress(progress, 1.0);
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
    final progress = ValueNotifier<double>(0.0);
    final syncFuture = _connectAndSync(progress: progress);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoadingPage(
            loadFuture: syncFuture,
            progressListenable: progress,
          ),
          fullscreenDialog: true,
        ),
      );
    } finally {
      progress.dispose();
    }
    if (mounted) _startScanLoop();
  }

  // ==================== Template Loading & Scan Loop ====================

  Future<void> _loadAndRegisterTemplates({ValueNotifier<double>? progress}) async {
    if (!mounted) return;
    final siteId = _selectedSiteId;
    if (siteId == null) {
      // No site selected, do not proceed.
      return;
    }

    // Removed status text about syncing fingerprint data to local database.
    await _syncEmployeesFromApiToLocalDb(siteId);
    _setLoadingProgress(progress, 0.7);
    await _loadFromLocalDb(siteId);
    _setLoadingProgress(progress, 0.82);
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

      // Merge API employees with local enrollments (preserve locally enrolled employees)
      await LocalDb.mergeEmployeesFromApi(
        siteId: siteId,
        apiEmployees: templatesToSave,
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
      debugPrint('[LOAD_EMPLOYEES] Loading employees for site: $siteId');
      final rows = await LocalDb.getEmployeesBySite(siteId);
      debugPrint('[LOAD_EMPLOYEES] Found ${rows.length} employee rows in DB');
      
      _employeeDb.clear();
      _employeeDbByFid.clear();
      int registered = 0;

      for (final row in rows) {
        final fid = row['fid'] as int;
        final empId = row['employee_id'] as String;
        final empName = row['employee_name'] as String?;
        final templateBytes = row['finger_template'] as Uint8List;

        debugPrint('[LOAD_EMPLOYEES] Processing employee: fid=$fid, id=$empId, name=$empName');
        await _device.registerFingerprint(fid, templateBytes);
        final entry = _EmployeeEntry(id: empId, name: empName ?? empId);
        _employeeDb[fid] = entry;
        _employeeDbByFid[fid.toString()] = entry;
        registered++;
      }

      debugPrint('[LOAD_EMPLOYEES] Successfully registered $registered employees');
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
        await LocalDb.replaceTimelogCache(siteId: siteId, rows: rows);
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('_fetchAndCacheSiteTimeLogs: $e');
    }
  }

  void _startScanLoop() {
    if (!_isActiveRoute || _uiMode != _HomeUiMode.scanner) return;
    if (_controller.isScanning.value || !_device.isConnected) return;
    _controller.setScanning(true);

    if (ZKTecoUSB.isAndroidPlatform) {
      // Android is event-driven via onTemplateExtracted callback.
      // Always point the callback at HomePage and let _handleAndroidTemplate decide whether to act.
      _templateHandler ??= (template, size) {
        _handleAndroidTemplate(template, size);
      };
      _device.onTemplateExtracted = _templateHandler;
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

  void _scheduleScannerResume() {
    _portalAutoReturnTimer?.cancel();
    _portalAutoReturnTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted || !_isActiveRoute) return;
      setState(() {
        _uiMode = _HomeUiMode.scanner;
        _matchedEmployee = null;
        _matchedAt = null;
        _matchedAttendanceType = null;
      });
      if (_device.isConnected) {
        _startScanLoop();
      } else {
        _autoConnectIfSiteSelected();
      }
    });
  }

  void _handleAndroidTemplate(Uint8List template, int size) {
    if (!mounted) return;
    if (!ZKTecoUSB.isAndroidPlatform) return;

    // Only react when HomePage is the visible/active route and in scanner mode.
    if (!_isActiveRoute || _uiMode != _HomeUiMode.scanner) return;
    if (!_device.isConnected) return;

    // Debounce and prevent re-entrancy.
    final now = DateTime.now();
    final lastAt = _lastTemplateHandledAt;
    if (lastAt != null && now.difference(lastAt).inMilliseconds < 800) return;
    if (_isProcessingTemplate) return;

    _lastTemplateHandledAt = now;
    _isProcessingTemplate = true;

    debugPrint('[HOME_SCAN] onTemplateExtracted (android) size=$size -> handling');

    // Process asynchronously.
    Future(() async {
      try {
        await _onTemplateReady(template);
      } finally {
        if (mounted && _device.isConnected && _isActiveRoute && _uiMode == _HomeUiMode.scanner) {
          // Re-arm scanning state so future templates are accepted.
          _controller.setScanning(true);
        }
        _isProcessingTemplate = false;
      }
    });
  }

  Future<void> _onTemplateReady(Uint8List template) async {
    if (!mounted || !_device.isConnected) return;
    _controller.setScanning(false);

    debugPrint('[HOME_SCAN] Template ready, identifying...');
    debugPrint('[HOME_SCAN] Current employee DB size: ${_employeeDb.length}');
    debugPrint('[HOME_SCAN] Current employeeDbByFid size: ${_employeeDbByFid.length}');

    String? fid;
    if (ZKTecoUSB.isAndroidPlatform) {
      final res = await _device.identifyFingerprint();
      if (res.found) fid = res.fid;
      debugPrint('[HOME_SCAN] Android identify result: found=${res.found}, fid=${res.fid}');
    } else {
      final res = _device.identifyTemplate(template);
      if (res.fingerId != null) fid = res.fingerId.toString();
      debugPrint('[HOME_SCAN] Desktop identify result: fingerId=${res.fingerId}');
    }

    final fingerId = _parseFingerId(fid);
    debugPrint('[HOME_SCAN] Looking for employee with fid="$fid", fingerId=$fingerId');
    
    _EmployeeEntry? employee =
        (fid != null ? _employeeDbByFid[fid.trim()] : null) ??
        (fingerId != null ? _employeeDb[fingerId] : null) ??
        (fingerId != null ? _employeeDbByFid[fingerId.toString()] : null);

    debugPrint('[HOME_SCAN] Employee lookup result: ${employee?.name ?? 'NOT FOUND'}');

    // If no employee found and database is empty, try reloading employees
    if (employee == null && _employeeDb.isEmpty && _selectedSiteId != null) {
      debugPrint('[HOME_SCAN] Employee DB is empty, attempting to reload...');
      await _reloadEmployeesForCurrentSite();
      
      // Try lookup again after reload
      employee =
          (fid != null ? _employeeDbByFid[fid.trim()] : null) ??
          (fingerId != null ? _employeeDb[fingerId] : null) ??
          (fingerId != null ? _employeeDbByFid[fingerId.toString()] : null);
      
      debugPrint('[HOME_SCAN] After reload, employee lookup result: ${employee?.name ?? 'STILL NOT FOUND'}');
    }

    if (employee == null && ZKTecoUSB.isAndroidPlatform) {
      debugPrint('[HOME_SCAN] Trying verification fallback...');
      employee = await _resolveEmployeeByVerificationFallback();
      debugPrint('[HOME_SCAN] Verification fallback result: ${employee?.name ?? 'NOT FOUND'}');
    }

    if (employee != null) {
      debugPrint('[HOME_SCAN] Found employee: ${employee.name} (ID: ${employee.id})');
      final attendanceType = await _recordAttendance(employee.id);
      if (!mounted) return;
      
      // Navigate to dashboard for successful scans - show success loading first
      if (attendanceType == 'TIME IN' || attendanceType == 'TIME OUT' || attendanceType == 'QUEUED OFFLINE') {
        final String resultTypeStr = attendanceType == 'TIME OUT' 
            ? 'timeOutSuccess' 
            : 'timeInSuccess';
        final String displayAttendanceType = attendanceType == 'QUEUED OFFLINE' ? 'Time In (Queued)' : (attendanceType ?? 'Time In');
        final DateTime now = DateTime.now();
        
        // Show success loading page with employee info
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuccessLoadingPage(
              employeeName: employee!.name,
              attendanceType: displayAttendanceType,
              timestamp: now,
              onComplete: () {
                // Pop the SuccessLoadingPage first
                Navigator.of(context).pop();
                // Use push instead of pushReplacement to keep home page in stack
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => DashboardPage(
                          employeeId: employee!.id,
                          employeeName: employee!.name,
                          attendanceType: displayAttendanceType,
                          matchedAt: now,
                          siteId: _selectedSiteId,
                          resultType: resultTypeStr,
                          timeIn: attendanceType == 'TIME OUT' ? null : _formatTimeOnly(now),
                          timeOut: attendanceType == 'TIME OUT' ? _formatTimeOnly(now) : null,
                        ),
                      ),
                    )
                    .then((_) {
                      if (!mounted) return;
                      if (_device.isConnected && _uiMode == _HomeUiMode.scanner) {
                        debugPrint('[HOME_SCAN] Dashboard closed, resuming scan loop');
                        _restartScanningWithFeedback();
                      }
                    });
              },
            ),
            fullscreenDialog: true,
          ),
        );
        
        _controller.setStatus(
          '${employee!.name} — ${attendanceType ?? 'RECORDED'}',
        );
        return;
      }
      
      // Show modal for error cases (already timed, unsuccessful) - navigate to dashboard with error result
      String resultTypeStr;
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
      
      // Go straight to Dashboard (no LoadingPage for already-timed/unsuccessful cases).
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => DashboardPage(
                employeeId: employee!.id,
                employeeName: employee!.name,
                attendanceType: attendanceType,
                matchedAt: DateTime.now(),
                siteId: _selectedSiteId,
                resultType: resultTypeStr,
              ),
            ),
          )
          .then((_) {
            if (!mounted) return;
            if (_device.isConnected && _uiMode == _HomeUiMode.scanner) {
              debugPrint('[HOME_SCAN] Dashboard closed, resuming scan loop');
              _restartScanningWithFeedback();
            }
          });
      
      _controller.setStatus(
        '${employee!.name} — ${attendanceType ?? 'FAILED'}',
      );
    } else {
      debugPrint('[HOME_SCAN] No employee found - showing fingerprint not recognized');
      // Fingerprint not recognized - show modal on home page
      _displayResult(
        _ScanResult(
          success: false,
          timestamp: DateTime.now(),
          type: _ScanResultType.fingerprintNotRecognized,
          errorMessage: fid != null
              ? 'Employee not on record'
              : 'Fingerprint not registered',
        ),
      );
      
      // Restart scan loop after a short delay
      Timer(const Duration(seconds: 2), () {
        if (mounted && _device.isConnected && _uiMode == _HomeUiMode.scanner) {
          debugPrint('[HOME_SCAN] Restarting scan loop after failed identification');
          _startScanLoop();
        }
      });
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

    _PendingTimeLog pending;
    try {
      pending = await _buildPendingTimeLog(
        employeeId: employeeId,
        siteId: siteId,
        now: DateTime.now(),
      );
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('ALREADY_OUT_TODAY')) {
        return 'ALREADY OUT - Come back tomorrow';
      } else if (errorMsg.contains('WAIT_5_MINUTES')) {
        return 'ALREADY IN';
      }
      return 'TIME IN UNSUCCESSFUL';
    }

    final requests = _buildAttendanceRequests(
      siteId: siteId,
      employeeId: employeeId,
      pending: pending,
    );

    // ALWAYS save to local cache first (before network requests)
    // This ensures the attendance is tracked even if network fails
    try {
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
      debugPrint(
        '[SAVE_TIMELOG] Saved timelog employeeId=$employeeId siteId=$siteId date=${pending.timeLogDate} code=${pending.code} '
        'inAM=${pending.timeInMorning} outAM=${pending.timeOutMorning} inPM=${pending.timeInAfternoon} outPM=${pending.timeOutAfternoon}',
      );
      
      // Add a small delay to ensure database write completes  
      await Future.delayed(Duration(milliseconds: 500));
      
    } catch (e) {
      debugPrint('[SAVE_TIMELOG] Error saving timelog: $e');
    }

    // First request is the critical write (timeIn/timeOut).
    final primary = requests.first;
    final primarySent = await _sendHrisRequest(
      endpoint: primary.$1,
      queryParams: primary.$2,
    ).timeout(const Duration(seconds: 5), onTimeout: () => false);

    if (primarySent) {
      debugPrint(
        '[ATTENDANCE] RECORDED employeeId=$employeeId siteId=$siteId code=${pending.code} '
        'inAM=${pending.timeInMorning} outAM=${pending.timeOutMorning} inPM=${pending.timeInAfternoon} outPM=${pending.timeOutAfternoon}',
      );
      // Secondary requests (logs/audit) are important but should not change
      // the UI result when the core attendance record is already saved.
      for (final request in requests.skip(1)) {
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
    ).timeout(const Duration(seconds: 5), onTimeout: () => null);
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
    
    debugPrint('[BUILD_PENDING] Employee=$employeeId Date=$date Time=$time');
    debugPrint('[BUILD_PENDING] Cached data: $cached');

    String? normalizeDate(String? raw) {
      if (raw == null) return null;
      final s = raw.trim();
      if (s.isEmpty) return null;

      // Fast-path: ISO/date prefix.
      if (s.length >= 10) {
        final prefix = s.substring(0, 10);
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(prefix)) {
          return prefix;
        }
      }

      final dt = DateTime.tryParse(s);
      if (dt != null) {
        return _formatDateOnly(dt);
      }

      return s;
    }

    // Check if cached data is from today (normalize because API/DB may include time).
    final cachedDateRaw = (cached?['timeLogDate'] ??
            cached?['timelog'] ??
            cached?['timelog_date'] ??
            cached?['date'])
        ?.toString();
    final cachedDate = normalizeDate(cachedDateRaw) ?? '';
    final isToday = cachedDate == date;
    debugPrint('[BUILD_PENDING] cachedDate=$cachedDate, today=$date, isToday=$isToday');

    // Only use cached data if it's from today
    final todayCache = isToday ? cached : null;

    final timeLogId =
        (todayCache?['timelogID'] ??
                todayCache?['timeLogID'] ??
                todayCache?['timelog_id'] ??
                '$employeeId-$date')
            .toString();
    final remarks = (todayCache?['remarks'] ?? todayCache?['remark'] ?? '').toString();
    final schedule = (todayCache?['schedule'] ?? todayCache?['schedCode'] ?? '')
        .toString();

    final existingInMorning = _isBlank(todayCache?['timeInMorning'])
        ? null
        : '${todayCache?['timeInMorning']}';
    final existingOutMorning = _isBlank(todayCache?['timeOutMorning'])
        ? null
        : '${todayCache?['timeOutMorning']}';
    final existingInAfternoon = _isBlank(todayCache?['timeInAfternoon'])
        ? null
        : '${todayCache?['timeInAfternoon']}';
    final existingOutAfternoon = _isBlank(todayCache?['timeOutAfternoon'])
        ? null
        : '${todayCache?['timeOutAfternoon']}';

    debugPrint('[BUILD_PENDING] existingInMorning=$existingInMorning, existingOutMorning=$existingOutMorning');
    debugPrint('[BUILD_PENDING] existingInAfternoon=$existingInAfternoon, existingOutAfternoon=$existingOutAfternoon');

    // If there is any TIME OUT recorded today (AM or PM), the day is complete.
    // The next TIME IN is only allowed on a new day.
    if (existingOutMorning != null || existingOutAfternoon != null) {
      debugPrint('[BUILD_PENDING] REJECT: Already timed out today');
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
      debugPrint('[BUILD_PENDING] Time since last time-in: $diffMinutes minutes');
      if (diffMinutes < 5) {
        debugPrint(
            '[BUILD_PENDING] REJECT: Must wait 5 min after time in (lastTimeIn=$lastTimeInForCooldown, now=$now)');
        throw Exception('WAIT_5_MINUTES');
      }
    }

    if (existingInMorning == null) {
      debugPrint('[BUILD_PENDING] DECISION: IN_AM (time in morning)');
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
      debugPrint('[BUILD_PENDING] DECISION: OUT_AM (time out morning)');
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
      debugPrint('[BUILD_PENDING] DECISION: IN_PM (time in afternoon)');
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

    debugPrint('[BUILD_PENDING] DECISION: OUT_PM (time out afternoon)');
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
    final uri = Uri.parse(
      '$_apiBaseUrl$endpoint',
    ).replace(queryParameters: queryParams);

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 12);
      try {
        final request = await client.getUrl(uri);
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
    
    _controller.setStatus(
      result.success ? 'RECORDED' : (result.errorMessage ?? 'Scan failed'),
    );
    
    // Show the new modal dialog
    _showAttendanceResultModal(result);
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
          // Auto-connect if device is not connected
          if (_device.isConnected) {
            _startScanLoop();
          } else {
            _autoConnectIfSiteSelected();
          }
        },
        onEnrollNowTap: null, // Removed enrollment functionality
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      drawer: custom.NavigationDrawer(
        selectedSiteId: _selectedSiteId,
        onNavigate: (route) {
          // Handle navigation if needed
        },
        onSync: _syncNow,
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
                  padding: EdgeInsets.symmetric(
                    horizontal: screenW * 0.015,
                    vertical: screenH * 0.015,
                  ),
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: screenH - (screenH * 0.03),
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Menu button to open drawer
                                Builder(
                                  builder: (context) => GestureDetector(
                                    onTap: () => Scaffold.of(context).openDrawer(),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0x223E7DDD),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFF3E7DDD),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.menu,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox.shrink(), // Removed ADD USER button
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
                        () {
                          final currentTime = _controller.now.value;
                          final hour = currentTime.hour > 12
                              ? currentTime.hour - 12
                              : (currentTime.hour == 0 ? 12 : currentTime.hour);
                          final minute = currentTime.minute.toString().padLeft(2, '0');
                          final period = currentTime.hour >= 12 ? 'PM' : 'AM';
                          final timeString =
                              "${hour.toString().padLeft(2, '0')}:$minute $period";

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
                          final dateString =
                              '${months[currentTime.month - 1]} ${currentTime.day}, ${currentTime.year}';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timeString,
                                style: TextStyle(
                                  fontFamily: 'CEORUSE',
                                  fontSize: cardW * 0.07,
                                  color: Colors.white,
                                  letterSpacing: 4,
                                  height: 1,
                                ),
                              ),
                              Text(
                                dateString,
                                style: TextStyle(
                                  fontFamily: 'CEORUSE',
                                  fontSize: cardW * 0.024,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  letterSpacing: 3,
                                  height: 1,
                                ),
                              ),
                            ],
                          );
                        },
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

  /// Show attendance result modal dialog
  void _showAttendanceResultModal(_ScanResult result) {
    if (!mounted) return;

    String title;
    String subtitle;
    String buttonText;
    Color buttonColor;
    Color iconBgColor;
    Color iconColor;
    IconData iconData;

    switch (result.type) {
      case _ScanResultType.timeInSuccess:
        title = 'TIME IN SUCCESSFUL';
        subtitle = 'Your time in has been recorded successfully. Wishing you a productive day!';
        buttonText = 'PROCEED';
        buttonColor = const Color(0xFF90EE90);
        iconBgColor = const Color(0xFF90EE90).withValues(alpha: 0.3);
        iconColor = const Color(0xFF2E7D32);
        iconData = Icons.check_circle;
        break;
      case _ScanResultType.timeOutSuccess:
        title = 'TIME OUT SUCCESSFUL';
        subtitle = 'Your time out has been recorded successfully. Wishing you a productive day!';
        buttonText = 'PROCEED';
        buttonColor = const Color(0xFF90EE90);
        iconBgColor = const Color(0xFF90EE90).withValues(alpha: 0.3);
        iconColor = const Color(0xFF2E7D32);
        iconData = Icons.check_circle;
        break;
      case _ScanResultType.alreadyTimedIn:
        title = 'ALREADY TIMED IN';
        subtitle = 'You have already timed in for today.';
        buttonText = 'Close';
        buttonColor = const Color(0xFFA3C9FF);
        iconBgColor = const Color(0xFFA3C9FF).withValues(alpha: 0.3);
        iconColor = const Color(0xFF1565C0);
        iconData = Icons.info;
        break;
      case _ScanResultType.alreadyTimedOut:
        title = 'ALREADY TIMED OUT';
        subtitle = 'You have already timed out for today.';
        buttonText = 'Close';
        buttonColor = const Color(0xFFA3C9FF);
        iconBgColor = const Color(0xFFA3C9FF).withValues(alpha: 0.3);
        iconColor = const Color(0xFF1565C0);
        iconData = Icons.info;
        break;
      case _ScanResultType.timeInUnsuccessful:
        title = 'TIME IN UNSUCCESSFUL';
        subtitle = "We couldn't process your request. Please try again.";
        buttonText = 'RETRY';
        buttonColor = const Color(0xFFFFA0A0);
        iconBgColor = const Color(0xFFFFA0A0).withValues(alpha: 0.3);
        iconColor = const Color(0xFFC62828);
        iconData = Icons.error;
        break;
      case _ScanResultType.timeOutUnsuccessful:
        title = 'TIME OUT UNSUCCESSFUL';
        subtitle = "We couldn't process your request. Please try again.";
        buttonText = 'RETRY';
        buttonColor = const Color(0xFFFFA0A0);
        iconBgColor = const Color(0xFFFFA0A0).withValues(alpha: 0.3);
        iconColor = const Color(0xFFC62828);
        iconData = Icons.error;
        break;
      case _ScanResultType.fingerprintNotRecognized:
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
                // Icon
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
                // Title
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                // Subtitle
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 20),
                // Button
                SizedBox(
                  width: 120,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      if (_device.isConnected) {
                        _startScanLoop();
                      } else {
                        _autoConnectIfSiteSelected();
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
    // DISABLED: Enrollment functionality removed
    return;
    
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
              final fid =
                  int.tryParse(
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
                final completer =
                    Completer<
                      ({
                        bool success,
                        String message,
                        String? fid,
                        Uint8List? template,
                      })
                    >();
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

                final started = await _device.startEnrollmentAndroid(
                  fid.toString(),
                );
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
                  horizontal: 28,
                  vertical: 26,
                ),
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
                      style: TextStyle(fontSize: 13, color: Color(0xFF7A9BBD)),
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
                          margin: const EdgeInsets.symmetric(horizontal: 6),
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
                        horizontal: 12,
                        vertical: 10,
                      ),
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
                                  Color(0xFFFFB74D),
                                ),
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
                                  color: Color(0xFF3E5A7A),
                                ),
                                foregroundColor: const Color(0xFF7A9BBD),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(isComplete ? 'DONE' : 'CANCEL'),
                            ),
                          ),
                        ),
                        if (!isComplete) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: ElevatedButton(
                                onPressed: isCapturing ? null : doCapture,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3E7DDD),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  captureCount == 0 ? 'START' : 'CAPTURE',
                                ),
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

  Future<void> _syncNow() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Syncing data...'),
        backgroundColor: Color(0xFF3FA9F5),
      ),
    );
    try {
      final siteId = _selectedSiteId;
      if (siteId != null && siteId.isNotEmpty) {
        await _syncEmployeesFromApiToLocalDb(siteId);
        await _loadFromLocalDb(siteId);
        await _fetchAndCacheSiteTimeLogs();
        await _syncPendingHrisQueue();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync completed successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
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