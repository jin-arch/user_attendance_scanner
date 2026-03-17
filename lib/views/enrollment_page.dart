import 'package:flutter/material.dart';

class EnrollmentPage extends StatelessWidget {
  const EnrollmentPage({super.key});

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
                          _EnrollmentProfileCard(width: w, height: h),
                          SizedBox(width: w * 0.018),
                          Expanded(
                            child: Column(
                              children: [
                                _EnrollmentTimePanel(width: w, height: h),
                                SizedBox(height: h * 0.016),
                                _TodayLogCard(width: w, height: h),
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
                                  activeCount: 0,
                                ),
                                SizedBox(height: h * 0.018),
                                _StatusCard(
                                  width: w,
                                  height: h,
                                  title: 'RIGHT THUMB STATUS',
                                  activeCount: 3,
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _ActionButton(
                                        width: w,
                                        label: 'RESET',
                                        color: const Color(0xFF244D86),
                                      ),
                                    ),
                                    SizedBox(width: w * 0.012),
                                    Expanded(
                                      child: _ActionButton(
                                        width: w,
                                        label: 'SAVE',
                                        color: const Color(0xFF44D980),
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
  const _EnrollmentProfileCard({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(width * 0.03);

    return SizedBox(
      width: width * 0.58,
      child: Row(
        children: [
          _EmployeePhotoCard(width: width, height: height, radius: radius),
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
                    'WALLY REVILLAME',
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
                      '250727648',
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
                    'UI/UX Desinger',
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

class _EmployeePhotoCard extends StatelessWidget {
  const _EmployeePhotoCard({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width * 0.2,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8F8F8), Color(0xFFE7E0D8)],
              ),
            ),
          ),
          Positioned(
            left: width * 0.03,
            right: width * 0.03,
            bottom: 0,
            top: height * 0.035,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Icon(
                Icons.person,
                color: const Color(0xFFC7A165),
                size: width * 0.15,
              ),
            ),
          ),
        ],
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
  });

  final double width;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: width * 0.030,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
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