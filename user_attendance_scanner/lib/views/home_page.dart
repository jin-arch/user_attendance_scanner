import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../animations/rising_fade_particle.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/local_db.dart';
import '../services/site_repository_impl.dart';
import '../models/site_model.dart';
import '../controllers/legacy_home_page_controller.dart';
import '../utils/color_with_values_compat.dart';
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

enum _HomeUiMode { scanner, portal }

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<_HomePageController>(
      init: _HomePageController(),
      global: false,
      builder: (controller) {
        controller.ensureInitialized(context);
        return controller.build(context);
      },
    );
  }
}

class _HomePageController extends GetxController with RouteAware {
  static const String _deviceSitePrefsKey = 'device_site_map_v1';

  BuildContext? _context;
  bool _initialized = false;

  BuildContext get context => _context!;
  bool get mounted => !isClosed && _context != null;

  void setState(VoidCallback fn) {
    if (isClosed) return;
    fn();
    update();
  }

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
  bool _startupSiteSelectionCompleted = false;

  void ensureInitialized(BuildContext context) {
    _context = context;
    _bindRoute();
    if (_initialized) return;
    _initialized = true;
    _isActiveRoute = true;

    // Controller is provided by AppBinding (MVP-style DI)
    _controller = Get.find<LegacyHomePageController>();

    _loadDeviceSiteMap();

    // Load saved site preference first (synchronously load the site if available)
    _loadSavedSitePreferenceSync();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only run startup site selection once
      if (!_startupSiteSelectionCompleted) {
        _startupSiteSelectionCompleted = true;
        _requireSiteSelectionOnStartup();
      }
    });

    // Set up Android callbacks
    if (ZKTecoUSB.isAndroidPlatform) {
      _device.onDeviceAttached = () {
        _controller.setStatus('Device attached!');
        debugPrint('[DEVICE] Device attached - attempting auto-connect with site: $_selectedSiteId');
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

  /// Load previously saved site preference from database
  void _loadSavedSitePreferenceSync() {
    try {
      // This should complete quickly since we're just reading from local database
      _loadSavedSitePreference().then((_) {
        debugPrint('[INIT] Site preference loaded: $_selectedSiteId');
      }).catchError((e) {
        debugPrint('[INIT] Error loading site preference: $e');
      });
    } catch (e) {
      debugPrint('[INIT] Error in sync load: $e');
    }
  }

  /// Load previously saved site preference from database (async)
  Future<void> _loadSavedSitePreference() async {
    try {
      final siteRepository = SiteRepositoryImpl();
      final savedSite = await siteRepository.getSelectedSite();
      if (savedSite != null && savedSite.id.isNotEmpty) {
        debugPrint('[INIT] Loaded saved site: ${savedSite.id}');
        _selectedSiteId = savedSite.id;
      }
    } catch (e) {
      debugPrint('[INIT] Error loading saved site: $e');
    }
  }

  void _bindRoute() {
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
    final list = await _controller.fetchSiteRows();
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

    // If site was already loaded from saved preference, skip dialog
    if (_selectedSiteId != null && _selectedSiteId!.isNotEmpty) {
      debugPrint('[STARTUP] Site already loaded: $_selectedSiteId, skipping dialog');
      _controller.setStatus(
        'Using saved site: ${_siteNameById(_selectedSiteId)}',
      );

      // Proceed directly to sync
      final progress = ValueNotifier<double>(0.0);
      final syncFuture = _connectAndSync(progress: progress);
      try {
        await Get.to<void>(
          () => LoadingPage(
            loadFuture: syncFuture,
            onComplete: () {
              _startScanLoop();
            },
            progressListenable: progress,
          ),
          fullscreenDialog: true,
        );
      } finally {
        progress.dispose();
      }
      if (mounted) _startScanLoop();
      return;
    }

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

    // Step 2 - let the user choose their work site if no previous selection
    final selected = await _showSiteSelectionDialog(requiredSelection: true);
    if (!mounted || selected == null) return;

    setState(() => _selectedSiteId = selected);

    // Persist the newly selected site
    final siteRepository = SiteRepositoryImpl();
    await siteRepository.selectSite(
      Site(
        id: selected,
        name: _siteNameById(selected) ?? selected,
      ),
    );

    await LocalDb.pruneToSite(selected);
    _controller.setStatus(
      'Selected site: ${_siteNameById(selected) ?? selected}',
    );

    // Step 3 - NOW show the loading screen while connecting + syncing data
    if (!mounted) return;
    final progress = ValueNotifier<double>(0.0);
    final syncFuture = _connectAndSync(progress: progress);
    try {
      await Get.to<void>(
        () => LoadingPage(
          loadFuture: syncFuture,
          onComplete: () {
            _startScanLoop();
          },
          progressListenable: progress,
        ),
        fullscreenDialog: true,
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
                                      : () => Get.back<void>(),
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
                                  onPressed: () => Get.back<String>(result: selectedId),
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
  void onClose() {
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
    super.onClose();
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
                                padding: const EdgeInsets.all(20.0),
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
    final cardPadV = screenH * 0.12;

    return Stack(
      clipBehavior: Clip.none,
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
                    width: screenW * 0.2,
                    height: screenH * 0.09,
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
                  clipBehavior: Clip.none,
                  children: [
                    // Decorative rising particles (from animations/rising_fade_particle.dart)
                    Builder(
                      builder: (context) {
                        final ps = (cardW * 0.045).clamp(14.0, 52.0);
                        return Stack(
                          children: [
                            Positioned(
                              left: cardW * 0.08 - ps / 2,
                              top: cardH * 0.15 - ps / 2,
                              width: ps * 1.2,
                              height: ps * 1.2,
                              child: RisingFadeParticle(
                                size: ps * 1.2,
                                phase: 0.0,
                                assetPath: 'assets/icons/square-particles-fx.svg',
                              ),
                            ),
                            Positioned(
                              left: cardW * 0.28 - ps / 2,
                              top: cardH * 0.08 - ps / 2,
                              width: ps * 0.6,
                              height: ps * 0.6,
                              child: RisingFadeParticle(
                                size: ps * 0.6,
                                phase: 0.3,
                                assetPath: 'assets/icons/square-particles-fx.svg',
                              ),
                            ),
                            Positioned(
                              left: cardW * 0.72 - ps / 2,
                              top: cardH * 0.18 - ps / 2,
                              width: ps * 0.9,
                              height: ps * 0.9,
                              child: RisingFadeParticle(
                                size: ps * 0.9,
                                phase: 0.6,
                                assetPath: 'assets/icons/square-particles-fx.svg',
                              ),
                            ),
                            Positioned(
                              left: cardW * 0.5 - ps / 2,
                              top: cardH * 0.72 - ps / 2,
                              width: ps * 0.55,
                              height: ps * 0.55,
                              child: RisingFadeParticle(
                                size: ps * 0.55,
                                phase: 0.5,
                                assetPath: 'assets/icons/square-particles-fx.svg',
                              ),
                            ),
                            Positioned(
                              left: cardW * 0.88 - ps / 2,
                              top: cardH * 0.6 - ps / 2,
                              width: ps * 1.15,
                              height: ps * 1.15,
                              child: RisingFadeParticle(
                                size: ps * 1.15,
                                phase: 0.25,
                                assetPath: 'assets/icons/square-particles-fx.svg',
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    // Time & date - bottom-right transparent area
                    Positioned(
                      right: cardW * 0.01,
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
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

                    // (HIRS logo moved to render on top to avoid clipping)

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

                    // HIRS logo - placed last so it renders above other card content
                    Positioned(
                      top: -cardH * 0.02,
                      right: cardW * 0.01,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
    await _controller.syncEmployeesFromApiToLocalDb(siteId);
  }

  Future<void> _fetchAndCacheSiteTimeLogs() async {
    final siteId = _selectedSiteId;
    if (siteId == null) return;
    await _controller.fetchAndCacheSiteTimeLogs(siteId);
  }

  Future<void> _syncPendingHrisQueue() async {
    await _controller.syncPendingHrisQueue();
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
        final templateRaw = row['finger_template'];
        final templateBytes = templateRaw is Uint8List
            ? templateRaw
            : (templateRaw is List<int> ? Uint8List.fromList(templateRaw) : null);
        if (templateBytes == null) {
          continue;
        }

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
      final siteId = _selectedSiteId;
      if (siteId == null) return;
      final attendanceType = await _controller.recordAttendance(
        siteId: siteId,
        employeeId: employee.id,
      );
      if (!mounted) return;
      
      if (attendanceType == 'TIME IN' || attendanceType == 'TIME OUT' || attendanceType == 'QUEUED OFFLINE') {
        final String resultTypeStr = attendanceType == 'TIME OUT' 
            ? 'timeOutSuccess' 
            : 'timeInSuccess';
        final String displayAttendanceType = attendanceType == 'QUEUED OFFLINE' ? 'Time In (Queued)' : (attendanceType ?? 'Time In');
        final DateTime now = DateTime.now();
        
        await Get.to<void>(
          () => SuccessLoadingPage(
            employeeName: employee!.name,
            attendanceType: displayAttendanceType,
            timestamp: now,
            onComplete: () {
              Get.back<void>();
              Get.to<void>(
                () => DashboardPage(
                  employeeId: employee!.id,
                  employeeName: employee.name,
                  attendanceType: displayAttendanceType,
                  matchedAt: now,
                  siteId: _selectedSiteId,
                  resultType: resultTypeStr,
                  timeIn: attendanceType == 'TIME OUT'
                      ? null
                      : _controller.formatTimeOnly(now),
                  timeOut: attendanceType == 'TIME OUT'
                      ? _controller.formatTimeOnly(now)
                      : null,
                ),
              )?.then((_) {
                if (!mounted) return;
                if (_device.isConnected && _uiMode == _HomeUiMode.scanner) {
                  debugPrint('[HOME_SCAN] Dashboard closed, resuming scan loop');
                  _restartScanningWithFeedback();
                }
              });
            },
          ),
          fullscreenDialog: true,
        );
        
        _controller.setStatus(
          '${employee.name} - ${attendanceType ?? 'RECORDED'}',
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
      
      Get.to<void>(
            () => DashboardPage(
              employeeId: employee!.id,
              employeeName: employee.name,
              attendanceType: attendanceType,
              matchedAt: DateTime.now(),
              siteId: _selectedSiteId,
              resultType: resultTypeStr,
            ),
          )
          ?.then((_) {
            if (!mounted) return;
            if (_device.isConnected && _uiMode == _HomeUiMode.scanner) {
              debugPrint('[HOME_SCAN] Dashboard closed, resuming scan loop');
              _restartScanningWithFeedback();
            }
          });
      
      _controller.setStatus(
        '${employee.name} - ${attendanceType ?? 'FAILED'}',
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

    // If site already selected, use fast reconnect (load from local DB only)
    if (_selectedSiteId != null && _selectedSiteId!.isNotEmpty) {
      debugPrint('[SEARCH] Site already selected: $_selectedSiteId - fast reconnect');

      // Check if we already have employees cached
      final hasCachedEmployees = await _checkAndLoadCachedEmployees(_selectedSiteId!);

      if (hasCachedEmployees) {
        // Fast path: employees already in memory, just connect device
        debugPrint('[SEARCH] Employees cached - fast connect without loading screen');
        _controller.setStatus('Connecting to device...');

        try {
          await _quickDeviceConnect();
          if (mounted) {
            _controller.setStatus(
              'Connected: ${_siteNameById(_selectedSiteId)}',
            );
            _startScanLoop();
          }
        } catch (e) {
          debugPrint('[SEARCH] Quick connect failed: $e');
          _controller.setStatus('Connection failed: $e');
        }
        return;
      }

      // Slow path: need to sync employees, show loading screen
      _controller.setStatus('Syncing data...');
      if (!mounted) return;
      final progress = ValueNotifier<double>(0.0);
      final syncFuture = _connectAndSync(progress: progress);
      try {
        await Get.to<void>(
          () => LoadingPage(
            loadFuture: syncFuture,
            progressListenable: progress,
          ),
          fullscreenDialog: true,
        );
      } finally {
        progress.dispose();
      }
      if (mounted) _startScanLoop();
      return;
    }

    // Only show site dialog if no site is selected yet
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

    // Persist the newly selected site
    final siteRepository = SiteRepositoryImpl();
    await siteRepository.selectSite(
      Site(
        id: selected,
        name: _siteNameById(selected) ?? selected,
      ),
    );

    await LocalDb.pruneToSite(selected);
    _controller.setStatus(
      'Selected site: ${_siteNameById(selected) ?? selected}',
    );

    if (!mounted) return;
    final progress = ValueNotifier<double>(0.0);
    final syncFuture = _connectAndSync(progress: progress);
    try {
      await Get.to<void>(
        () => LoadingPage(
          loadFuture: syncFuture,
          progressListenable: progress,
        ),
        fullscreenDialog: true,
      );
    } finally {
      progress.dispose();
    }
    if (mounted) _startScanLoop();
  }

  /// Check if employees are cached for the site, load them in batch
  Future<bool> _checkAndLoadCachedEmployees(String siteId) async {
    try {
      if (_employeeDb.isNotEmpty) {
        debugPrint('[CACHE] Employees already in memory: ${_employeeDb.length}');
        return true;
      }

      // Load employees from local DB in batch (not one by one)
      final rows = await LocalDb.getEmployeesBySite(siteId);
      if (rows.isEmpty) {
        debugPrint('[CACHE] No cached employees for site: $siteId');
        return false;
      }

      debugPrint('[CACHE] Loading ${rows.length} employees from local DB');
      _employeeDb.clear();
      _employeeDbByFid.clear();

      // Batch load employees into memory
      for (final row in rows) {
        final fid = row['fid'] as int?;
        final empId = row['employee_id']?.toString() ?? '';
        final empName = row['employee_name']?.toString() ?? '';

        if (fid != null && empId.isNotEmpty) {
          final entry = _EmployeeEntry(id: empId, name: empName);
          _employeeDb[fid] = entry;
          _employeeDbByFid[fid.toString()] = entry;
        }
      }

      debugPrint('[CACHE] Loaded ${_employeeDb.length} employees from cache');
      return _employeeDb.isNotEmpty;
    } catch (e) {
      debugPrint('[CACHE] Error loading cached employees: $e');
      return false;
    }
  }

  /// Quick device connect without full sync (for cached employees)
  Future<void> _quickDeviceConnect() async {
    final siteId = _selectedSiteId;
    if (siteId == null || siteId.isEmpty) {
      throw Exception('No site selected');
    }

    try {
      if (ZKTecoUSB.isAndroidPlatform) {
        final env = await _device.getAndroidSdkEnvironment();
        if (env['canUseSdk'] != true) {
          throw Exception('SDK not compatible');
        }
      }

      final sdkInit = await _device.initSdk();
      if (!sdkInit) throw Exception('SDK init failed');

      final count = await _device.getDeviceCountAsync();
      if (count == 0) {
        await _device.terminateSdk();
        throw Exception('No device found');
      }

      final opened = await _device.openDevice(0);
      if (!opened) {
        await _device.terminateSdk();
        throw Exception('Failed to open device');
      }

      final serial = await _device.getSerialNumber();
      debugPrint('[QUICK_CONNECT] Connected: $serial');

      // Register fingerprints that are already in memory
      for (final entry in _employeeDb.entries) {
        final fid = entry.key;
        final row = (await LocalDb.getEmployeesBySite(siteId))
            .firstWhere((r) => r['fid'] == fid, orElse: () => {});
        if (row.isNotEmpty) {
          final template = row['finger_template'] as Uint8List?;
          if (template != null) {
            await _device.registerFingerprint(fid, template);
          }
        }
      }

      _controller.setConnected(true, status: 'Connected: ${serial ?? 'Unknown'}');
      debugPrint('[QUICK_CONNECT] Device ready for scanning');
    } catch (e) {
      debugPrint('[QUICK_CONNECT] Error: $e');
      rethrow;
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

    Get.dialog<void>(
      Dialog(
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
                      Get.back<void>();
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
        ),
      barrierDismissible: false,
    );
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

}

// Particle animation is provided by lib/animations/rising_fade_particle.dart
