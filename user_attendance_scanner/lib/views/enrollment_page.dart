// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:user_attendance_scanner/views/dashboard_page.dart';
import '../zkfp/zkteco_usb.dart';
import '../services/local_db.dart';

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

class EnrollmentPage extends StatelessWidget {
  const EnrollmentPage({
    super.key,
    this.siteId,
    this.isEditMode = false,
    this.employeeId,
    this.employeeName,
  });

  final String? siteId;
  final bool isEditMode;
  final String? employeeId;
  final String? employeeName;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(
      EnrollmentController(
        siteId: siteId,
        isEditMode: isEditMode,
        employeeId: employeeId,
        employeeName: employeeName,
      ),
      tag: 'enrollment_${siteId ?? 'default'}_${employeeId ?? 'new'}',
    );
  
  // Set up callbacks with context
    controller.onStateChanged = () {
      // Trigger UI update if needed
    };
    
    controller.onError = (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ),
      );
    };
    
    controller.onSuccess = (message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
    };

    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: screenH - MediaQuery.of(context).padding.top,
              ),
              child: IntrinsicHeight(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenW * 0.015,
                    vertical: screenH * 0.015,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(screenW, screenH, controller, context),
                      SizedBox(height: screenH * 0.018),
                      Expanded(
                        child: _buildMainContent(screenW, screenH, controller),
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

  Widget _buildTopBar(double screenW, double screenH, EnrollmentController controller, BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Back button
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
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
              Icons.arrow_back,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        // Title
        Text(
          isEditMode ? 'EDIT EMPLOYEE' : 'ENROLLMENT',
          style: TextStyle(
            fontFamily: 'CEORUSE',
            fontSize: screenW * 0.04,
            color: Colors.white,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
        // Empty space for balance
        const SizedBox(width: 40),
      ],
    );
  }

  Widget _buildMainContent(double screenW, double screenH, EnrollmentController controller) {
    return Obx(() {
      return Row(
        children: [
          // Left panel - Fingerprint scanning
          Expanded(
            flex: 3,
            child: _buildFingerprintPanel(screenW, screenH, controller),
          ),
          SizedBox(width: screenW * 0.02),
          // Right panel - Employee details
          Expanded(
            flex: 2,
            child: _buildEmployeePanel(screenW, screenH, controller),
          ),
        ],
      );
    });
  }

  Widget _buildFingerprintPanel(double screenW, double screenH, EnrollmentController controller) {
    return Obx(() {
      final isDeviceReady = controller.deviceInitialized.value;
      final isScanning = controller.isScanning.value;
      final leftScans = controller.leftThumbScans.value;
      final rightScans = controller.rightThumbScans.value;
      final totalScans = leftScans + rightScans;
      final maxScans = EnrollmentController.scansPerFinger * 2;
      final isComplete = totalScans >= maxScans;

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(screenW * 0.02),
          border: Border.all(
            color: const Color(0xFF3E7DDD).withOpacity(0.3),
            width: 2,
          ),
          color: Colors.black.withOpacity(0.3),
        ),
        child: Padding(
          padding: EdgeInsets.all(screenW * 0.02),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Title
              Text(
                'FINGERPRINT SCANNING',
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: screenW * 0.025,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: screenH * 0.02),

              // Device status
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenW * 0.02,
                  vertical: screenH * 0.01,
                ),
                decoration: BoxDecoration(
                  color: isDeviceReady ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(screenW * 0.01),
                  border: Border.all(
                    color: isDeviceReady ? Colors.green : Colors.red,
                  ),
                ),
                child: Text(
                  isDeviceReady ? 'DEVICE READY' : 'DEVICE NOT READY',
                  style: TextStyle(
                    fontFamily: 'CEORUSE',
                    fontSize: screenW * 0.015,
                    color: isDeviceReady ? Colors.green : Colors.red,
                    letterSpacing: 1,
                  ),
                ),
              ),
              SizedBox(height: screenH * 0.02),

              // Fingerprint visualization
              Expanded(
                child: Stack(
                  children: [
                    // Background particles
                    if (isScanning) ...[
                      Positioned(
                        top: screenH * 0.1,
                        left: screenW * 0.05,
                        child: _DashboardRisingFadeParticle(
                          size: screenW * 0.08,
                          assetPath: 'assets/icons/fingerprint.svg',
                          phase: 0.0,
                        ),
                      ),
                      Positioned(
                        top: screenH * 0.15,
                        right: screenW * 0.08,
                        child: _DashboardRisingFadeParticle(
                          size: screenW * 0.06,
                          assetPath: 'assets/icons/fingerprint.svg',
                          phase: 0.3,
                        ),
                      ),
                      Positioned(
                        bottom: screenH * 0.2,
                        left: screenW * 0.1,
                        child: _DashboardRisingFadeParticle(
                          size: screenW * 0.07,
                          assetPath: 'assets/icons/fingerprint.svg',
                          phase: 0.6,
                        ),
                      ),
                    ],

                    // Center content
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Fingerprint image or placeholder
                          Container(
                            width: screenW * 0.15,
                            height: screenW * 0.15,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.1),
                              border: Border.all(
                                color: isScanning ? Colors.green : Colors.grey,
                                width: 3,
                              ),
                            ),
                            child: Obx(() {
                              final fingerprintImage = controller.lastFingerprintImage.value;
                              if (fingerprintImage != null) {
                                return ClipOval(
                                  child: Image.memory(
                                    fingerprintImage,
                                    fit: BoxFit.cover,
                                  ),
                                );
                              }
                              return Icon(
                                Icons.fingerprint,
                                size: screenW * 0.08,
                                color: isScanning ? Colors.green : Colors.grey,
                              );
                            }),
                          ),
                          SizedBox(height: screenH * 0.02),

                          // Scanning progress
                          Text(
                            isScanning ? 'SCANNING...' : 'PLACE FINGER',
                            style: TextStyle(
                              fontFamily: 'CEORUSE',
                              fontSize: screenW * 0.02,
                              color: isScanning ? Colors.green : Colors.grey,
                              letterSpacing: 2,
                            ),
                          ),
                          SizedBox(height: screenH * 0.01),

                          // Progress text
                          Text(
                            isComplete 
                                ? 'SCANNING COMPLETE'
                                : 'Scan $totalScans/$maxScans complete',
                            style: TextStyle(
                              fontFamily: 'CEORUSE',
                              fontSize: screenW * 0.015,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),

                          // Individual finger progress
                          SizedBox(height: screenH * 0.02),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildFingerProgress(
                                'LEFT',
                                leftScans,
                                EnrollmentController.scansPerFinger,
                                screenW,
                              ),
                              _buildFingerProgress(
                                'RIGHT',
                                rightScans,
                                EnrollmentController.scansPerFinger,
                                screenW,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Reset button
              if (!isComplete)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: controller.resetFingerprints,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: screenH * 0.015),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(screenW * 0.01),
                      ),
                    ),
                    child: Text(
                      'RESET FINGERPRINTS',
                      style: TextStyle(
                        fontFamily: 'CEORUSE',
                        fontSize: screenW * 0.015,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildFingerProgress(String label, int current, int max, double screenW) {
    final progress = current / max;
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'CEORUSE',
            fontSize: screenW * 0.012,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: screenW * 0.01),
        Container(
          width: screenW * 0.08,
          height: screenW * 0.01,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(screenW * 0.005),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: progress == 1.0 ? Colors.green : Colors.blue,
                borderRadius: BorderRadius.circular(screenW * 0.005),
              ),
            ),
          ),
        ),
        SizedBox(height: screenW * 0.005),
        Text(
          '$current/$max',
          style: TextStyle(
            fontFamily: 'CEORUSE',
            fontSize: screenW * 0.01,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeePanel(double screenW, double screenH, EnrollmentController controller) {
    return Obx(() {
      final showForm = controller.showForm.value;
      final selfieImage = controller.selfieImageBytes.value;

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(screenW * 0.02),
          border: Border.all(
            color: const Color(0xFF3E7DDD).withOpacity(0.3),
            width: 2,
          ),
          color: Colors.black.withOpacity(0.3),
        ),
        child: Padding(
          padding: EdgeInsets.all(screenW * 0.02),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Title
              Text(
                'EMPLOYEE DETAILS',
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: screenW * 0.025,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: screenH * 0.02),

              // Profile picture
              GestureDetector(
                onTap: controller.takeSelfie,
                child: Container(
                  width: screenW * 0.12,
                  height: screenW * 0.12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                    border: Border.all(
                      color: Colors.blue,
                      width: 2,
                    ),
                  ),
                  child: selfieImage != null
                      ? ClipOval(
                          child: Image.memory(
                            selfieImage,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt,
                              size: screenW * 0.04,
                              color: Colors.blue,
                            ),
                            Text(
                              'ADD PHOTO',
                              style: TextStyle(
                                fontFamily: 'CEORUSE',
                                fontSize: screenW * 0.01,
                                color: Colors.blue,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              SizedBox(height: screenH * 0.02),

              // Form fields (shown when ready)
              if (showForm) ...[
                // Employee ID field
                TextField(
                  controller: controller.idController,
                  style: TextStyle(
                    fontFamily: 'CEORUSE',
                    fontSize: screenW * 0.015,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    labelText: 'EMPLOYEE ID',
                    labelStyle: TextStyle(
                      fontFamily: 'CEORUSE',
                      color: Colors.white.withOpacity(0.7),
                      letterSpacing: 1,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: screenH * 0.015),

                // Employee name field
                TextField(
                  controller: controller.usernameController,
                  style: TextStyle(
                    fontFamily: 'CEORUSE',
                    fontSize: screenW * 0.015,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    labelText: 'EMPLOYEE NAME',
                    labelStyle: TextStyle(
                      fontFamily: 'CEORUSE',
                      color: Colors.white.withOpacity(0.7),
                      letterSpacing: 1,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: screenH * 0.03),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: controller.saveEnrollment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: screenH * 0.02),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(screenW * 0.01),
                      ),
                    ),
                    child: Text(
                      isEditMode ? 'UPDATE EMPLOYEE' : 'SAVE EMPLOYEE',
                      style: TextStyle(
                        fontFamily: 'CEORUSE',
                        fontSize: screenW * 0.018,
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Waiting message
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.fingerprint,
                          size: screenW * 0.08,
                          color: Colors.grey,
                        ),
                        SizedBox(height: screenH * 0.02),
                        Text(
                          'Complete fingerprint scanning\nto enter employee details',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'CEORUSE',
                            fontSize: screenW * 0.015,
                            color: Colors.grey,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
  }
    final isLeftTurn = _leftThumbScans < _scansPerFinger;
    final isRightTurn = _rightThumbScans < _scansPerFinger;
    
    // Debounce: prevent same finger from scanning too quickly
    final now = DateTime.now();
    if (_lastScanTime != null) {
      final diff = now.difference(_lastScanTime!).inMilliseconds;
      if (diff < _minTimeBetweenScansMs) {
        debugPrint('Scan too fast (${diff}ms) - please wait before scanning again');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait before scanning again'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 1),
          ),
        );
        return;
      }
    }
    
    // Temporarily disabled finger consistency validation to fix scanning issues
    // The validation was too strict and preventing same finger scans
    // TODO: Implement a more reliable fingerprint comparison method
    
    _lastScanTime = now;
    
    setState(() {
      if (isLeftTurn) {
        _leftThumbScansList.add(template);
        _leftThumbScans++;
        debugPrint('Left thumb scan ${_leftThumbScans}/$_scansPerFinger captured');
      } else if (isRightTurn) {
        _rightThumbScansList.add(template);
        _rightThumbScans++;
        debugPrint('Right thumb scan ${_rightThumbScans}/$_scansPerFinger captured');
      }
    });
    
    // Show feedback with clear next step
    final totalScans = _leftThumbScans + _rightThumbScans;
    final isComplete = totalScans >= (_scansPerFinger * 2);
    
    String message;
    Color color;
    
    if (isComplete) {
      message = 'Both thumbs captured successfully! Enter employee details.';
      color = Colors.green;
    } else if (_leftThumbScans < _scansPerFinger) {
      message = 'Left thumb scan ${_leftThumbScans}/$_scansPerFinger complete';
      color = Colors.blue;
    } else if (_rightThumbScans < _scansPerFinger) {
      message = 'Right thumb scan ${_rightThumbScans}/$_scansPerFinger complete';
      color = Colors.blue;
    } else {
      message = 'Scan $totalScans/${_scansPerFinger * 2} complete';
      color = Colors.blue;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  // Simple fingerprint template comparison for consistency validation
  bool _isSameFinger(Uint8List template1, Uint8List template2) {
    if (template1.length != template2.length) return false;
    
    // More lenient byte comparison with higher tolerance for scan variations
    int differences = 0;
    const maxDifferences = 200; // Increased tolerance for real-world scan variations
    
    for (int i = 0; i < template1.length; i++) {
      if (template1[i] != template2[i]) {
        differences++;
        if (differences > maxDifferences) return false;
      }
    }
    
    return true;
  }
  
  Future<void> _takeSelfie() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _selfieImageBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('Error taking selfie: $e');
    }
  }
  
  void _resetFingerprints() {
    _device.clearCachedCapture();
    setState(() {
      _leftThumbScans = 0;
      _rightThumbScans = 0;
      _leftThumbScansList.clear();
      _rightThumbScansList.clear();
      _lastFingerprintImage = null;
      _lastScanTime = null;
      _showForm = true; // Switch to enter details form
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enter employee details'),
        backgroundColor: Color(0xFF3E7DDD),
      ),
    );
  }
  
  void _saveEnrollment() async {
    // Validate form
    if (_idController.text.isEmpty || _usernameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter ID and username'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Check if all fingerprints were captured (3 per finger)
    if (_leftThumbScans < _scansPerFinger || _rightThumbScans < _scansPerFinger) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please scan each thumb 3 times (3 left, 3 right)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    try {
      final siteId = widget.siteId ?? 'default';
      final employeeId = _idController.text.trim();
      final employeeName = _usernameController.text.trim();
      
      debugPrint('Saving enrollment:');
      debugPrint('  ID: $employeeId');
      debugPrint('  Name: $employeeName');
      debugPrint('  Site: $siteId');
      debugPrint('  Left scans: ${_leftThumbScansList.length}');
      debugPrint('  Right scans: ${_rightThumbScansList.length}');
      
      // Check if employee already exists - only prevent replacement when NOT in edit mode
      if (!widget.isEditMode) {
        final existingEmployees = await LocalDb.getEmployeesBySite(siteId);
        final existingEmployee = existingEmployees.firstWhere(
          (emp) => emp['employee_id'].toString() == employeeId,
          orElse: () => <String, dynamic>{},
        );
        
        if (existingEmployee.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Employee with this ID already exists! Use a different ID.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      
      // Save only 2 templates (1st scan from each finger)
      // fid 1 = left thumb, fid 2 = right thumb
      await LocalDb.upsertEmployee(
        fid: 1,
        employeeId: employeeId,
        employeeName: employeeName,
        template: _leftThumbScansList[0],
        siteId: siteId,
      );
      debugPrint('Saved left thumb template');

      await LocalDb.upsertEmployee(
        fid: 2,
        employeeId: employeeId,
        employeeName: employeeName,
        template: _rightThumbScansList[0],
        siteId: siteId,
      );
      debugPrint('Saved right thumb template');
      
      if (_selfieImageBytes != null) {
        await LocalDb.upsertEmployeePhoto(
          employeeId: employeeId,
          siteId: siteId,
          photo: _selfieImageBytes!,
        );
        debugPrint('Saved employee selfie');
      }
      
      // Clear all data after save
      setState(() {
        _showForm = false;
        _leftThumbScans = 0;
        _rightThumbScans = 0;
        _leftThumbScansList.clear();
        _rightThumbScansList.clear();
        _idController.clear();
        _usernameController.clear();
        _lastFingerprintImage = null;
        _selfieImageBytes = null;
        _lastScanTime = null;
        _lastPhotoEmployeeId = null;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditMode
                ? 'Enrollment updated successfully! Employee data refreshed.'
                : 'Enrollment saved successfully! Employee registered.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Save error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Time Panel
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

  // Today Log Card
  Widget _buildTodayLogCard(double w, double h) {
    final now = DateTime.now();
    final todayDate = _formatDate(now);
    const todayIn = '8:00AM';
    const todayOut = '6:38PM';
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

  // Top Pill
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

  // Profile Card
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
                  GestureDetector(
                    onTap: _takeSelfie,
                    child: Container(
                      width: w * 0.11,
                      height: w * 0.11,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.85),
                          width: 3,
                        ),
                        gradient: _selfieImageBytes == null
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF3FA9F5), Color(0xFF1B75BB)],
                              )
                            : null,
                        image: _selfieImageBytes != null
                            ? DecorationImage(
                                image: MemoryImage(_selfieImageBytes!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _selfieImageBytes == null
                          ? Builder(
                              builder: (_) {
                                final initials = _initialsFromName(_displayName);
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
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            },
                            child: _buildTopPill(w, label: 'PORTAL'),
                          ),
                        ),
                        SizedBox(width: w * 0.005),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => DashboardPage(
                                    employeeId: _displayId.isNotEmpty ? _displayId : widget.employeeId,
                                    employeeName: _displayName.isNotEmpty ? _displayName : widget.employeeName,
                                    siteId: widget.siteId,
                                  ),
                                ),
                              );
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
                                    _displayName.toUpperCase(),
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
                                      _displayId,
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
                                    'RECORDED',
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

  // Bottom Row
  Widget _buildBottomRow(double w, double h) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEnrollmentGuide(w, h),
          SizedBox(width: w * 0.010),

          // Scanner + fingerprint container
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
    if (_showForm) {
      return _buildEnrollmentForm(w, h);
    }
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
            widget.isEditMode ? 'Update Enrollment' : 'Enrollment Guide',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.012,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: h * 0.024),
          Text(
            widget.isEditMode
                ? '1. Enter existing employee details\n2. Press SCAN to capture new prints\n3. Place left thumb 3 times\n4. Place right thumb 3 times\n5. Press SAVE to update'
                : '1. Tap PROFILE to take selfie\n2. Press SCAN to start\n3. Place left thumb 3 times\n4. Place right thumb 3 times\n5. Press SAVE to complete',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.011,
              color: Colors.white,
              height: 1.6,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: h * 0.020),
          GestureDetector(
            onTap: () => setState(() => _showForm = true),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.016,
                vertical: h * 0.012,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF3E7DDD),
                borderRadius: BorderRadius.circular(w * 0.012),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit,
                    color: Colors.white,
                    size: w * 0.014,
                  ),
                  SizedBox(width: w * 0.008),
                  Text(
                    'ENTER DETAILS',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: w * 0.011,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
  
  Widget _buildEnrollmentForm(double w, double h) {
    final readOnly = widget.isEditMode;
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
            widget.isEditMode ? 'Edit Employee Details' : 'Employee Details',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.012,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: h * 0.020),
          _buildTextField(w, h, 'Employee ID', _idController, readOnly: readOnly),
          SizedBox(height: h * 0.016),
          _buildTextField(w, h, 'Username', _usernameController, readOnly: readOnly),
        ],
      ),
    );
  }
  
  Widget _buildTextField(
    double w,
    double h,
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: w * 0.010,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
        SizedBox(height: h * 0.008),
        Container(
          padding: EdgeInsets.symmetric(horizontal: w * 0.012),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(w * 0.010),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            enableInteractiveSelection: !readOnly,
            showCursor: !readOnly,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.011,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Enter $label',
              hintStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: w * 0.011,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScannerCard(double w, double h) {
    return SizedBox(
      width: w * 0.20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(w * 0.022),
        child: Image.asset(
          'assets/images/finger-biometric-image.png',
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
        child: _lastFingerprintImage != null
            ? Image.memory(
                _lastFingerprintImage!,
                fit: BoxFit.contain,
              )
            : Image.asset(
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
          _buildThumbStatus(w, h, title: 'LEFT THUMB STATUS', activeCount: _leftThumbScans, maxCount: _scansPerFinger),
          SizedBox(height: h * 0.018),
          // Right thumb status
          _buildThumbStatus(w, h, title: 'RIGHT THUMB STATUS', activeCount: _rightThumbScans, maxCount: _scansPerFinger),
          const Spacer(),
          // Reset / Save buttons
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  w,
                  h,
                  label: 'RESET',
                  color: const Color(0xFF244D86),
                  onTap: _resetFingerprints,
                ),
              ),
              SizedBox(width: w * 0.012),
              Expanded(
                child: _buildActionButton(
                  w,
                  h,
                  label: 'SAVE',
                  color: const Color(0xFF44D980),
                  onTap: _saveEnrollment,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _clearScanState() {
    _leftThumbScans = 0;
    _rightThumbScans = 0;
    _leftThumbScansList.clear();
    _rightThumbScansList.clear();
    _lastFingerprintImage = null;
    _lastScanTime = null;
  }
  
  Widget _buildThumbStatus(double w, double h,
      {required String title, required int activeCount, required int maxCount}) {
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
          SizedBox(height: h * 0.008),
          // Debug counter
          Text(
            '$activeCount/$maxCount',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.010,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          SizedBox(height: h * 0.008),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(maxCount, (i) {
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
                  border: isActive 
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
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
          color: color,
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

  // Particle FX (copied from dashboard)
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

  // Build
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
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
