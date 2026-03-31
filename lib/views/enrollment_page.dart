import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import '../services/local_db.dart';
import '../zkfp/zkteco_usb.dart';
import 'success_loading_page.dart';

// Helper function to avoid awaiting futures
void unawaited(Future<void> future) {
  // Intentionally not awaiting future
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
    // Reset state but don't dispose device as it's shared with main app
    _leftCount = 0;
    _rightCount = 0;
    _isCapturing = false;
    _canSave = false;
    _leftTemplate = null;
    _rightTemplate = null;
    _leftFid = null;
    _rightFid = null;
    _statusText = 'NOT REGISTERED';
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
  String _statusText = 'NOT REGISTERED';
  String _displayEmployeeName = 'NOT REGISTERED';
  String _displayEmployeeId = 'N/A';
  String _todayIn = '-';
  String _todayOut = '-';
  Uint8List? _leftTemplate;
  Uint8List? _rightTemplate;
  int? _leftFid;
  int? _rightFid;
  final TextEditingController _employeeIdController = TextEditingController();
  final TextEditingController _employeeNameController = TextEditingController();
  File? _profileImageFile;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    // Don't auto-fill employee info - let user input their own
    _displayEmployeeName = 'NOT REGISTERED';
    _displayEmployeeId = 'N/A';
  }

  @override
  void dispose() {
    // Don't dispose device as it's shared with main app
    _employeeIdController.dispose();
    _employeeNameController.dispose();
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
    final employeeId = _employeeIdController.text.trim();
    if (siteId == null || employeeId.isEmpty) return;
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
    final employeeId = _employeeIdController.text.trim();
    final employeeName = _employeeNameController.text.trim();
    
    if (employeeId.isEmpty) {
      setState(() => _statusText = 'Please enter Employee ID first.');
      return;
    }
    
    if (employeeName.isEmpty) {
      setState(() => _statusText = 'Please enter Employee Name first.');
      return;
    }
    
    // Check if employee ID already exists
    if (widget.siteId != null) {
      try {
        final existingEmployees = await LocalDb.getEmployeesBySiteAndEmployeeId(
          siteId: widget.siteId!,
          employeeId: employeeId,
        );
        if (existingEmployees.isNotEmpty) {
          setState(() => _statusText = 'Employee ID already exists. Please use a different ID.');
          return;
        }
      } catch (e) {
        debugPrint('Error checking employee ID uniqueness: $e');
      }
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
    final employeeId = _employeeIdController.text.trim();
    final employeeName = _employeeNameController.text.trim();
    if (siteId == null || siteId.isEmpty || employeeId.isEmpty) {
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
        employeeName: employeeName.isNotEmpty ? employeeName : employeeId,
        template: _leftTemplate!,
        siteId: siteId,
      );
      await LocalDb.upsertEmployee(
        fid: _rightFid!,
        employeeId: employeeId,
        employeeName: employeeName.isNotEmpty ? employeeName : employeeId,
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
      
      // Show success loading screen
      if (posted && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuccessLoadingPage(
              message: 'Employee enrolled successfully!\n$employeeId - $employeeName',
              duration: const Duration(seconds: 2),
              onComplete: () {
                // Return to homepage after success screen
                if (mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _statusText = 'Save failed: $e';
      });
    }
  }

  Future<void> _pickProfilePicture() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        final bytes = await image.readAsBytes();
        setState(() {
          _profileImageFile = File(image.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(w * 0.02),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(w * 0.04),
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/Main BG.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.018,
                  vertical: h * 0.02,
                ),
                child: Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _EnrollmentProfileCard(
                            width: w, 
                            height: h,
                            profileImageFile: _profileImageFile,
                            onImagePicked: (File file) {
                              if (mounted) {
                                setState(() {
                                  _profileImageFile = file;
                                });
                              }
                            },
                          ),
                          SizedBox(width: w * 0.018),
                          Expanded(
                            child: Column(
                              children: [
                                _EnrollmentTimePanel(width: w, height: h),
                                SizedBox(height: h * 0.016),
                                _TodayLogCard(width: w, height: h),
                                SizedBox(height: h * 0.016),
                                _EmployeeInputFields(
                                  width: w, 
                                  height: h,
                                  employeeIdController: _employeeIdController,
                                  employeeNameController: _employeeNameController,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: h * 0.02),
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          _EnrollmentGuideCard(width: w, height: h),
                          SizedBox(width: w * 0.012),
                          _ScannerImageCard(width: w, height: h),
                          SizedBox(width: w * 0.012),
                          _FingerprintPreviewCard(width: w, height: h),
                          SizedBox(width: w * 0.012),
                          Expanded(
                            child: Column(
                              children: [
                                _StatusCard(
                                  width: w,
                                  height: h,
                                  title: 'LEFT THUMB STATUS',
                                  activeCount: _leftCount,
                                ),
                                SizedBox(height: h * 0.018),
                                _StatusCard(
                                  width: w,
                                  height: h,
                                  title: 'RIGHT THUMB STATUS',
                                  activeCount: _rightCount,
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _ActionButton(
                                        width: w,
                                        label: _isCapturing ? 'SCANNING...' : 'RESET',
                                        color: const Color(0xFF244D86),
                                        onTap: _isCapturing ? null : _startSixScans,
                                      ),
                                    ),
                                    SizedBox(width: w * 0.012),
                                    Expanded(
                                      child: _ActionButton(
                                        width: w,
                                        label: 'SAVE',
                                        color: const Color(0xFF44D980),
                                        onTap: (_isCapturing || !_canSave) ? null : _saveEnrollment,
                                      ),
                                    ),
                                  ],
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
            ),
          ),
        ),
      ),
    );
  }
}

class _EnrollmentProfileCard extends StatelessWidget {
  const _EnrollmentProfileCard({
    required this.width, 
    required this.height,
    required this.profileImageFile,
    required this.onImagePicked,
  });

  final double width;
  final double height;
  final File? profileImageFile;
  final Function(File) onImagePicked;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(width * 0.03);

    return SizedBox(
      width: width * 0.58,
      child: Row(
        children: [
          _EmployeePhotoCard(
            width: width, 
            radius: radius,
            profileImageFile: profileImageFile,
            onImagePicked: onImagePicked,
          ),
          SizedBox(width: width * 0.012),
          Expanded(
            child: Container(
              height: double.infinity,
              padding: EdgeInsets.all(width * 0.022),
              decoration: BoxDecoration(
                color: const Color(0xFF0A2240).withValues(alpha: 0.74),
                borderRadius: radius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Expanded(child: _TopPill(label: 'PORTAL')),
                      SizedBox(width: 12),
                      Expanded(child: _TopPill(label: 'LOGIN')),
                    ],
                  ),
                  SizedBox(height: height * 0.02),
                  Text(
                    'NOT REGISTERED',
                    style: TextStyle(
                      fontFamily: 'TRTCENZODEMO',
                      fontSize: width * 0.018,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: height * 0.014),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: width * 0.014,
                      vertical: height * 0.006,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A90FF),
                      borderRadius: BorderRadius.circular(width * 0.014),
                    ),
                    child: Text(
                      'N/A',
                      style: TextStyle(
                        fontFamily: 'CEORUSE',
                        fontSize: width * 0.009,
                        color: Colors.white,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  SizedBox(height: height * 0.016),
                  Text(
                    'NEW USER',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontStyle: FontStyle.italic,
                      fontSize: width * 0.012,
                      color: Colors.white.withValues(alpha: 0.85),
                      letterSpacing: 1.2,
                    ),
                  ),
                  SizedBox(height: height * 0.012),
                  Text(
                    'INFORMATION TECHNOLOGY | FAST\nDISTRIBUTION CORPORATION',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: width * 0.012,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1.8,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeePhotoCard extends StatefulWidget {
  const _EmployeePhotoCard({
    required this.width,
    required this.radius,
    required this.profileImageFile,
    required this.onImagePicked,
  });

  final double width;
  final BorderRadius radius;
  final File? profileImageFile;
  final Function(File) onImagePicked;

  @override
  State<_EmployeePhotoCard> createState() => _EmployeePhotoCardState();
}

class _EmployeePhotoCardState extends State<_EmployeePhotoCard> {
  Future<void> _pickProfilePicture() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        final bytes = await image.readAsBytes();
        setState(() {
          widget.onImagePicked(File(image.path));
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _pickProfilePicture,
      child: Container(
        width: widget.width * 0.2,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: widget.radius,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.profileImageFile != null)
              Image.file(
                widget.profileImageFile!,
                fit: BoxFit.cover,
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF8F8F8), Color(0xFFE7E0D8)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: widget.width * 0.04,
                      color: const Color(0xFF9E9E9E),
                    ),
                    SizedBox(height: widget.width * 0.01),
                    Text(
                      'Add Photo',
                      style: TextStyle(
                        fontSize: widget.width * 0.025,
                        color: const Color(0xFF9E9E9E),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnrollmentTimePanel extends StatelessWidget {
  const _EnrollmentTimePanel({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Align(
        alignment: Alignment.topRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '03:36 PM',
              style: TextStyle(
                fontFamily: 'CEORUSE',
                fontSize: width * 0.04,
                color: Colors.white,
                letterSpacing: 4,
                height: 1,
              ),
            ),
            SizedBox(height: height * 0.008),
            Text(
              'MARCH 10, 2026',
              style: TextStyle(
                fontFamily: 'CEORUSE',
                fontSize: width * 0.013,
                color: Colors.white,
                letterSpacing: 3,
              ),
            ),
            SizedBox(height: height * 0.002),
            Text(
              'TUESDAY',
              style: TextStyle(
                fontFamily: 'CEORUSE',
                fontSize: width * 0.013,
                color: Colors.white.withValues(alpha: 0.85),
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayLogCard extends StatelessWidget {
  const _TodayLogCard({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width * 0.38,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(width * 0.028),
            color: const Color(0xFF0B2742).withValues(alpha: 0.92),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: height * 0.014),
                child: Text(
                  'TODAYS LOG',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: width * 0.012,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ),
              Container(
                color: const Color(0xFF081A2E),
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.014,
                  vertical: height * 0.016,
                ),
                child: Row(
                  children: [
                    _TableHeaderCell(width: width, label: 'Date'),
                    _TableHeaderCell(width: width, label: 'IN'),
                    _TableHeaderCell(width: width, label: 'OUT'),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.014,
                  vertical: height * 0.018,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF5D7FAF).withValues(alpha: 0.75),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(width * 0.028),
                    bottomRight: Radius.circular(width * 0.028),
                  ),
                ),
                child: Row(
                  children: [
                    _TableValueCell(width: width, label: 'March 10, 2026'),
                    _TableValueCell(width: width, label: '8:00AM'),
                    _TableValueCell(width: width, label: '6:38PM'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnrollmentGuideCard extends StatelessWidget {
  const _EnrollmentGuideCard({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width * 0.20,
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.02,
        vertical: height * 0.03,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF233C66).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(width * 0.028),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enrollment Guide',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: width * 0.014,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          SizedBox(height: height * 0.028),
          Text(
            'Open Settings →\nBiometrics → Add\nFingerprint, then place\nyour finger on the sensor\nand lift it repeatedly until\nthe scan is complete. Your\nfingerprint will then be\nregistered.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: width * 0.011,
              color: Colors.white,
              height: 1.55,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerImageCard extends StatelessWidget {
  const _ScannerImageCard({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width * 0.20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.028),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C3E52), Color(0xFF111820)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: -width * 0.02,
            bottom: -height * 0.03,
            child: Icon(
              Icons.touch_app,
              size: width * 0.16,
              color: const Color(0x80F0C8A0),
            ),
          ),
          Center(
            child: Image.asset(
              'assets/images/Finger Print Icon.png',
              width: width * 0.11,
              height: width * 0.11,
              color: const Color(0xFF72E6F8),
            ),
          ),
          const _ScannerCorner(alignment: Alignment.topRight),
          const _ScannerCorner(alignment: Alignment.bottomRight),
        ],
      ),
    );
  }
}

class _FingerprintPreviewCard extends StatelessWidget {
  const _FingerprintPreviewCard({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width * 0.16,
      padding: EdgeInsets.all(width * 0.008),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.026),
      ),
      child: Center(
        child: Image.asset(
          'assets/images/Finger Print Icon.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _ScannerCorner extends StatelessWidget {
  const _ScannerCorner({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Transform.rotate(
          angle: alignment == Alignment.topRight ? 0.18 : -0.18,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              border: Border(
                top: const BorderSide(color: Colors.white70, width: 3),
                right: const BorderSide(color: Colors.white70, width: 3),
                bottom: alignment == Alignment.bottomRight
                    ? const BorderSide(color: Colors.white70, width: 3)
                    : BorderSide.none,
                left: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.width,
    required this.height,
    required this.title,
    required this.activeCount,
  });

  final double width;
  final double height;
  final String title;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.016,
        vertical: height * 0.027,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF123867).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(width * 0.028),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: width * 0.013,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          SizedBox(height: height * 0.018),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              final isActive = index < activeCount;
              return Container(
                width: width * 0.02,
                height: width * 0.02,
                margin: EdgeInsets.symmetric(horizontal: width * 0.006),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? const Color(0xFF39BF54)
                      : const Color(0xFFE9E5DB),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.width,
    required this.label,
    required this.color,
    this.onTap,
  });

  final double width;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: width * 0.030,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? color.withOpacity(0.45) : color,
          borderRadius: BorderRadius.circular(width * 0.03),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'CEORUSE',
            fontSize: width * 0.012,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

class _TopPill extends StatelessWidget {
  const _TopPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF173765).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'CEORUSE',
            fontSize: 10,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell({required this.width, required this.label});

  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: width * 0.012,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _EmployeeInputFields extends StatelessWidget {
  const _EmployeeInputFields({
    required this.width, 
    required this.height,
    required this.employeeIdController,
    required this.employeeNameController,
  });

  final double width;
  final double height;
  final TextEditingController employeeIdController;
  final TextEditingController employeeNameController;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(width * 0.02),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2742).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(width * 0.028),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EMPLOYEE INFORMATION',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: width * 0.012,
              color: Colors.white,
              letterSpacing: 3,
            ),
          ),
          SizedBox(height: height * 0.016),
          TextField(
            controller: employeeIdController,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: width * 0.011,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              labelText: 'Employee ID',
              labelStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: width * 0.010,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(width * 0.02),
                borderSide: const BorderSide(color: Color(0xFF3E5A7A)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(width * 0.02),
                borderSide: const BorderSide(color: Color(0xFF3E5A7A)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(width * 0.02),
                borderSide: const BorderSide(color: Color(0xFF3E7DDD)),
              ),
              filled: true,
              fillColor: const Color(0xFF162233),
            ),
          ),
          SizedBox(height: height * 0.012),
          TextField(
            controller: employeeNameController,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: width * 0.011,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              labelText: 'Employee Name',
              labelStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: width * 0.010,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(width * 0.02),
                borderSide: const BorderSide(color: Color(0xFF3E5A7A)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(width * 0.02),
                borderSide: const BorderSide(color: Color(0xFF3E5A7A)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(width * 0.02),
                borderSide: const BorderSide(color: Color(0xFF3E7DDD)),
              ),
              filled: true,
              fillColor: const Color(0xFF162233),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableValueCell extends StatelessWidget {
  const _TableValueCell({required this.width, required this.label});

  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: width * 0.008,
          color: Colors.white,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}
