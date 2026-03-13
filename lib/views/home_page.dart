import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../controllers/home_page_controller.dart';
import '../zkfp/zkteco_usb.dart';

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
    this.employeeId,
    this.employeeName,
    this.attendanceType,
    this.errorMessage,
  });

  final bool success;
  final DateTime timestamp;
  final String? employeeId;
  final String? employeeName;
  final String? attendanceType; // 'TIME IN' or 'TIME OUT'
  final String? errorMessage;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _siteApiUrl =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/site/all';
  static const String _employeesPerSiteApiUrl =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/employee/perSite';
  static const String _scannerDbPath = r'C:\SQLiteDB\biometric_scanner.db';
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
  _ScanResult? _lastResult;
  bool _showResult = false;
  final Map<int, _EmployeeEntry> _employeeDb = {};

  @override
  void initState() {
    super.initState();
    _controller = Get.isRegistered<HomePageController>()
        ? Get.find<HomePageController>()
        : Get.put(HomePageController());
    unawaited(_ensureScannerDbReady());
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
          decoded['site'];
    }

    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return const [];
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
    await _ensureSitesLoaded();
    if (!mounted) return;

    if (_sites.isEmpty) {
      _controller.setStatus(
        'Cannot load site list. Please check API connection.',
      );
      return;
    }

    final selected = await _showSiteSelectionDialog(requiredSelection: true);
    if (!mounted || selected == null) return;

    setState(() {
      _selectedSiteId = selected;
    });
    _controller.setStatus(
      'Selected site: ${_siteNameById(selected) ?? selected}',
    );
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
    _device.dispose();
    if (Get.isRegistered<HomePageController>()) {
      Get.delete<HomePageController>();
    }
    super.dispose();
  }

  Future<void> _searchAndConnect() async {
    if (_controller.isSearching.value) return;

    if (_selectedSiteId == null) {
      await _requireSiteSelectionOnStartup();
      if (_selectedSiteId == null) {
        _controller.setStatus(
          'Please select a site before searching for device.',
        );
        return;
      }
    }

    _controller.startSearching('Searching for device...');

    try {
      if (ZKTecoUSB.isAndroidPlatform) {
        final env = await _device.getAndroidSdkEnvironment();
        final canUseSdk = env['canUseSdk'] == true;
        if (!canUseSdk) {
          final reason =
              env['reason']?.toString() ??
              'Android runtime is not compatible with the ZKTeco SDK.';
          _controller.stopSearching(reason);
          return;
        }
      }

      // Initialize SDK
      final sdkInit = await _device.initSdk();
      if (!sdkInit) {
        _controller.stopSearching(
          ZKTecoUSB.isAndroidPlatform
              ? 'SDK init failed. Use a physical ARM Android device with the scanner attached, or run the Windows build.'
              : 'SDK init failed',
        );
        return;
      }

      // Check device count
      final count = await _device.getDeviceCountAsync();
      if (count == 0) {
        _controller.stopSearching('No device found');
        await _device.terminateSdk();
        return;
      }

      _controller.setStatus('Found $count device(s). Connecting...');

      // Open device
      final opened = await _device.openDevice(0);
      if (opened) {
        final serial = await _device.getSerialNumber();
        await _ensureSitesLoaded();

        if (!mounted) return;

        String? siteId;
        if (serial != null && serial.isNotEmpty) {
          siteId = _deviceSiteMap[serial];
          if (siteId == null && _sites.isNotEmpty) {
            final pickedSiteId = await _showSiteSelectionDialog(
              requiredSelection: true,
              initialSiteId: _selectedSiteId,
            );
            if (pickedSiteId != null) {
              _deviceSiteMap[serial] = pickedSiteId;
              siteId = pickedSiteId;
              await _saveDeviceSiteMap();
            }
          }
        }

        siteId ??= _selectedSiteId;
        _selectedSiteId = siteId;

        final siteName = _siteNameById(siteId);
        final siteText = siteName != null ? ' | Site: $siteName' : '';

        _controller.stopSearching();
        _controller.setConnected(
          true,
          status: 'Connected: ${serial ?? "Unknown"}$siteText',
        );
        await _loadAndRegisterTemplates();
        _startScanLoop();
      } else {
        _controller.stopSearching('Failed to open device');
        await _device.terminateSdk();
      }
    } catch (e) {
      _controller.stopSearching('Error: $e');
    }
  }

  // ==================== Template Loading & Scan Loop ====================

  Future<void> _loadAndRegisterTemplates() async {
    if (!mounted) return;
    if (_selectedSiteId == null || _selectedSiteId!.isEmpty) {
      _controller.setStatus('Please select a site before scanning');
      return;
    }

    _controller.setStatus('Loading fingerprints...');
    try {
      final siteId = _selectedSiteId!;
      await _syncEmployeesPerSiteToLocalDb(siteId);

      final rows = await _readEmployeesFromLocalDb(siteId);
      _employeeDb.clear();

      await _device.clearDatabase();

      int autoId = 1;
      int registered = 0;

      for (final row in rows) {
        final empId = (row['employee_id'] ?? row['emp_id'] ?? row['id'])
            ?.toString();
        final empName =
            (row['employee_name'] ?? row['full_name'] ?? row['name'])
                ?.toString();
        final templateB64 =
            (row['finger_template'] ?? row['template'] ?? row['fingerprint'])
                ?.toString();
        final rawFid = row['finger_id'] ?? row['fid'] ?? row['fingerprint_id'];
        final fid = int.tryParse(rawFid?.toString() ?? '') ?? autoId;

        if (empId == null || templateB64 == null || templateB64.isEmpty) {
          autoId++;
          continue;
        }

        try {
          final templateBytes = base64Decode(templateB64);
          final ok = await _device.registerFingerprint(fid, templateBytes);
          if (ok) {
            _employeeDb[fid] = _EmployeeEntry(
              id: empId,
              name: empName ?? empId,
            );
            registered++;
          }
        } catch (_) {}
        autoId++;
      }

      if (!mounted) return;
      _controller.setStatus(
        registered > 0
            ? 'Ready — $registered fingerprint(s) loaded'
            : 'Ready — place finger on scanner',
      );
    } catch (e) {
      if (!mounted) return;
      _controller.setStatus('Ready — place finger on scanner');
      debugPrint('_loadAndRegisterTemplates: $e');
    }
  }

  Future<void> _syncEmployeesPerSiteToLocalDb(String siteId) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    Database? db;

    try {
      final request = await client.getUrl(
        Uri.parse('$_employeesPerSiteApiUrl?siteID=$siteId'),
      );
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

      db = await _openScannerDb();
      await db.execute(
        "DELETE FROM scanner_employee WHERE site_id = ? AND source = 'api'",
        [siteId],
      );

      final batch = db.batch();
      final now = DateTime.now().toIso8601String();
      for (final row in rows) {
        final templateB64 =
            (row['finger_template'] ?? row['template'] ?? row['fingerprint'])
                ?.toString();
        if (templateB64 == null || templateB64.isEmpty) {
          continue;
        }

        batch.insert('scanner_employee', {
          'site_id': siteId,
          'employee_id': (row['employee_id'] ?? row['emp_id'] ?? row['id'])
              ?.toString(),
          'employee_name':
              (row['employee_name'] ?? row['full_name'] ?? row['name'])
                  ?.toString(),
          'finger_id': (row['finger_id'] ?? row['fid'] ?? row['fingerprint_id'])
              ?.toString(),
          'finger_template': templateB64,
          'synced_at': now,
          'source': 'api',
        });
      }
      await batch.commit(noResult: true);
    } finally {
      client.close(force: true);
      await db?.close();
    }
  }

  Future<List<Map<String, Object?>>> _readEmployeesFromLocalDb(
    String siteId,
  ) async {
    Database? db;
    try {
      db = await _openScannerDb();
      return db.query(
        'scanner_employee',
        where: 'site_id = ?',
        whereArgs: [siteId],
        orderBy: 'id ASC',
      );
    } finally {
      await db?.close();
    }
  }

  Future<Database> _openScannerDb() async {
    final dbDir = Directory(r'C:\SQLiteDB');
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final dbFile = File(_scannerDbPath);
    if (!await dbFile.exists()) {
      await dbFile.create(recursive: true);
    }

    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(_scannerDbPath);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scanner_employee (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        site_id TEXT NOT NULL,
        employee_id TEXT,
        employee_name TEXT,
        finger_id TEXT,
        finger_template TEXT,
        synced_at TEXT,
        source TEXT DEFAULT 'api'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scanner_attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        site_id TEXT NOT NULL,
        employee_id TEXT,
        attendance_type TEXT,
        created_at TEXT
      )
    ''');

    try {
      await db.execute(
        "ALTER TABLE scanner_employee ADD COLUMN source TEXT DEFAULT 'api'",
      );
    } catch (_) {}

    return db;
  }

  Future<void> _ensureScannerDbReady() async {
    Database? db;
    try {
      db = await _openScannerDb();
      _controller.setStatus('Local DB ready: $_scannerDbPath');
    } catch (e) {
      _controller.setStatus('Local DB init failed: $e');
      debugPrint('_ensureScannerDbReady: $e');
    } finally {
      await db?.close();
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

    final fingerId = int.tryParse(fid ?? '');
    final employee = fingerId != null ? _employeeDb[fingerId] : null;

    if (employee != null) {
      await _recordAttendanceToScannerDb(employee.id);
      _displayResult(
        _ScanResult(
          success: true,
          timestamp: DateTime.now(),
          employeeId: employee.id,
          employeeName: employee.name,
          attendanceType: 'TIMED IN',
        ),
      );
    } else {
      final shouldAdd = await _showAddBiometricUserPrompt(
        hasFingerprintMatch: fid != null,
      );

      if (shouldAdd) {
        final added = await _addScannedUserToScannerDb(
          template: template,
          fid: fid,
        );
        if (added) {
          unawaited(_refreshTemplatesAfterAdd());
          _displayResult(
            _ScanResult(
              success: true,
              timestamp: DateTime.now(),
              employeeName: 'New Biometric User',
              attendanceType: 'ADDED',
            ),
          );
        } else {
          _displayResult(
            _ScanResult(
              success: false,
              timestamp: DateTime.now(),
              errorMessage: 'Failed to add to local biometric_scanner.db',
            ),
          );
        }
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
  }

  Future<void> _refreshTemplatesAfterAdd() async {
    try {
      await _loadAndRegisterTemplates().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('_refreshTemplatesAfterAdd: $e');
    }
  }

  Future<bool> _showAddBiometricUserPrompt({
    required bool hasFingerprintMatch,
  }) async {
    if (!mounted) return false;

    final action = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Unregistered Fingerprint'),
          content: Text(
            hasFingerprintMatch
                ? 'This fingerprint matched a device template but is not in the registered list.\n\nAdd it to biometric_user?'
                : 'This fingerprint is not in the registered list.\n\nAdd it to biometric_user?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    return action == true;
  }

  Future<bool> _addScannedUserToScannerDb({
    required Uint8List template,
    String? fid,
  }) async {
    if (_selectedSiteId == null || _selectedSiteId!.isEmpty) {
      _controller.setStatus('Cannot add user: no site selected');
      return false;
    }

    Database? db;
    try {
      db = await _openScannerDb();
      final siteId = _selectedSiteId!;
      final parsedFid = int.tryParse(fid ?? '');

      int nextFid;
      if (parsedFid != null && parsedFid > 0) {
        nextFid = parsedFid;
      } else {
        final maxRows = await db.rawQuery(
          '''
          SELECT MAX(CAST(finger_id AS INTEGER)) AS max_fid
          FROM scanner_employee
          WHERE site_id = ?
        ''',
          [siteId],
        );
        final rawMax = maxRows.isNotEmpty ? maxRows.first['max_fid'] : null;
        final maxFid = int.tryParse('${rawMax ?? ''}') ?? 0;
        nextFid = maxFid + 1;
      }

      final now = DateTime.now();
      final employeeId = 'LOCAL-${now.millisecondsSinceEpoch}';

      await db.insert('scanner_employee', {
        'site_id': siteId,
        'employee_id': employeeId,
        'employee_name': 'New Biometric User',
        'finger_id': nextFid.toString(),
        'finger_template': base64Encode(template),
        'synced_at': now.toIso8601String(),
        'source': 'local',
      });

      final registered = await _device.registerFingerprint(nextFid, template);
      if (registered) {
        _employeeDb[nextFid] = _EmployeeEntry(
          id: employeeId,
          name: 'New Biometric User',
        );
      }

      return true;
    } catch (e) {
      debugPrint('_addScannedUserToScannerDb: $e');
      _controller.setStatus('Add user failed: $e');
      return false;
    } finally {
      await db?.close();
    }
  }

  Future<bool> _recordAttendanceToScannerDb(String employeeId) async {
    if (_selectedSiteId == null || _selectedSiteId!.isEmpty) {
      _controller.setStatus('Cannot log attendance: no site selected');
      return false;
    }

    Database? db;
    try {
      db = await _openScannerDb();
      await db.insert('scanner_attendance', {
        'site_id': _selectedSiteId,
        'employee_id': employeeId,
        'attendance_type': 'TIMED IN',
        'created_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('_recordAttendanceToScannerDb: $e');
      _controller.setStatus('Attendance write failed: $e');
      return false;
    } finally {
      await db?.close();
    }
  }

  void _displayResult(_ScanResult result) {
    if (!mounted) return;
    setState(() {
      _lastResult = result;
      _showResult = true;
    });
    _controller.setStatus(
      result.success
          ? '${result.employeeName ?? 'Employee'} — ${result.attendanceType ?? 'RECORDED'}'
          : (result.errorMessage ?? 'Scan failed'),
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
    return Scaffold(
      body: Container(
        width: screenW,
        height: screenH,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/FinalBG.png'),
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
                Image.asset(
                  'assets/images/FastLogo.png',
                  height: screenH * 0.10,
                  fit: BoxFit.contain,
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

  Widget _buildMainCard(double screenW, double screenH) {
    final cardPadH = screenW * 0.03;
    final cardPadV = screenH * 0.04;

    return Stack(
      children: [
        // Particles spread across the card (no dark container)
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(screenW * 0.015),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                final size = (w * 0.090).clamp(64.0, 88.0);
                return Stack(
                  children: [
                    _positionedParticle(w, h, 0.08, 0.12, size * 1.25, 0),
                    _positionedParticle(w, h, 0.130, 0.105, size * 0.5, 0.3),
                    _positionedParticle(w, h, 0.15, 0.55, size * 0.9, 0.6),
                    _positionedParticle(w, h, 0.78, 0.5, size * 1.15, 0.2),
                    _positionedParticle(w, h, 0.45, 0.18, size * 0.55, 0.5),
                    _positionedParticle(w, h, 0.10, 0.72, size * 1.1, 0.8),
                    _positionedParticle(w, h, 0.25, 0.35, size * 0.45, 0.15),
                    _positionedParticle(w, h, 0.7, 0.28, size * 0.95, 0.45),
                    _positionedParticle(w, h, 0.35, 0.78, size * 0.6, 0.7),
                    _positionedParticle(w, h, 0.88, 0.65, size * 1.2, 0.25),
                    _positionedParticle(w, h, 0.05, 0.42, size * 0.5, 0.9),
                    _positionedParticle(w, h, 0.6, 0.42, size * 0.75, 0.35),
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

  Widget _positionedParticle(
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
      child: _RisingFadeParticle(
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
      width: cardW * 0.38,
      padding: EdgeInsets.symmetric(
        horizontal: cardW * 0.022,
        vertical: cardH * 0.028,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cardW * 0.01),
        border: Border.all(
          color: const Color(0xFF6B8CC4).withValues(alpha: 0.45),
          width: 1.2,
        ),
        image: const DecorationImage(
          image: AssetImage('assets/images/FinalBG.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
                if (isSuccess && result.employeeName != null) ...[
                  Text(
                    result.employeeName!.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'CEORUSE',
                      fontSize: cardW * 0.04,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: cardH * 0.015),
                ],
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
                        ? (result.attendanceType ?? 'RECORDED')
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
}

/// Rising + fading particle using square-particles-fx.svg.
class _RisingFadeParticle extends StatefulWidget {
  const _RisingFadeParticle({
    required this.size,
    required this.assetPath,
    this.phase = 0.0,
  });

  final double size;
  final String assetPath;
  final double phase;

  @override
  State<_RisingFadeParticle> createState() => _RisingFadeParticleState();
}

class _RisingFadeParticleState extends State<_RisingFadeParticle>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _opacity;
  Animation<double>? _translateY;
  Animation<double>? _scale;

  static const double _riseDistance = 56.0;
  static const Duration _duration = Duration(milliseconds: 2800);

  @override
  void initState() {
    super.initState();
    final controller = AnimationController(vsync: this, duration: _duration);
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeOut);
    _controller = controller;
    _opacity = Tween<double>(begin: 0.65, end: 0.0).animate(curve);
    _translateY = Tween<double>(begin: 0.0, end: -_riseDistance).animate(curve);
    _scale = Tween<double>(begin: 1.0, end: 0.75).animate(curve);
    controller.value = widget.phase;
    controller.repeat();
  }

  @override
  void didUpdateWidget(_RisingFadeParticle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) _controller?.value = widget.phase;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
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
