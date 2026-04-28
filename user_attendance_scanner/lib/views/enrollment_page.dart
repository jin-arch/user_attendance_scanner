// ignore_for_file: deprecated_member_use

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:user_attendance_scanner/views/dashboard_page.dart';
import '../controllers/enrollment_controller.dart';

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
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _translateY;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _opacity = Tween<double>(begin: 0.50, end: 0.0).animate(curve);
    _translateY = Tween<double>(begin: 0.0, end: -48.0).animate(curve);
    _scale = Tween<double>(begin: 1.0, end: 0.8).animate(curve);
    _controller.forward(from: widget.phase);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _translateY.value),
          child: Opacity(
            opacity: _opacity.value,
            child: Transform.scale(
              scale: _scale.value,
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
    final routeId = ModalRoute.of(context)?.hashCode ?? context.hashCode;
    final tag =
        'enrollment_${siteId ?? 'default'}_${employeeId ?? 'new'}_$routeId';
    EnrollmentController controller;
    
    if (Get.isRegistered<EnrollmentController>(tag: tag)) {
      controller = Get.find<EnrollmentController>(tag: tag);
    } else {
      controller = Get.put(
        EnrollmentController(
          siteId: siteId,
          isEditMode: isEditMode,
          employeeId: employeeId,
          employeeName: employeeName,
        ),
        tag: tag,
      );
    }

    // Set up callbacks
    controller.onStateChanged = () {};
    controller.onError = (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    };
    controller.onSuccess = (message) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
        final normalized = message.toLowerCase();
        final didSave = normalized.contains('saved successfully') ||
            normalized.contains('updated successfully');
        if (didSave) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            Navigator.of(context).popUntil((route) => route.isFirst);
          });
        }
      }
    };

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
                              child: _buildProfileCard(w, h, controller, context),
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
                      _buildBottomRow(w, h, controller),
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

  Widget _particle(double w, double h, double fracLeft, double fracTop, double sizePx, double phase) {
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

  Widget _logCell(double w, String text, {bool bold = false, bool small = false}) {
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

  Widget _buildProfileCard(double w, double h, EnrollmentController controller, BuildContext context) {
    final cardRadius = BorderRadius.circular(w * 0.023);
    final expandedPanelColor = const Color(0xFF092238).withOpacity(0.5);
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller.selfieImageBytes,
        controller.idController,
        controller.usernameController,
      ]),
      builder: (context, _) {
        final selfieImage = controller.selfieImageBytes.value;
        final displayName = controller.usernameController.text;
        final displayId = controller.idController.text;

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
                      onTap: controller.takeSelfie,
                      child: Container(
                        width: w * 0.11,
                        height: w * 0.11,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.85),
                            width: 3,
                          ),
                          gradient: selfieImage == null
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFF3FA9F5), Color(0xFF1B75BB)],
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
                            ? Builder(
                                builder: (_) {
                                  final initials = _initialsFromName(displayName);
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
                              onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
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
                                      employeeId: displayId.isNotEmpty ? displayId : employeeId,
                                      employeeName: displayName.isNotEmpty ? displayName : employeeName,
                                      siteId: siteId,
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
                                    Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: w * 0.013,
                                        vertical: h * 0.004,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1D7CFF),
                                        borderRadius: BorderRadius.circular(w * 0.013),
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
      },
    );
  }

  Widget _buildBottomRow(double w, double h, EnrollmentController controller) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEnrollmentGuide(w, h, controller),
          SizedBox(width: w * 0.010),
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
                _buildFingerprintPreview(w, h, controller),
              ],
            ),
          ),
          SizedBox(width: w * 0.010),
          _buildStatusPanel(w, h, controller),
        ],
      ),
    );
  }

  Widget _buildEnrollmentGuide(double w, double h, EnrollmentController controller) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.showForm,
      builder: (context, showForm, _) {
      if (showForm) {
        return _buildEnrollmentForm(w, h, controller);
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
              isEditMode ? 'Update Enrollment' : 'Enrollment Guide',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: w * 0.012,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: h * 0.024),
            Text(
              isEditMode
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
              onTap: () => controller.showForm.value = true,
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
      },
    );
  }

  Widget _buildEnrollmentForm(double w, double h, EnrollmentController controller) {
    final readOnly = isEditMode;
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
            isEditMode ? 'Edit Employee Details' : 'Employee Details',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.012,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: h * 0.020),
          _buildTextField(w, h, 'Employee ID', controller.idController, readOnly: readOnly),
          SizedBox(height: h * 0.016),
          _buildTextField(w, h, 'Username', controller.usernameController, readOnly: readOnly),
        ],
      ),
    );
  }

  Widget _buildTextField(double w, double h, String label, TextEditingController controller, {bool readOnly = false}) {
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

  Widget _buildFingerprintPreview(double w, double h, EnrollmentController controller) {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: controller.lastFingerprintImage,
      builder: (context, lastFingerprintImage, _) {
      return Container(
        width: w * 0.16,
        padding: EdgeInsets.all(w * 0.008),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * 0.022),
        ),
        child: Center(
          child: lastFingerprintImage != null
              ? Image.memory(
                  lastFingerprintImage,
                  fit: BoxFit.contain,
                )
              : Image.asset(
                  'assets/images/Finger Print Icon.png',
                  fit: BoxFit.contain,
                ),
        ),
      );
      },
    );
  }

  Widget _buildStatusPanel(double w, double h, EnrollmentController controller) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildThumbStatus(w, h, controller, title: 'LEFT THUMB STATUS'),
          SizedBox(height: h * 0.018),
          _buildThumbStatus(w, h, controller, title: 'RIGHT THUMB STATUS', isRight: true),
          const Spacer(),
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
                child: _buildActionButton(
                  w,
                  h,
                  label: 'SAVE',
                  color: const Color(0xFF44D980),
                  onTap: controller.saveEnrollment,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThumbStatus(double w, double h, EnrollmentController controller,
      {required String title, bool isRight = false}) {
    final scanNotifier = isRight ? controller.rightThumbScans : controller.leftThumbScans;
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
            Text(
              '$scans/$maxScans',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: w * 0.010,
                color: Colors.white.withOpacity(0.7),
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
                    color: isActive ? const Color(0xFF39BF54) : Colors.grey.withOpacity(0.55),
                    border: isActive ? Border.all(color: Colors.white, width: 2) : null,
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

  Widget _buildActionButton(double w, double h, {required String label, required Color color, VoidCallback? onTap}) {
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

  String _initialsFromName(String name) {
    if (name.isEmpty) return '';
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }
    return (parts[0].substring(0, 1) + parts[parts.length - 1].substring(0, 1)).toUpperCase();
  }
}
