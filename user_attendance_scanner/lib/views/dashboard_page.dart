// ignore_for_file: avoid_print
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../animations/dashboard_rising_fade_particle.dart';
import '../constants/date_time_formats.dart';
import '../controllers/dashboard_page_controller.dart';
import '../legacy_home_page_controller.dart';
import '../routes/route_observer.dart';
import '../widgets/top_left_curved_notch_clipper.dart';
import '../zkfp/zkteco_usb.dart';
import 'enrollment_page.dart';

class DashboardPage extends StatelessWidget {
  final String? resultType; // 'timeInSuccess', 'timeOutSuccess', 'alreadyTimedIn', etc.
  final String? timeIn; // Actual time in value to display
  final String? timeOut; // Actual time out value to display

  const DashboardPage({
    super.key,
    this.employeeId,
    this.employeeName,
    this.attendanceType,
    this.matchedAt,
    this.siteId,
    this.onPortalTap,
    this.onEnrollNowTap,
    this.resultType,
    this.timeIn,
    this.timeOut,
  });

  final String? employeeId;
  final String? employeeName;
  final String? attendanceType;
  final DateTime? matchedAt;
  final String? siteId;
  final VoidCallback? onPortalTap;
  final VoidCallback? onEnrollNowTap;

  @override
  Widget build(BuildContext context) {
    return _DashboardPageContent(
      employeeId: employeeId,
      employeeName: employeeName,
      attendanceType: attendanceType,
      matchedAt: matchedAt,
      siteId: siteId,
      onPortalTap: onPortalTap,
      onEnrollNowTap: onEnrollNowTap,
      resultType: resultType,
      timeIn: timeIn,
      timeOut: timeOut,
    );
  }
}

class _DashboardPageContent extends StatefulWidget {
  const _DashboardPageContent({
    this.employeeId,
    this.employeeName,
    this.attendanceType,
    this.matchedAt,
    this.siteId,
    this.onPortalTap,
    this.onEnrollNowTap,
    this.resultType,
    this.timeIn,
    this.timeOut,
  });

  final String? employeeId;
  final String? employeeName;
  final String? attendanceType;
  final DateTime? matchedAt;
  final String? siteId;
  final VoidCallback? onPortalTap;
  final VoidCallback? onEnrollNowTap;
  final String? resultType;
  final String? timeIn;
  final String? timeOut;

