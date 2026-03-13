import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../zkfp/zkteco_usb.dart';

class _SiteOption {
  const _SiteOption({required this.id, required this.name});

  final String id;
  final String name;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _siteApiUrl =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/get/site/all';
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';
  static const String _deviceSitePrefsKey = 'device_site_map_v1';

  late Timer _clockTimer;
  DateTime _now = DateTime.now();
  bool _biometricConnected = false;
  bool _isSearching = false;
  bool _isLoadingSites = false;
  String _statusMessage = '';
  String? _selectedSiteId;
  List<_SiteOption> _sites = const [];
  final Map<String, String> _deviceSiteMap = {};
  
  final ZKTecoUSB _device = ZKTecoUSB();

  @override
  void initState() {
    super.initState();
    _loadDeviceSiteMap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requireSiteSelectionOnStartup();
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
    
    // Set up Android callbacks
    if (ZKTecoUSB.isAndroidPlatform) {
      _device.onDeviceAttached = () {
        setState(() => _statusMessage = 'Device attached!');
      };
      _device.onDeviceDetached = () {
        setState(() {
          _biometricConnected = false;
          _statusMessage = 'Device detached';
        });
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
          decoded['site'];
    }

    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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
      setState(() {
        _statusMessage = 'Connected, but site list failed to load: $e';
      });
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
      setState(() {
        _statusMessage = 'Cannot load site list. Please check API connection.';
      });
      return;
    }

    final selected = await _showSiteSelectionDialog(requiredSelection: true);
    if (!mounted || selected == null) return;

    setState(() {
      _selectedSiteId = selected;
      _statusMessage = 'Selected site: ${_siteNameById(selected) ?? selected}';
    });
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
        return WillPopScope(
          onWillPop: () async => !requiredSelection,
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
                          value: selectedId,
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
    _clockTimer.cancel();
    _device.dispose();
    super.dispose();
  }
  
  Future<void> _searchAndConnect() async {
    if (_isSearching) return;

    if (_selectedSiteId == null) {
      await _requireSiteSelectionOnStartup();
      if (_selectedSiteId == null) {
        setState(() {
          _statusMessage = 'Please select a site before searching for device.';
        });
        return;
      }
    }
    
    setState(() {
      _isSearching = true;
      _statusMessage = 'Searching for device...';
    });
    
    try {
      // Initialize SDK
      final sdkInit = await _device.initSdk();
      if (!sdkInit) {
        setState(() {
          _isSearching = false;
          _statusMessage = 'SDK init failed';
        });
        return;
      }
      
      // Check device count
      final count = await _device.getDeviceCountAsync();
      if (count == 0) {
        setState(() {
          _isSearching = false;
          _statusMessage = 'No device found';
        });
        await _device.terminateSdk();
        return;
      }
      
      setState(() => _statusMessage = 'Found $count device(s). Connecting...');
      
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

        setState(() {
          _biometricConnected = true;
          _isSearching = false;
          _statusMessage = 'Connected: ${serial ?? "Unknown"}$siteText';
        });
      } else {
        setState(() {
          _isSearching = false;
          _statusMessage = 'Failed to open device';
        });
        await _device.terminateSdk();
      }
    } catch (e) {
      setState(() {
        _isSearching = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  String get _timeString {
    final hour = _now.hour > 12
        ? _now.hour - 12
        : (_now.hour == 0 ? 12 : _now.hour);
    final minute = _now.minute.toString().padLeft(2, '0');
    final period = _now.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  String get _dateString {
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    return '${months[_now.month - 1]} ${_now.day}, ${_now.year}';
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
                // FAST Logo — top-left
                SvgPicture.asset(
                  'assets/logo/Fast Logo.svg',
                  height: screenH * 0.065,
                  colorFilter: const ColorFilter.mode(
                      Colors.white, BlendMode.srcIn),
                ),
                SizedBox(height: screenH * 0.018),
                // Main card
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildStatusButton(
                            label: _biometricConnected
                                ? 'BIOMETRIC CONNECTED'
                                : 'BIOMETRIC NOT CONNECTED',
                            textColor: _biometricConnected
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFE53935),
                            cardW: cardW,
                            cardH: cardH,
                          ),
                          SizedBox(height: cardH * 0.02),
                          GestureDetector(
                            onTap: _isSearching ? null : _searchAndConnect,
                            child: _buildStatusButton(
                              label: _isSearching ? 'SEARCHING...' : 'SEARCH MODE',
                              textColor: _isSearching 
                                  ? const Color(0xFFFFB74D)
                                  : Colors.white,
                              cardW: cardW,
                              cardH: cardH,
                              showLoading: _isSearching,
                            ),
                          ),
                          if (_statusMessage.isNotEmpty) ...[
                            SizedBox(height: cardH * 0.015),
                            SizedBox(
                              width: cardW * 0.32,
                              child: Text(
                                _statusMessage,
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

                    // ── Bottom-right: time & date ──
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Column(
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
}
