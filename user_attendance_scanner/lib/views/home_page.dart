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
import '../controllers/legacy_home_page_controller.dart';
import '../zkfp/zkteco_usb.dart';
import '../routes/route_observer.dart';
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

    // Step 1 - fetch site list quietly (status bar only, no loading screen)
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

    // Step 2 - let the user choose their work site
    final selected = await _showSiteSelectionDialog(requiredSelection: true);
    if (!mounted || selected == null) return;

    setState(() => _selectedSiteId = selected);
    await LocalDb.pruneToSite(selected);
    _controller.setStatus(
      'Selected site: ${_siteNameById(selected) ?? selected}',
    );

    // Step 3 - NOW show the loading screen while connecting + syncing data
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

  /// Pure async connect + sync - NO dialogs, NO Navigator calls.
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

      // Persist serial - site mapping (no dialog - site was already chosen)
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

      // Sync API - SQLite, then always load/register from SQLite.
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

  // Placeholder for remaining methods - will be added in next parts
  Future<void> _loadAndRegisterTemplates({ValueNotifier<double>? progress}) async {
    if (!mounted) return;
    final siteId = _selectedSiteId;
    if (siteId == null) {
      // No site selected, do not proceed.
      return;
    }

    await _syncEmployeesFromApiToLocalDb(siteId);
    _setLoadingProgress(progress, 0.7);
    await _loadFromLocalDb(siteId);
    _setLoadingProgress(progress, 0.82);
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
                    height: screenH * 0.08,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
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
                    // Time & date - bottom-right transparent area
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

                    // Fingerprint icon - top-right
                    Positioned(
                      top: cardH * 0.005,
                      right: cardW * 0.01,
                      bottom: cardH * 0.20,
                      width: cardW * 0.30,
                      child: Obx(
                        () => Image.asset(
                          _controller.biometricConnected.value
                              ? 'assets/images/HIRSLogo-scanner-connected.png'
                              : 'assets/images/HIRSLogo-scanner-unconnected.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),

                    // Title - left, vertically centered
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

                    // Bottom-left: status buttons
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
                          ],
                        ),
                      ),
                    ),

                    // Scan result overlay
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
          if (_isBlank(templateB64)) {
            skippedTemplates++;
            continue;
          }

          try {
            final fid = _stableFingerprintId(empId, entry.key);
            templatesToSave.add({
              'fid': fid,
              'employee_id': empId,
              'employee_name': resolvedName,
              'finger_template': base64Decode(templateB64!),
            });
            savedFingerprints++;
          } catch (_) {
            skippedTemplates++;
          }
        }
      }

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

  Future<void> _syncPendingHrisQueue() async {
    try {
      await LocalDb.syncPendingHrisQueue();
    } catch (e) {
      debugPrint('_syncPendingHrisQueue: $e');
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
    } catch (e) {
      if (!mounted) return;
      _controller.setStatus('Ready - place finger on scanner');
      debugPrint('_loadFromLocalDb error: $e');
    }
  }

  void _startScanLoop() {
    if (!_isActiveRoute || _uiMode != _HomeUiMode.scanner) return;
    if (_controller.isScanning.value || !_device.isConnected) return;
    _controller.setScanning(true);

    if (ZKTecoUSB.isAndroidPlatform) {
      _templateHandler ??= (template, size) {
        _handleAndroidTemplate(template, size);
      };
      _device.onTemplateExtracted = _templateHandler;
      return;
    }

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

  void _handleAndroidTemplate(Uint8List template, int size) {
    if (!mounted) return;
    if (!ZKTecoUSB.isAndroidPlatform) return;

    if (!_isActiveRoute || _uiMode != _HomeUiMode.scanner) return;
    if (!_device.isConnected) return;

    final now = DateTime.now();
    final lastAt = _lastTemplateHandledAt;
    if (lastAt != null && now.difference(lastAt).inMilliseconds < 800) return;
    if (_isProcessingTemplate) return;

    _lastTemplateHandledAt = now;
    _isProcessingTemplate = true;

    debugPrint('[HOME_SCAN] onTemplateExtracted (android) size=$size -> handling');

    Future(() async {
      try {
        await _onTemplateReady(template);
      } finally {
        if (mounted && _device.isConnected && _isActiveRoute && _uiMode == _HomeUiMode.scanner) {
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

    if (employee == null && _employeeDb.isEmpty && _selectedSiteId != null) {
      debugPrint('[HOME_SCAN] Employee DB is empty, attempting to reload...');
      await _reloadEmployeesForCurrentSite();
      
      employee =
          (fid != null ? _employeeDbByFid[fid.trim()] : null) ??
          (fingerId != null ? _employeeDb[fingerId] : null) ??
          (fingerId != null ? _employeeDbByFid[fingerId.toString()] : null);
      
      debugPrint('[HOME_SCAN] After reload, employee lookup result: ${employee?.name ?? 'STILL NOT FOUND'}');
    }

    if (employee != null) {
      debugPrint('[HOME_SCAN] Found employee: ${employee.name} (ID: ${employee.id})');
      final attendanceType = await _recordAttendance(employee.id);
      if (!mounted) return;
      
      if (attendanceType == 'TIME IN' || attendanceType == 'TIME OUT' || attendanceType == 'QUEUED OFFLINE') {
        final String resultTypeStr = attendanceType == 'TIME OUT' 
            ? 'timeOutSuccess' 
            : 'timeInSuccess';
        final String displayAttendanceType = attendanceType == 'QUEUED OFFLINE' ? 'Time In (Queued)' : (attendanceType ?? 'Time In');
        final DateTime now = DateTime.now();
        
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuccessLoadingPage(
              employeeName: employee!.name,
              attendanceType: displayAttendanceType,
              timestamp: now,
              onComplete: () {
                Navigator.of(context).pop();
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
          '${employee!.name} - ${attendanceType ?? 'RECORDED'}',
        );
        return;
      }
      
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
        '${employee!.name} - ${attendanceType ?? 'FAILED'}',
      );
    } else {
      debugPrint('[HOME_SCAN] No employee found - showing fingerprint not recognized');
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
      
      Timer(const Duration(seconds: 2), () {
        if (mounted && _device.isConnected && _uiMode == _HomeUiMode.scanner) {
          debugPrint('[HOME_SCAN] Restarting scan loop after failed identification');
          _startScanLoop();
        }
      });
    }
  }

  Future<void> _searchAndConnect() async {
    if (_controller.isSearching.value) return;
    if (!mounted) return;

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

  Future<String?> _recordAttendance(String employeeId) async {
    final siteId = _selectedSiteId;
    if (siteId == null) {
      return 'NO SITE';
    }

    try {
      final now = DateTime.now();
      final today = now.toIso8601String().split('T')[0];
      final timeStr = _formatTimeOnly(now);
      
      // Check if employee already has a timelog for today
      final existingTimelog = await LocalDb.getLatestTimelogForEmployee(
        siteId: siteId,
        employeeId: employeeId,
      );
      
      if (existingTimelog != null) {
        final timelogDate = existingTimelog['timeLogDate']?.toString() ?? 
                           existingTimelog['timelog_date']?.toString() ?? 
                           existingTimelog['timelog']?.toString();
        
        if (timelogDate != null && timelogDate.startsWith(today)) {
          // Employee already has a record for today
          final timeInMorning = existingTimelog['timeInMorning']?.toString();
          final timeOutMorning = existingTimelog['timeOutMorning']?.toString();
          final timeInAfternoon = existingTimelog['timeInAfternoon']?.toString();
          final timeOutAfternoon = existingTimelog['timeOutAfternoon']?.toString();
          
          // Check if already timed in today
          if (!_isBlank(timeInMorning) && _isBlank(timeOutMorning)) {
            debugPrint('[ATTENDANCE] Employee $employeeId already timed in today at $timeInMorning');
            return 'ALREADY IN';
          }
          
          // Check if already timed out today
          if (!_isBlank(timeOutMorning) || !_isBlank(timeOutAfternoon)) {
            debugPrint('[ATTENDANCE] Employee $employeeId already timed out today');
            return 'ALREADY OUT - Come back tomorrow';
          }
        }
      }
      
      // Save new time-in record
      await LocalDb.saveTimelog(
        siteId: siteId,
        employeeId: employeeId,
        timelogData: {
          'timelogID': 'tl_${now.millisecondsSinceEpoch}',
          'timelog': timeStr,
          'timeLogDate': today,
          'timeInMorning': timeStr,
          'remarks': 'SUCCESS',
          'schedule': 'AUTO',
          'code': 'SUCCESS',
        },
      );
      
      debugPrint('[ATTENDANCE] Employee $employeeId timed in successfully at $timeStr');
      return 'TIME IN';
    } catch (e) {
      debugPrint('_recordAttendance error: $e');
      return 'TIME IN UNSUCCESSFUL';
    }
  }

  void _displayResult(_ScanResult result) {
    if (!mounted) return;
    
    _controller.setStatus(
      result.success ? 'RECORDED' : (result.errorMessage ?? 'Scan failed'),
    );
    
    // Show modal dialog for fingerprint not recognized errors
    if (result.type == _ScanResultType.fingerprintNotRecognized) {
      _showFingerprintErrorModal();
    } else {
      // For other errors, show the overlay
      setState(() {
        _showResult = true;
        _lastResult = result;
      });
      
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showResult = false;
            _lastResult = null;
          });
        }
      });
    }
  }

  void _showFingerprintErrorModal() {
    if (!mounted) return;

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
                    color: const Color(0xFFFFE4D6).withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: Color(0xFFEF6C00),
                    size: 24,
                  ),
                ),
                const SizedBox(height: 16),
                // Title
                const Text(
                  'FINGERPRINT NOT RECOGNIZED',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                // Subtitle
                const Text(
                  "We couldn't recognize your fingerprint. Please try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
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
                      backgroundColor: const Color(0xFFFFE4D6),
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text(
                      'RETRY',
                      style: TextStyle(
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

  String _formatTimeOnly(DateTime dateTime) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    final s = dateTime.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
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

  bool _isBlank(dynamic value) {
    if (value == null) return true;
    final text = value.toString().trim();
    return text.isEmpty ||
        text == 'null' ||
        text == '00:00:00' ||
        text == '0' ||
        text.toUpperCase() == 'N/A';
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
