// ignore_for_file: unused_local_variable

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:user_attendance_scanner/app/modules/home/views/dashboard_page.dart';
import 'package:user_attendance_scanner/app/core/widgets/animations/dashboard_rising_fade_particle.dart';
import 'package:user_attendance_scanner/app/modules/enrollment/controllers/enrollment_controller.dart';
import 'package:user_attendance_scanner/app/modules/home/controllers/offline_mode_controller.dart';
import 'package:user_attendance_scanner/app/core/widgets/top_left_curved_notch_clipper.dart';
import 'package:user_attendance_scanner/app/modules/enrollment/views/enrollment_saving_page.dart';

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
    final controller = Get.find<EnrollmentController>();

    // Set up callbacks
    controller.onError = (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    };
    controller.onFingerprintAlreadyEnrolled = () {
      if (!context.mounted) return;
      _showFingerprintAlreadyEnrolledDialog(context);
    };
    controller.onFingerprintNotRecognized = () {
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF0B2742),
          title: const Text(
            'Fingerprint Not Recognized',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'This fingerprint is not recognized or is not enrolled in the database. '
            'Please try again or enter the employee ID manually.',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Color(0xFF44D980),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    };
    controller.onSuccess = (message) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
      }
    };

    // Pause inactivity timer while on enrollment page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final offlineModeController = Get.find<OfflineModeController>();
        offlineModeController.setInDashboardOrEnrollment(true);
      } catch (e) {
        debugPrint('[ENROLLMENT] OfflineModeController not found: $e');
      }
    });

    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          // Resume inactivity timer when leaving enrollment page
          try {
            final offlineModeController = Get.find<OfflineModeController>();
            offlineModeController.setInDashboardOrEnrollment(false);
          } catch (e) {
            debugPrint('[ENROLLMENT] OfflineModeController not found on pop: $e');
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
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
                              flex: 3,
                              child: _buildProfileCard(
                                w,
                                h,
                                controller,
                                context,
                              ),
                            ),
                            SizedBox(width: w * 0.01),
                            Expanded(
                              flex: 2,
                              child: Column(
                                children: [
                                  _buildTimePanel(w, h),
                                  SizedBox(height: h * 0.08),
                                  _buildTodayLogCard(w, h),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: h * 0.03),
                      _buildBottomRow(context, w, h, controller),
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

  Widget _buildTimePanel(double w, double h) {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return Container(
      padding: EdgeInsets.all(h * 0.045),
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
                  fontSize: w * 0.045,
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
                  fontSize: w * 0.018,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 3,
                  height: 1.1,
                ),
              ),
              SizedBox(height: h * 0.002),
              Text(
                _formatDay(now),
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: w * 0.015,
                  color: Colors.white.withValues(alpha: 0.7),
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDay(DateTime date) {
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    return days[date.weekday - 1];
  }

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
            color: const Color(0xFF0B2742).withValues(alpha: 0.70),
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
                color: const Color(0xFF081A2E).withValues(alpha: 0.5),
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
                  color: Colors.white.withValues(alpha: 0.4),
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

  Widget _logCell(
    double w,
    String text, {
    bool bold = false,
    bool small = false,
  }) {
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

  Widget _buildTopPill(double w, {required String label, bool active = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.01, vertical: w * 0.01),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.018),
        color: const Color(0xFF0E1F33).withValues(alpha: 0.5),
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

  Widget _buildProfileCard(
    double w,
    double h,
    EnrollmentController controller,
    BuildContext context,
  ) {
    final cardRadius = BorderRadius.circular(w * 0.023);
    final expandedPanelColor = const Color(0xFF092238).withValues(alpha: 0.5);
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller.selfieImageBytes,
        controller.idController,
        controller.usernameController,
        controller.employeePosition,
        controller.employeeSbu,
      ]),
      builder: (context, _) {
        final selfieImage = controller.selfieImageBytes.value;
        final displayName = controller.usernameController.text;
        final displayId = controller.idController.text;
        final position = controller.employeePosition.value.trim();
        final sbu = controller.employeeSbu.value.trim();
        final recordedLine = position.isNotEmpty && sbu.isNotEmpty
            ? '$position | $sbu'
            : (position.isNotEmpty
                ? position
                : (sbu.isNotEmpty
                    ? sbu
                    : 'Position and department will appear after lookup'));

        return ClipRRect(
          borderRadius: cardRadius,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.transparent,
            child: Row(
              children: [
                Container(
                  width: w * 0.18,
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
                      GestureDetector(
                        onTap: controller.takeSelfie,
                        child: Container(
                          width: w * 0.11,
                          height: w * 0.11,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 3,
                            ),
                            gradient: selfieImage == null
                                ? const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF3FA9F5),
                                      Color(0xFF1B75BB),
                                    ],
                                  )
                                : null,
                            image: selfieImage != null
                                ? DecorationImage(
                                    image: MemoryImage(selfieImage),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: selfieImage == null
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 40,
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
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Get.until((route) => route.isFirst),
                                child: _buildTopPill(w, label: 'PORTAL'),
                              ),
                            ),
                            SizedBox(width: w * 0.005),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Get.off<void>(
                                    () => DashboardPage(
                                      employeeId: displayId.isNotEmpty
                                          ? displayId
                                          : employeeId,
                                      employeeName: displayName.isNotEmpty
                                          ? displayName
                                          : employeeName,
                                      siteId: siteId,
                                    ),
                                  );
                                },
                                child: _buildTopPill(
                                  w,
                                  label: 'LOGIN',
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName.toUpperCase(),
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
                                      FractionallySizedBox(
                                        widthFactor: 0.60,
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: w * 0.013,
                                            vertical: h * 0.004,
                                          ),
                                          decoration: BoxDecoration(
                                            image: const DecorationImage(
                                              image: AssetImage(
                                                'assets/images/Main BG.png',
                                              ),
                                              fit: BoxFit.cover,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              w * 0.013,
                                            ),
                                          ),
                                          child: Text(
                                            displayId,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
                                            style: TextStyle(
                                              fontFamily: 'CEORUSE',
                                              fontSize: w * 0.013,
                                              color: Colors.white,
                                              letterSpacing: 1.5,
                                            ),
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
                                          color: Colors.white.withValues(alpha: 0.8),
                                          letterSpacing: 1.4,
                                        ),
                                      ),
                                      SizedBox(height: h * 0.006),
                                      Text(
                                        recordedLine.toUpperCase(),
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
      },
    );
  }

  Widget _buildBottomRow(
    BuildContext context,
    double w,
    double h,
    EnrollmentController controller,
  ) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEnrollmentGuide(w, h, controller),
          SizedBox(width: w * 0.010),
          Container(
            padding: EdgeInsets.all(w * 0.010),
            decoration: BoxDecoration(
              color: const Color(0xFF0B2742).withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(w * 0.022),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildScannerCard(w, h),
                SizedBox(width: w * 0.010),
                _buildFingerprintPreview(w, h, controller),
              ],
            ),
          ),
          SizedBox(width: w * 0.010),
          _buildStatusPanel(context, w, h, controller),
        ],
      ),
    );
  }

  Widget _buildEnrollmentGuide(
    double w,
    double h,
    EnrollmentController controller,
  ) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.isIdentifyingEmployee,
      builder: (context, isIdentifying, _) {
        if (isIdentifying) {
          return _buildIdentificationGuide(w, h, controller);
        }
        return ValueListenableBuilder<bool>(
          valueListenable: controller.showForm,
          builder: (context, showForm, _) {
            if (showForm) {
              return _buildEnrollmentForm(w, h, controller);
            }
            return _buildManualEntryGuide(w, h, controller);
          },
        );
      },
    );
  }

  Widget _buildIdentificationGuide(
    double w,
    double h,
    EnrollmentController controller,
  ) {
    return Container(
      width: w * 0.20,
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.016,
        vertical: h * 0.020,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2742).withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(w * 0.022),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Identify Employee',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.012,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: h * 0.024),
          Text(
            '1. Place your finger on the scanner\n2. System will identify you\n3. Your details will be displayed\n4. Then scan new fingerprints\n5. Press SAVE to update',
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
            onTap: controller.cancelIdentificationMode,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.012,
                vertical: h * 0.010,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF244D86),
                borderRadius: BorderRadius.circular(w * 0.012),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard, color: Colors.white, size: w * 0.013),
                  SizedBox(width: w * 0.006),
                  Flexible(
                    child: Text(
                      'ENTER ID',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: w * 0.010,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
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

  Widget _buildManualEntryGuide(
    double w,
    double h,
    EnrollmentController controller,
  ) {
    return Container(
      width: w * 0.20,
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.020,
        vertical: h * 0.020,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2742).withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(w * 0.022),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Update Fingerprint',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.012,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: h * 0.024),
          Text(
            '1. Enter employee ID to lookup\n2. Or scan fingerprint to identify\n3. System displays employee details\n4. Scan new fingerprints (3 left, 3 right)\n5. Press SAVE to update',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.011,
              color: Colors.white,
              height: 1.6,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: h * 0.020),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => controller.showForm.value = true,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: w * 0.012,
                      vertical: h * 0.012,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3E7DDD),
                      borderRadius: BorderRadius.circular(w * 0.012),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, color: Colors.white, size: w * 0.014),
                        SizedBox(width: w * 0.006),
                        Text(
                          'ENTER ID',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: w * 0.010,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: w * 0.008),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    await controller.startIdentificationMode();
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: w * 0.012,
                      vertical: h * 0.012,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF44D980),
                      borderRadius: BorderRadius.circular(w * 0.012),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fingerprint, color: Colors.white, size: w * 0.014),
                        SizedBox(width: w * 0.006),
                        Text(
                          'SCAN',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: w * 0.010,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnrollmentForm(
    double w,
    double h,
    EnrollmentController controller,
  ) {
    final readOnly = isEditMode;
    return Container(
      width: w * 0.20,
      padding: EdgeInsets.symmetric(horizontal: w * 0.020, vertical: h * 0.020),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2742).withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(w * 0.022),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
          Text(
            isEditMode ? 'Employee Details' : 'Employee Details',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.012,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: h * 0.016),
          _buildTextField(
            w,
            h,
            'Employee ID',
            controller.idController,
            readOnly: false,
            onSubmitted: () => FocusManager.instance.primaryFocus?.unfocus(),
          ),
          SizedBox(height: h * 0.016),
          _buildTextField(
            w,
            h,
            'Username',
            controller.usernameController,
            readOnly: true,
          ),
          SizedBox(height: h * 0.016),
          GestureDetector(
            onTap: () => controller.loadEmployeeDetails(controller.idController.text),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.012,
                vertical: h * 0.010,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF3E7DDD),
                borderRadius: BorderRadius.circular(w * 0.012),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search, color: Colors.white, size: w * 0.014),
                  SizedBox(width: w * 0.006),
                  Flexible(
                    child: Text(
                      'LOOKUP EMPLOYEE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: w * 0.010,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: h * 0.008),
          GestureDetector(
            onTap: () async {
              await controller.startIdentificationMode();
            },
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.012,
                vertical: h * 0.010,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF44D980),
                borderRadius: BorderRadius.circular(w * 0.012),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fingerprint, color: Colors.white, size: w * 0.014),
                  SizedBox(width: w * 0.006),
                  Flexible(
                    child: Text(
                      'SCAN TO IDENTIFY',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: w * 0.010,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    double w,
    double h,
    String label,
    TextEditingController controller, {
    bool readOnly = false,
    VoidCallback? onSubmitted,
    VoidCallback? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: w * 0.010,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        SizedBox(height: h * 0.008),
        Container(
          padding: EdgeInsets.symmetric(horizontal: w * 0.012),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(w * 0.010),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            enableInteractiveSelection: !readOnly,
            showCursor: !readOnly,
            onChanged: (_) => onChanged?.call(),
            onSubmitted: (_) => onSubmitted?.call(),
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
                color: Colors.white.withValues(alpha: 0.5),
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

  Widget _buildFingerprintPreview(
    double w,
    double h,
    EnrollmentController controller,
  ) {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: controller.lastFingerprintImage,
      builder: (context, lastFingerprintImage, _) {
        return Container(
          width: w * 0.16,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(w * 0.022),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(w * 0.022),
            child: SizedBox.expand(
              child: lastFingerprintImage != null
                  ? Image.memory(lastFingerprintImage, fit: BoxFit.cover)
                  : Center(
                      child: SizedBox(
                        width: w * 0.15,
                        height: w * 0.15,
                        child: Image.asset(
                          'assets/images/Finger Print Icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusPanel(
    BuildContext context,
    double w,
    double h,
    EnrollmentController controller,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildThumbStatus(w, h, controller, title: 'LEFT THUMB STATUS'),
          SizedBox(height: h * 0.018),
          _buildThumbStatus(
            w,
            h,
            controller,
            title: 'RIGHT THUMB STATUS',
            isRight: true,
          ),
          SizedBox(height: h * 0.02),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  w,
                  h,
                  label: 'RESET',
                  color: const Color(0xFF244D86),
                  onTap: controller.resetFingerprints,
                ),
              ),
              SizedBox(width: w * 0.012),
              Expanded(
                child: Obx(
                  () => _buildActionButton(
                    w,
                    h,
                    label: controller.isSaving.value ? 'SAVING...' : 'SAVE',
                    color: const Color(0xFF44D980),
                    onTap: controller.isSaving.value
                        ? null
                        : () => _onSavePressed(context, controller),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThumbStatus(
    double w,
    double h,
    EnrollmentController controller, {
    required String title,
    bool isRight = false,
  }) {
    final scanNotifier = isRight
        ? controller.rightThumbScans
        : controller.leftThumbScans;
    return ValueListenableBuilder<int>(
      valueListenable: scanNotifier,
      builder: (context, scans, _) {
        final maxScans = EnrollmentController.scansPerFinger;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.016,
            vertical: h * 0.026,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0B2742).withValues(alpha: 0.70),
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
              Text(
                '$scans/$maxScans',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: w * 0.010,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              SizedBox(height: h * 0.008),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(maxScans, (i) {
                  final isActive = i < scans;
                  return Container(
                    width: w * 0.020,
                    height: w * 0.020,
                    margin: EdgeInsets.symmetric(horizontal: w * 0.006),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? const Color(0xFF39BF54)
                          : Colors.grey.withValues(alpha: 0.55),
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
      },
    );
  }

  Future<void> _showFingerprintAlreadyEnrolledDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0B2742),
        title: const Text(
          'Fingerprint Already Enrolled',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'This employee already has saved fingerprints on file. '
          'You cannot enroll again from this screen. '
          'Open Update Fingerprint from the menu to replace an existing enrollment.',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white70,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'OK',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFF44D980),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSavePressed(
    BuildContext context,
    EnrollmentController controller,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();

    final precheck = await controller.precheckEnrollmentSave();
    if (precheck != EnrollmentSavePrecheck.ok) {
      if (!context.mounted) return;
      if (precheck == EnrollmentSavePrecheck.alreadyEnrolled) {
        await _showFingerprintAlreadyEnrolledDialog(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(controller.messageForSavePrecheck(precheck)),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    EnrollmentSaveContext? saveCtx;
    final saveFuture = controller.saveEnrollmentLocal().then((ctx) {
      saveCtx = ctx;
      return ctx != null;
    });
    var saved = false;

    await Get.to<void>(
      () => EnrollmentSavingPage(
        saveFuture: saveFuture,
        onLocalSaved: () => saved = true,
      ),
      fullscreenDialog: true,
    );

    if (!saved || saveCtx == null) return;

    // Return to Home as soon as local DB has both thumbs; HRIS upload continues in background.
    Get.until((route) => route.isFirst);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enrollment saved locally'),
          backgroundColor: Colors.green,
        ),
      );
    }

    unawaited(controller.uploadEnrollmentToHris(saveCtx!));
  }

  Widget _buildActionButton(
    double w,
    double h, {
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: Container(
          height: w * 0.065,
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
      ),
    );
  }
}
