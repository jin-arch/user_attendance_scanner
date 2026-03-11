import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();
  bool _biometricConnected = false;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
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
                          _buildStatusButton(
                            label: 'SEARCH MODE',
                            textColor: Colors.white,
                            cardW: cardW,
                            cardH: cardH,
                          ),
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
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'CEORUSE',
          fontSize: cardW * 0.016,
          color: textColor,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
