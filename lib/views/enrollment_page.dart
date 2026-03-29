import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/local_db.dart';
import '../zkfp/zkteco_usb.dart';

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
  State<_DashboardRisingFadeParticle> createState() => _DashboardRisingFadeParticleState();
}

class _DashboardRisingFadeParticleState extends State<_DashboardRisingFadeParticle> with SingleTickerProviderStateMixin {
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
    if (controller == null || opacity == null || translateY == null || scale == null) {
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

class EnrollmentPage extends StatefulWidget {
  const EnrollmentPage({super.key, this.employeeId, this.employeeName, this.siteId});

  final String? employeeId;
  final String? employeeName;
  final String? siteId;

  @override
  State<EnrollmentPage> createState() => _EnrollmentPageState();
}

class _EnrollmentPageState extends State<EnrollmentPage> {
    // Ensures device is always ready when page is shown again
    @override
    void didChangeDependencies() {
      super.didChangeDependencies();
      _resetDeviceState();
    }

    // Optionally, also reset when coming back from another page
    @override
    void didUpdateWidget(covariant EnrollmentPage oldWidget) {
      super.didUpdateWidget(oldWidget);
      _resetDeviceState();
    }

    void _resetDeviceState() {
      // Dispose and re-initialize the device
      _device.dispose();
      _leftCount = 0;
      _rightCount = 0;
      _isCapturing = false;
      _canSave = false;
      _leftTemplate = null;
      _rightTemplate = null;
      _leftFid = null;
      _rightFid = null;
      _statusText = 'Press RESET to start capture (3x left, 3x right).';
      // Optionally, re-initialize device if needed
      // unawaited(_ensureDeviceReady());
      setState(() {});
    }
  static const String _apiBaseUrl =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/';
  static const String _thumbDetailsApiEndpoint = 'update/employee/thumbDetails';
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';

  final ZKTecoUSB _device = ZKTecoUSB();
  int _leftCount = 0;
  int _rightCount = 0;
  bool _isCapturing = false;
  bool _canSave = false;
  String _statusText = 'Press RESET to start capture (3x left, 3x right).';
  String _displayEmployeeName = 'UNKNOWN USER';
  String _displayEmployeeId = 'N/A';
  String _todayIn = '-';
  String _todayOut = '-';
  Uint8List? _leftTemplate;
  Uint8List? _rightTemplate;
  int? _leftFid;
  int? _rightFid;

  @override
  void initState() {
    super.initState();
    _displayEmployeeName = widget.employeeName?.trim().isNotEmpty == true
        ? widget.employeeName!.trim()
        : 'UNKNOWN USER';
    _displayEmployeeId = widget.employeeId?.trim().isNotEmpty == true
        ? widget.employeeId!.trim()
        : 'N/A';
    unawaited(_loadTodayLog());
  }

  @override
  void dispose() {
    _device.dispose();
    super.dispose();
  }

  String _pickFirst(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return '';
  }

  bool _isBlank(String value) {
    final text = value.trim();
    return text.isEmpty || text == '00:00:00' || text == '0' || text.toLowerCase() == 'null';
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

  Future<void> _loadTodayLog() async {
    final siteId = widget.siteId;
    final employeeId = widget.employeeId;
    if (siteId == null || employeeId == null || siteId.isEmpty || employeeId.isEmpty) return;
    final row = await LocalDb.getLatestTimelogForEmployee(siteId: siteId, employeeId: employeeId);
    if (!mounted || row == null) return;
    final inMorning = _pickFirst(row, ['timeInMorning', 'timeinmorning', 'time_in_morning']);
    final inAfternoon = _pickFirst(row, ['timeInAfternoon', 'timeinafternoon', 'time_in_afternoon']);
    final outMorning = _pickFirst(row, ['timeOutMorning', 'timeoutmorning', 'time_out_morning']);
    final outAfternoon = _pickFirst(row, ['timeOutAfternoon', 'timeoutafternoon', 'time_out_afternoon']);
    setState(() {
      _todayIn = !_isBlank(inMorning) ? inMorning : (!_isBlank(inAfternoon) ? inAfternoon : '-');
      _todayOut = !_isBlank(outAfternoon) ? outAfternoon : (!_isBlank(outMorning) ? outMorning : '-');
    });
  }

  Future<bool> _ensureDeviceReady() async {
    if (_device.isConnected) return true;
    final sdk = await _device.initSdk();
    if (!sdk) return false;
    final count = await _device.getDeviceCountAsync();
    if (count <= 0) return false;
    return _device.openDevice(0);
  }

  Future<Uint8List?> _captureThumb(String label, int fid) async {
    if (ZKTecoUSB.isAndroidPlatform) {
      final completer = Completer<({bool success, String message, Uint8List? template})>();
      final prevProgress = _device.onEnrollProgress;
      final prevResult = _device.onEnrollResult;
      _device.onEnrollProgress = (current, total, message) {
        if (!mounted) return;
        setState(() {
          if (label == 'LEFT') {
            _leftCount = current;
          } else {
            _rightCount = current;
          }
          _statusText = '$label: $message';
        });
      };
      _device.onEnrollResult = (success, message, resultFid, template) {
        if (!completer.isCompleted) {
          completer.complete((success: success, message: message, template: template));
        }
      };
      final started = await _device.startEnrollmentAndroid(fid.toString());
      if (!started) {
        _device.onEnrollProgress = prevProgress;
        _device.onEnrollResult = prevResult;
        return null;
      }
      try {
        final result = await completer.future.timeout(const Duration(seconds: 45));
        if (!result.success) return null;
        return result.template;
      } finally {
        _device.onEnrollProgress = prevProgress;
        _device.onEnrollResult = prevResult;
      }
    }

    _device.startEnrollment();
    var merged = await _device.captureForEnrollment();
    while (merged.mergedTemplate == null && merged.error == null) {
      if (!mounted) return null;
      setState(() {
        if (label == 'LEFT') {
          _leftCount = merged.count;
        } else {
          _rightCount = merged.count;
        }
      });
      merged = await _device.captureForEnrollment();
    }
    return merged.mergedTemplate;
  }

  Future<void> _startSixScans() async {
    final employeeId = widget.employeeId;
    if (employeeId == null || employeeId.isEmpty) {
      setState(() => _statusText = 'Employee is missing. Open from dashboard after scanning a user.');
      return;
    }
    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
      _canSave = false;
      _leftCount = 0;
      _rightCount = 0;
      _leftTemplate = null;
      _rightTemplate = null;
      _statusText = 'Preparing scanner...';
    });

    final ready = await _ensureDeviceReady();
    if (!ready) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _statusText = 'Scanner not ready. Connect biometric and retry.';
      });
      return;
    }

    final leftFid = _stableFingerprintId(employeeId, 'LEFT_THUMB');
    final rightFid = _stableFingerprintId(employeeId, 'RIGHT_THUMB');
    _leftFid = leftFid;
    _rightFid = rightFid;

    try {
      setState(() => _statusText = 'Scan LEFT thumb 3 times...');
      final left = await _captureThumb('LEFT', leftFid);
      if (left == null) {
        setState(() {
          _isCapturing = false;
          _statusText = 'Left thumb capture failed.';
        });
        return;
      }
      setState(() {
        _leftTemplate = left;
        _leftCount = 3;
      });

      setState(() => _statusText = 'Scan RIGHT thumb 3 times...');
      final right = await _captureThumb('RIGHT', rightFid);
      if (right == null) {
        setState(() {
          _isCapturing = false;
          _statusText = 'Right thumb capture failed.';
        });
        return;
      }
      setState(() {
        _rightTemplate = right;
        _rightCount = 3;
        _canSave = true;
        _isCapturing = false;
        _statusText = '6 scans complete. Press SAVE.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _statusText = 'Capture error: $e';
      });
    }
  }

  Future<bool> _postEnrollment({
    required String employeeId,
    required Uint8List leftTemplate,
    required Uint8List rightTemplate,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.putUrl(
          Uri.parse('$_apiBaseUrl$_thumbDetailsApiEndpoint')
              .replace(queryParameters: {'employeeID': employeeId}),
        );
        final basicToken = base64Encode(utf8.encode('$_apiUsername:$_apiPassword'));
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');
        final payload = jsonEncode({
          'employeeID': employeeId,
          'leftFingerThumb': base64Encode(leftTemplate),
          'rightFingerThumb': base64Encode(rightTemplate),
        });
        request.contentLength = utf8.encode(payload).length;
        request.write(payload);
        final response = await request.close();
        await response.transform(utf8.decoder).join();
        return response.statusCode >= 200 && response.statusCode < 300;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveEnrollment() async {
    if (!_canSave || _leftTemplate == null || _rightTemplate == null || _leftFid == null || _rightFid == null) {
      setState(() => _statusText = 'Complete 6 scans first.');
      return;
    }
    final siteId = widget.siteId;
    final employeeId = widget.employeeId;
    if (siteId == null || employeeId == null || siteId.isEmpty || employeeId.isEmpty) {
      setState(() => _statusText = 'Missing site/employee info.');
      return;
    }

    setState(() {
      _isCapturing = true;
      _statusText = 'Saving enrollment...';
    });
    try {
      final rows = await LocalDb.getEmployeesBySiteAndEmployeeId(siteId: siteId, employeeId: employeeId);
      for (final row in rows) {
        final oldFid = row['fid'] as int?;
        if (oldFid != null) {
          try {
            await _device.removeFingerprint(oldFid.toString());
          } catch (_) {}
        }
      }
      await LocalDb.deleteEmployeesBySiteAndEmployeeId(siteId: siteId, employeeId: employeeId);

      await _device.registerFingerprint(_leftFid!, _leftTemplate!);
      await _device.registerFingerprint(_rightFid!, _rightTemplate!);
      await LocalDb.upsertEmployee(
        fid: _leftFid!,
        employeeId: employeeId,
        employeeName: widget.employeeName ?? employeeId,
        template: _leftTemplate!,
        siteId: siteId,
      );
      await LocalDb.upsertEmployee(
        fid: _rightFid!,
        employeeId: employeeId,
        employeeName: widget.employeeName ?? employeeId,
        template: _rightTemplate!,
        siteId: siteId,
      );

      final posted = await _postEnrollment(
        employeeId: employeeId,
        leftTemplate: _leftTemplate!,
        rightTemplate: _rightTemplate!,
      );
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _statusText = posted
            ? 'Enrollment saved successfully.'
            : 'Saved locally, but HRIS update failed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _statusText = 'Save failed: $e';
      });
    }
  }

  // ─── Time Panel ───────────────────────────────────────────────────────────

  Widget _buildTimePanel(double w, double h) {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return Container(
      padding: EdgeInsets.all(
        h * 0.045,
      ),
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
                  fontSize: w * 0.035,
                  color: Colors.white,
                  letterSpacing: 4,
                  height: 1,
                ),
              ),
              SizedBox(height: h * 0.002),
              Text(
                _formatDate(now),
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: w * 0.015,
                  color: Colors.white.withOpacity(0.9),
                  letterSpacing: 3,
                  height: 1.1,
                ),
              ),
              SizedBox(height: h * 0.002),
              Text(
                _formatDay(now),
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: w * 0.013,
                  color: Colors.white.withOpacity(0.7),
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDay(DateTime date) {
    const days = [
      'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
      'FRIDAY', 'SATURDAY', 'SUNDAY',
    ];
    return days[date.weekday - 1];
  }

  // ─── Today Log Card ───────────────────────────────────────────────────────

  Widget _buildTodayLogCard(double w, double h) {
    final now = DateTime.now();
    final todayDate = _formatDate(now);
    final todayIn = _todayIn;
    final todayOut = _todayOut;
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: w * 0.90,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(w * 0.028),
            color: const Color(0xFF0B2742).withOpacity(0.70),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: h * 0.010),
                child: Text(
                  'TODAYS LOG',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: w * 0.010,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ),
              Container(
                color: const Color(0xFF081A2E).withOpacity(0.5),
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.014,
                  vertical: h * 0.010,
                ),
                child: Row(
                  children: [
                    _logCell(w, 'Date', bold: true),
                    _logCell(w, 'IN', bold: true),
                    _logCell(w, 'OUT', bold: true),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.014,
                  vertical: h * 0.014,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(w * 0.028),
                    bottomRight: Radius.circular(w * 0.028),
                  ),
                ),
                child: Row(
                  children: [
                    _logCell(w, todayDate, small: true),
                    _logCell(w, todayIn, small: true),
                    _logCell(w, todayOut, small: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logCell(double w, String text,
      {bool bold = false, bool small = false}) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: w * 0.010,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: Colors.white,
          letterSpacing: small ? 1.5 : 2,
        ),
      ),
    );
  }

  // ─── Top Pill ─────────────────────────────────────────────────────────────

  Widget _buildTopPill(double w, {required String label, bool active = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.01, vertical: w * 0.01),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.018),
        color: const Color(0xFF0E1F33).withOpacity(0.5),
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

  // ─── Profile Card ─────────────────────────────────────────────────────────

  Widget _buildProfileCard(double w, double h, BuildContext context) {
    final cardRadius = BorderRadius.circular(w * 0.023);
    final expandedPanelColor = const Color(0xFF092238).withOpacity(0.5);
    return ClipRRect(
      borderRadius: cardRadius,
      child: Container(
        width: w * 4,
        height: double.infinity,
        color: Colors.transparent,
        child: Row(
          children: [
            Container(
              width: w * 0.18,
              decoration: BoxDecoration(
                color: const Color(0xFF092238).withOpacity(0.7),
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
                        color: Colors.white.withOpacity(0.85),
                        width: 3,
                      ),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3FA9F5), Color(0xFF1B75BB)],
                      ),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  SizedBox(height: h * 0.012),
                  Text(
                    'PROFILE',
                    style: TextStyle(
                      fontFamily: 'CEORUSE',
                      fontSize: w * 0.012,
                      color: Colors.white.withOpacity(0.8),
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
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              }
                            },
                            child: _buildTopPill(w, label: 'PORTAL'),
                          ),
                        ),
                        SizedBox(width: w * 0.005),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              }
                            },
                            child: _buildTopPill(w, label: 'LOGIN', active: true),
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
                                    _displayEmployeeName.toUpperCase(),
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
                                      borderRadius:
                                          BorderRadius.circular(w * 0.013),
                                    ),
                                    child: Text(
                                      _displayEmployeeId,
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
                                    _statusText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontStyle: FontStyle.italic,
                                      fontSize: w * 0.015,
                                      color: Colors.white.withOpacity(0.8),
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                  SizedBox(height: h * 0.006),
                                  Text(
                                    'INFORMATION TECHNOLOGY | FAST\nDISTRIBUTION CORPORATION',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: w * 0.013,
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

  // ─── Bottom Row ───────────────────────────────────────────────────────────

  Widget _buildBottomRow(double w, double h) {
  return Expanded(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEnrollmentGuide(w, h),
        SizedBox(width: w * 0.010),

        // ← Wrap scanner + fingerprint in a dark container
        Container(
          padding: EdgeInsets.all(w * 0.010),
          decoration: BoxDecoration(
            color: const Color(0xFF0B2742).withOpacity(0.70),
            borderRadius: BorderRadius.circular(w * 0.022),
          ),
          child: Row(
            children: [
              _buildScannerCard(w, h),
              SizedBox(width: w * 0.010),
              _buildFingerprintPreview(w, h),
            ],
          ),
        ),

        SizedBox(width: w * 0.010),
        _buildStatusPanel(w, h),
      ],
    ),
  );
}

  Widget _buildEnrollmentGuide(double w, double h) {
    return Container(
      width: w * 0.20,
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.020,
        vertical: h * 0.020,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2742).withOpacity(0.70),
        borderRadius: BorderRadius.circular(w * 0.022),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enrollment Guide',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.012,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: h * 0.024),
          Text(
            'Open Settings →\nBiometrics → Add\nFingerprint, then place\nyour finger on the sensor\nand lift it repeatedly until\nthe scan is complete. Your\nfingerprint will then be\nregistered.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.011,
              color: Colors.white,
              height: 1.6,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerCard(double w, double h) {
  return SizedBox(
    width: w * 0.20,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(w * 0.022),
      child: Image.asset(
        'assets/images/finger-biometric-image.png', // 👈 replace with your image path
        fit: BoxFit.cover,
      ),
    ),
  );
}

  Widget _buildFingerprintPreview(double w, double h) {
    return Container(
      width: w * 0.16,
      padding: EdgeInsets.all(w * 0.008),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.022),
      ),
      child: Center(
        child: Image.asset(
          'assets/images/Finger Print Icon.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildStatusPanel(double w, double h) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left thumb status
          _buildThumbStatus(w, h, title: 'LEFT THUMB STATUS', activeCount: _leftCount),
          SizedBox(height: h * 0.018),
          // Right thumb status
          _buildThumbStatus(w, h, title: 'RIGHT THUMB STATUS', activeCount: _rightCount),
          const Spacer(),
          // Reset / Save buttons
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  w,
                  h,
                  label: _isCapturing ? 'SCANNING...' : 'RESET',
                  color: const Color(0xFF244D86),
                  onTap: _isCapturing ? null : _startSixScans,
                ),
              ),
              SizedBox(width: w * 0.012),
              Expanded(
                child: _buildActionButton(
                  w,
                  h,
                  label: 'SAVE',
                  color: const Color(0xFF44D980),
                  onTap: (_isCapturing || !_canSave) ? null : _saveEnrollment,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThumbStatus(double w, double h,
      {required String title, required int activeCount}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.016,
        vertical: h * 0.026,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2742).withOpacity(0.70),
        borderRadius: BorderRadius.circular(w * 0.022),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.013,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          SizedBox(height: h * 0.016),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final isActive = i < activeCount;
              return Container(
                width: w * 0.020,
                height: w * 0.020,
                margin: EdgeInsets.symmetric(horizontal: w * 0.006),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? const Color(0xFF39BF54)
                      : Colors.grey.withOpacity(0.55),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(double w, double h,
      {required String label, required Color color, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: w * 0.032,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? color.withOpacity(0.45) : color,
          borderRadius: BorderRadius.circular(w * 0.022),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'CEORUSE',
            fontSize: w * 0.013,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  // ─── Particle FX (copied from dashboard) ───
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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/Main BG.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(w * 0.020),
            child: Stack(
              children: [
                // Particle FX layer
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
                // Main content
                Positioned.fill(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildProfileCard(w, h, context),
                            ),
                            SizedBox(width: w * 0.01),
                            Expanded(
                              flex: 1,
                              child: Column(
                                children: [
                                  _buildTimePanel(w, h),
                                  SizedBox(height: h * 0.01),
                                  _buildTodayLogCard(w, h),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: h * 0.03),
                      _buildBottomRow(w, h),
                    ],
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