  @override
  State<_DashboardPageContent> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPageContent> with RouteAware {
  // Device and scanning
  final ZKTecoUSB _device = ZKTecoUSB();
  late final LegacyHomePageController _controller;
  late final DashboardPageController _dashboardController;
  bool _routeSubscribed = false;
  
  bool get _isPortalMode => widget.onPortalTap != null;

  // Dashboard is display + actions (Portal + Enroll Now). Fingerprint scanning/identify
  // happens on HomePage (scan) and EnrollmentPage (enroll/reset).
  bool get _enableScanning => true;

  String _initialsFromName(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed.toUpperCase() == 'UNKNOWN USER') return '';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  Future<void> _loadProfilePhoto() async {
    await _dashboardController.loadProfilePhoto(
      employeeId: widget.employeeId,
      siteId: widget.siteId,
    );
  }

  @override
  void initState() {
    super.initState();
    
    // Controller is provided by AppBinding (MVP-style DI)
    _controller = Get.find<LegacyHomePageController>();
    _dashboardController = Get.find<DashboardPageController>();
    
    _dashboardController.setRouteActive(true);
    _dashboardController.attachAndroidTemplateCallback(
      device: _device,
      onTemplateReady: _onTemplateReady,
      setScanning: _controller.setScanning,
      isMounted: () => mounted,
    );
    
    // Defer loading to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadRows();
        if (_enableScanning) {
          _dashboardController.loadEmployeeDatabase(
            siteId: widget.siteId,
            device: _device,
          );
        }
        _loadProfilePhoto();
      }
    });

    _dashboardController.startSession(onAfkTimeout: () {
      if (mounted) {
        _returnToScanner();
      }
    });
    
    // Start scanning if device is connected (deferred) - only when scanning is enabled
    if (_enableScanning && _device.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _dashboardController.stopScanLoop(setScanning: _controller.setScanning);
          _dashboardController.startScanLoop(
            device: _device,
            isScanning: () => _controller.isScanning.value,
            setScanning: _controller.setScanning,
            onTemplateReady: _onTemplateReady,
          );
        }
      });
    }
    
    // Show result modal if resultType is provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showResultModalIfNeeded();
    });
  }

  @override
  void didUpdateWidget(covariant _DashboardPageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.employeeId != widget.employeeId ||
        oldWidget.siteId != widget.siteId ||
        oldWidget.attendanceType != widget.attendanceType ||
        oldWidget.matchedAt != widget.matchedAt ||
        oldWidget.resultType != widget.resultType;
    if (changed) {
      // Use addPostFrameCallback to avoid calling setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadRows();
        _loadProfilePhoto();
        _showResultModalIfNeeded();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_routeSubscribed) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) {
        routeObserver.subscribe(this, route);
        _routeSubscribed = true;
        _dashboardController.setRouteActive(route.isCurrent);
      }
    }
    // Reload data when page becomes visible (deferred to avoid setState during build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadRows();
        _loadProfilePhoto();
        if (_enableScanning && _device.isConnected) {
          _dashboardController.startScanLoop(
            device: _device,
            isScanning: () => _controller.isScanning.value,
            setScanning: _controller.setScanning,
            onTemplateReady: _onTemplateReady,
          );
        }
      }
    });
  }

  @override
  void didPushNext() {
    _dashboardController.setRouteActive(false);
    _dashboardController.stopScanLoop(setScanning: _controller.setScanning);
    _dashboardController.clearAndroidTemplateCallback(device: _device);
  }

  @override
  void didPopNext() {
    _dashboardController.setRouteActive(true);
    _dashboardController.attachAndroidTemplateCallback(
      device: _device,
      onTemplateReady: _onTemplateReady,
      setScanning: _controller.setScanning,
      isMounted: () => mounted,
    );
    if (_enableScanning && _device.isConnected) {
      _dashboardController.stopScanLoop(setScanning: _controller.setScanning);
      _dashboardController.startScanLoop(
        device: _device,
        isScanning: () => _controller.isScanning.value,
        setScanning: _controller.setScanning,
        onTemplateReady: _onTemplateReady,
      );
    }
  }

  @override
  void dispose() {
    if (_enableScanning) {
      _dashboardController.stopScanLoop(setScanning: _controller.setScanning);
    }
    _dashboardController.clearAndroidTemplateCallback(device: _device);
    if (_routeSubscribed) {
      routeObserver.unsubscribe(this);
    }
    _dashboardController.stopSession();
    super.dispose();
  }

  // ==================== Fingerprint Scanning ====================
  
  Future<void> _onTemplateReady(Uint8List template) async {
    print('[DASHBOARD_SCAN] _onTemplateReady called');
    if (!mounted || !_device.isConnected) {
      print('[DASHBOARD_SCAN] Early return: mounted=$mounted, isConnected=${_device.isConnected}');
      return;
    }

    _controller.setScanning(false);
    final employee = await _dashboardController.resolveEmployeeFromTemplate(
      device: _device,
      template: template,
    );
    
    if (employee == null) {
      print('[DASHBOARD_SCAN] Employee not found - showing fingerprint not recognized');
      // Show fingerprint not recognized error
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _dashboardController.setRouteActive(false);
          _dashboardController.stopScanLoop(setScanning: _controller.setScanning);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardPage(
                siteId: widget.siteId,
                resultType: 'fingerprintNotRecognized',
              ),
            ),
          );
        }
      });
      return;
    }
    
    // Record attendance
    print('[DASHBOARD_SCAN] Recording attendance for employee: ${employee.id}');
    final attendanceType = await _recordAttendance(employee.id);
    print('[DASHBOARD_SCAN] Attendance result: $attendanceType');
    
    if (attendanceType == 'TIME IN' || attendanceType == 'TIME OUT') {
      final resultTypeStr = attendanceType == 'TIME OUT' 
          ? 'timeOutSuccess' 
          : 'timeInSuccess';
      final now = DateTime.now();
      
      // Navigate to dashboard with new attendance info
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _dashboardController.setRouteActive(false);
          _dashboardController.stopScanLoop(setScanning: _controller.setScanning);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardPage(
                employeeId: employee.id,
                employeeName: employee.name,
                attendanceType: attendanceType,
                matchedAt: now,
                siteId: widget.siteId,
                resultType: resultTypeStr,
                timeIn: attendanceType == 'TIME OUT' ? null : DateTimeFormats.timeOnly(now),
                timeOut: attendanceType == 'TIME OUT' ? DateTimeFormats.timeOnly(now) : null,
              ),
            ),
          );
        });
      }
    } else {
      // Handle error cases - map error strings to result types like HomePage does
      String resultTypeStr;
      print('[DASHBOARD_ERROR] attendanceType=$attendanceType');
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
      print('[DASHBOARD_ERROR] resultTypeStr=$resultTypeStr');
      
      // Navigate to dashboard with error result type to show modal
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _dashboardController.setRouteActive(false);
          _dashboardController.stopScanLoop(setScanning: _controller.setScanning);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardPage(
                employeeId: employee.id,
                employeeName: employee.name,
                attendanceType: attendanceType,
                matchedAt: DateTime.now(),
                siteId: widget.siteId,
                resultType: resultTypeStr,
              ),
            ),
          );
        });
      }
    }
  }
  
  Future<String?> _recordAttendance(String employeeId) async {
    return _dashboardController.recordAttendance(
      employeeId: employeeId,
      siteId: widget.siteId?.toString(),
    );
  }
  
  void _showResultModalIfNeeded() {
    final type = widget.resultType;
    if (type == null || type.isEmpty) return;
    
    String title;
    String subtitle;
    String buttonText;
    Color buttonColor;
    Color iconBgColor;
    Color iconColor;
    IconData iconData;
    
    switch (type) {
      case 'timeInSuccess':
        title = 'TIME IN SUCCESSFUL';
        subtitle = 'Your time in has been recorded successfully. Wishing you a productive day!';
        buttonText = 'PROCEED';
        buttonColor = const Color(0xFF90EE90);
        iconBgColor = const Color(0xFF90EE90).withValues(alpha: 0.3);
        iconColor = const Color(0xFF2E7D32);
        iconData = Icons.check_circle;
        break;
      case 'timeOutSuccess':
        title = 'TIME OUT SUCCESSFUL';
        subtitle = 'Your time out has been recorded successfully. Wishing you a productive day!';
        buttonText = 'PROCEED';
        buttonColor = const Color(0xFF90EE90);
        iconBgColor = const Color(0xFF90EE90).withValues(alpha: 0.3);
        iconColor = const Color(0xFF2E7D32);
        iconData = Icons.check_circle;
        break;
      case 'alreadyTimedIn':
        title = 'ALREADY TIMED IN';
        subtitle = 'You have already timed in. Please wait 5 minutes to time out.';
        buttonText = 'Close';
        buttonColor = const Color(0xFFA3C9FF);
        iconBgColor = const Color(0xFFA3C9FF).withValues(alpha: 0.3);
        iconColor = const Color(0xFF1565C0);
        iconData = Icons.info;
        break;
      case 'alreadyTimedOut':
        title = 'ALREADY TIMED OUT';
        subtitle = 'You have already timed out for today. Please come back tomorrow.';
        buttonText = 'Close';
        buttonColor = const Color(0xFFA3C9FF);
        iconBgColor = const Color(0xFFA3C9FF).withValues(alpha: 0.3);
        iconColor = const Color(0xFF1565C0);
        iconData = Icons.info;
        break;
      case 'wait5Minutes':
        title = 'PLEASE WAIT';
        subtitle = 'You must wait 5 minutes after time in before you can time out.';
        buttonText = 'Close';
        buttonColor = const Color(0xFFFFB74D);
        iconBgColor = const Color(0xFFFFB74D).withValues(alpha: 0.3);
        iconColor = const Color(0xFFEF6C00);
        iconData = Icons.access_time;
        break;
      case 'timeInUnsuccessful':
        title = 'TIME IN UNSUCCESSFUL';
        subtitle = "We couldn't process your request. Please try again.";
        buttonText = 'RETRY';
        buttonColor = const Color(0xFFFFA0A0);
        iconBgColor = const Color(0xFFFFA0A0).withValues(alpha: 0.3);
        iconColor = const Color(0xFFC62828);
        iconData = Icons.error;
        break;
      case 'timeOutUnsuccessful':
        title = 'TIME OUT UNSUCCESSFUL';
        subtitle = "We couldn't process your request. Please try again.";
        buttonText = 'RETRY';
        buttonColor = const Color(0xFFFFA0A0);
        iconBgColor = const Color(0xFFFFA0A0).withValues(alpha: 0.3);
        iconColor = const Color(0xFFC62828);
        iconData = Icons.error;
        break;
      case 'fingerprintNotRecognized':
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 120,
                  height: 32,
                    child: ElevatedButton(
                      onPressed: () {
                        _resetAfkTimer(); // Reset AFK timer when user interacts
                        Navigator.of(context).pop();
                        if (_enableScanning && _device.isConnected) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _dashboardController.stopScanLoop(
                                setScanning: _controller.setScanning,
                              );
                              _dashboardController.startScanLoop(
                                device: _device,
                                isScanning: () => _controller.isScanning.value,
                                setScanning: _controller.setScanning,
                                onTemplateReady: _onTemplateReady,
                              );
                            }
                          });
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
  
  void _returnToScanner() {
    // Show brief message before returning
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Returning to scanner...'),
        duration: Duration(milliseconds: 800),
        backgroundColor: Colors.blue,
      ),
    );
    
    // Small delay then navigate back
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        // Pop back to home page (which is now safely in the navigation stack)
        Navigator.of(context).pop();
      }
    });
  }
  
  void _resetAfkTimer() {
    _dashboardController.resetAfkTimer();
  }

  Future<void> _loadRows() async {
    await _dashboardController.loadRows(
      siteId: widget.siteId,
      employeeId: widget.employeeId,
      overrideTimeIn: widget.timeIn,
      overrideTimeOut: widget.timeOut,
    );
  }

  String _rowDateKey(DashboardRowVm row) {
    final parsed = DateTime.tryParse(row.rawDate);
    if (parsed != null) return DateTimeFormats.dateKey(parsed);
    if (row.rawDate.length >= 10) return row.rawDate.substring(0, 10);
    return row.rawDate;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final outerRadius = BorderRadius.circular(w * 0.035);

    return Scaffold(
      backgroundColor: Colors.black,
      // Navigation bar removed - auto-return to home after AFK timeout
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/Main BG.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(w * 0.005),
            child: ClipRRect(
              borderRadius: outerRadius,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/Main BG.png',
                      fit: BoxFit.cover,
                    ),
                  ),
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
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: w * 0.02,
                      vertical: h * 0.025,
                    ),
                    child: Column(
                      children: [
                        Expanded(flex: 3, child: _buildTopRow(w, h)),
                        SizedBox(height: h * 0.022),
                        Expanded(flex: 2, child: _buildBottomTable(w, h)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
      child: DashboardRisingFadeParticle(
        size: sizePx,
        phase: phase,
        assetPath: 'assets/icons/square-particles-fx.svg',
      ),
    );
  }

  Widget _buildTopRow(double w, double h) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileCard(w, h),
        SizedBox(width: w * 0.010),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTimePanel(w, h),
              SizedBox(height: h * 0.03),
              _buildTodayLogCard(w, h),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(double w, double h) {
    return Obx(() {
      final cardRadius = BorderRadius.circular(w * 0.023);
      final expandedPanelColor = const Color(0xFF092238).withValues(alpha: 0.50);
      final profilePhoto = _dashboardController.profilePhoto.value;
      final alreadyTimedIn = _dashboardController.alreadyTimedIn.value;

      return ClipRRect(
        borderRadius: cardRadius,
        child: Container(
        width: w * 0.55,
        height: double.infinity,
        color: Colors.transparent,
        child: Row(
          children: [
            Container(
              width: w * 0.2,
              decoration: BoxDecoration(
                color: const Color(0xFF092238).withValues(alpha: 0.7),
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
                         color: Colors.white.withValues(alpha: 0.85),
                         width: 3,
                       ),
                      gradient: profilePhoto == null
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF3FA9F5), Color(0xFF1B75BB)],
                            )
                          : null,
                      image: profilePhoto != null
                          ? DecorationImage(
                              image: MemoryImage(profilePhoto),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: profilePhoto == null
                        ? Builder(
                            builder: (_) {
                              final initials =
                                  _initialsFromName(widget.employeeName);
                              if (initials.isNotEmpty) {
                                return Text(
                                  initials,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: w * 0.030,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 2,
                                  ),
                                );
                              }
                              return const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 40,
                              );
                            },
                          )
                        : null,
                  ),
                  SizedBox(height: h * 0.012),
                  Text(
                    'PROFILE',
                    style: TextStyle(
                      fontFamily: 'CEORUSE',
                      fontSize: w * 0.012,
                      color: Colors.white.withValues(alpha: 0.8),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 1,
                          child: GestureDetector(
                            onTap: () {
                              _resetAfkTimer();
                              if (widget.onPortalTap != null) {
                                widget.onPortalTap!();
                              } else {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              }
                            },
                            child: _buildTopPill(
                              w,
                              label: 'PORTAL',
                              active: false,
                            ),
                          ),
                        ),
                        SizedBox(width: w * 0.005),
                        Expanded(
                          flex: 1,
                          child: GestureDetector(
                            onTap: () {
                              _resetAfkTimer();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => EnrollmentPage(
                                    siteId: widget.siteId,
                                    isEditMode: true,
                                    employeeId: widget.employeeId,
                                    employeeName: widget.employeeName,
                                  ),
                                ),
                              );
                            },
                            child: _buildTopPill(
                              w,
                              label: 'ENROLL NOW',
                              active: true,
                            ),
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
                            clipper: const TopLeftCurvedNotchClipper(),
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
                                    (widget.employeeName ?? 'UNKNOWN USER')
                                        .toUpperCase(),
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
                                      borderRadius: BorderRadius.circular(
                                        w * 0.013,
                                      ),
                                    ),
                                    child: Text(
                                      widget.employeeId ?? 'N/A',
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
                                    widget.attendanceType ?? 'RECORDED',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontStyle: FontStyle.italic,
                                      fontSize: w * 0.015,
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                  if (alreadyTimedIn) ...[
                                    SizedBox(height: h * 0.008),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: w * 0.010,
                                        vertical: h * 0.004,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.8),
                                        borderRadius: BorderRadius.circular(w * 0.008),
                                      ),
                                      child: Text(
                                        'ALREADY TIMED IN (within 20 min)',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: w * 0.011,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                  SizedBox(height: h * 0.006),
                                  Text(
                                    'INFORMATION TECHNOLOGY | FAST\nDISTRIBUTION CORPORATION',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: w * 0.014,
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
      ));
    });
  }

  Widget _buildTopPill(
    double w, {
    required String label,
    bool active = false,
    VoidCallback? onTap,
  }) {
    final radius = BorderRadius.circular(w * 0.018);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.01, vertical: w * 0.01),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: active
            ? const Color(0xFF0E1F33).withValues(alpha: 0.50)
            : const Color(0xFF0E1F33).withValues(alpha: 0.50),
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

  Widget _buildTimePanel(double w, double h) {
    return Obx(() {
      final now = _dashboardController.now.value;
      final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final minute = now.minute.toString().padLeft(2, '0');
      final period = now.hour >= 12 ? 'PM' : 'AM';
      return Container(
        padding: EdgeInsets.symmetric(horizontal: w * 0.020, vertical: h * 0.050),
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
                    fontSize: w * 0.042,
                    color: Colors.white,
                    letterSpacing: 4,
                    height: 1,
                  ),
                ),
                SizedBox(height: h * 0.006),
                Text(
                  DateTimeFormats.dateLongUpper(now),
                  style: TextStyle(
                    fontFamily: 'CEORUSE',
                    fontSize: w * 0.020,
                    color: Colors.white.withValues(alpha: 0.9),
                    letterSpacing: 3,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: h * 0.002),
                Text(
                  DateTimeFormats.dayLongUpper(now),
                  style: TextStyle(
                    fontFamily: 'CEORUSE',
                    fontSize: w * 0.014,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildTodayLogCard(double w, double h) {
    return Obx(() {
      final now = widget.matchedAt ?? DateTime.now();
      final todayDate = DateTimeFormats.dateLongUpper(now);
      final todayKey = DateTimeFormats.dateKey(now);
      final rows = _dashboardController.rows;
      final todayRow = rows.firstWhere(
        (row) => _rowDateKey(row) == todayKey,
        orElse: () => rows.isNotEmpty
            ? rows.first
            : const DashboardRowVm(
                rawDate: '',
                date: '-',
                day: '-',
                shift: '-',
                timeLogs: '- | -',
                status: 'NO LOG',
                isComplete: false,
              ),
      );

      final passedTimeIn = widget.timeIn;
      final passedTimeOut = widget.timeOut;

      final todayLog = todayRow.timeLogs.split('|');
      final rowTimeIn = todayLog.isNotEmpty ? todayLog.first.trim() : '-';
      final rowTimeOut = todayLog.length > 1 ? todayLog[1].trim() : '-';

      final todayIn = passedTimeIn ?? (rowTimeIn != '-' ? rowTimeIn : '-');
      final todayOut = passedTimeOut ?? (rowTimeOut != '-' ? rowTimeOut : '-');
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
        width: w * 0.38,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(w * 0.028),
            color: const Color(0xFF0B2742).withValues(alpha: 0.70),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: h * 0.014),
                child: Text(
                  'TODAYS LOG',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: w * 0.020,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ),
              Container(
                color: const Color(0xFF081A2E).withValues(alpha: 0.50),
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.014,
                  vertical: h * 0.016,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Date',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.014,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'IN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.014,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'OUT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.014,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.014,
                  vertical: h * 0.018,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 255, 255).withValues(alpha: 0.40),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(w * 0.028),
                    bottomRight: Radius.circular(w * 0.028),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        todayDate,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.010,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        todayIn,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.010,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        todayOut,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.010,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    });
  }

  Widget _buildBottomTable(double w, double h) {
    final headerStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: w * 0.014,
      fontWeight: FontWeight.bold,
      color: Colors.white.withValues(alpha: 0.85),
      letterSpacing: 2,
    );

    final cellStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: w * 0.013,
      color: Colors.white,
      letterSpacing: 1.4,
    );

    return Obx(() {
      final rows = _dashboardController.rows;
      final loadingRows = _dashboardController.isLoadingRows.value;

      return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.028),
        color: const Color.fromRGBO(4, 17, 27, 1).withValues(alpha: 0.50),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF05080C).withValues(alpha: 0.30),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(w * 0.028),
                topRight: Radius.circular(w * 0.028),
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.024,
              vertical: h * 0.016,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(flex: 3, child: Text('Date', style: headerStyle)),
                Expanded(flex: 2, child: Text('Day', style: headerStyle)),
                Expanded(flex: 3, child: Text('Workhours', style: headerStyle)),
                Expanded(flex: 3, child: Text('Time Logs', style: headerStyle)),
                Expanded(flex: 2, child: Text('Status', style: headerStyle)),
              ],
            ),
          ),
          Expanded(
            child: loadingRows
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                ? Center(
                    child: Text(
                      'No timelog history found',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: w * 0.014,
                        color: Colors.white70,
                        letterSpacing: 1.2,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: index.isEven
                              ? const Color(0xFF071A2B).withValues(alpha: 0.50)
                              : const Color.fromARGB(255, 147, 158, 168).withValues(alpha: 0.30),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: w * 0.024,
                          vertical: h * 0.008,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(row.date, style: cellStyle),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(row.day, style: cellStyle),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(row.shift, style: cellStyle),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(row.timeLogs, style: cellStyle),
                            ),
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _buildStatusChip(w, row),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox.shrink(),
                    itemCount: rows.length,
                  ),
          ),
        ],
      ),
    );
    });
  }

  Widget _buildStatusChip(double w, DashboardRowVm row) {
    final color = row.isComplete
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFFC107);
    final bg = row.isComplete
        ? const Color(0xFF162D1D)
        : const Color(0xFF2E2611);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.015, vertical: w * 0.005),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.018),
        color: bg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w * 0.01,
            height: w * 0.01,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          SizedBox(width: w * 0.008),
          Text(
            row.status,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.010,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}


