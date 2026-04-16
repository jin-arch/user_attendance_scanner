// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';

class SuccessLoadingPage extends StatefulWidget {
  const SuccessLoadingPage({
    super.key,
    this.message,
    this.employeeName,
    this.attendanceType,
    this.timestamp,
    this.duration = const Duration(seconds: 2),
    this.onComplete,
  });

  final String? message;
  final String? employeeName;
  final String? attendanceType;
  final DateTime? timestamp;
  final Duration duration;
  final VoidCallback? onComplete;

  @override
  State<SuccessLoadingPage> createState() => _SuccessLoadingPageState();
}

class _SuccessLoadingPageState extends State<SuccessLoadingPage>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 0.8, curve: Curves.easeIn),
    ));

    _controller.forward();

    Timer(widget.duration, () {
      if (mounted && widget.onComplete != null) {
        widget.onComplete!();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final time = widget.timestamp ?? DateTime.now();
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  String get _formattedDate {
    final time = widget.timestamp ?? DateTime.now();
    final months = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];
    return '${months[time.month - 1]} ${time.day}, ${time.year}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final hasEmployeeInfo = widget.employeeName != null && widget.attendanceType != null;
    final isTimeIn = (widget.attendanceType?.toUpperCase().contains('IN') ?? true);
    final statusColor = isTimeIn ? const Color(0xFF90EE90) : const Color(0xFF7A9BBD);
    final statusText = isTimeIn ? 'TIME IN SUCCESSFUL' : 'TIME OUT SUCCESSFUL';

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
            padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: h * 0.04),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(w * 0.04),
                border: Border.all(
                  color: hasEmployeeInfo ? statusColor.withOpacity(0.5) : const Color(0xFF4A90B8).withOpacity(0.5),
                  width: hasEmployeeInfo ? 2 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: hasEmployeeInfo ? statusColor.withOpacity(0.2) : Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF1A3A52),
                    const Color(0xFF234A6B).withOpacity(0.9),
                    const Color(0xFF1A3A52),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
              child: Center(
                child: hasEmployeeInfo 
                  ? _buildEmployeeUI(w, h, statusColor, statusText)
                  : _buildSimpleUI(w, h),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeUI(double w, double h, Color statusColor, String statusText) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: w * 0.15,
                  height: w * 0.15,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor, width: 3),
                  ),
                  child: Icon(Icons.check, color: statusColor, size: w * 0.08),
                ),
              ),
              SizedBox(height: h * 0.04),
              Text(statusText, style: TextStyle(
                color: statusColor, fontSize: w * 0.035, fontWeight: FontWeight.bold, letterSpacing: 2)),
              SizedBox(height: h * 0.025),
              Text(widget.employeeName!.toUpperCase(), style: TextStyle(
                color: Colors.white, fontSize: w * 0.045, fontWeight: FontWeight.w600, letterSpacing: 1)),
              SizedBox(height: h * 0.015),
              Text(_formattedTime, style: TextStyle(
                color: Colors.white.withOpacity(0.9), fontSize: w * 0.065, 
                fontWeight: FontWeight.bold, fontFamily: 'CEORUSE')),
              SizedBox(height: h * 0.01),
              Text(_formattedDate, style: TextStyle(
                color: Colors.white.withOpacity(0.7), fontSize: w * 0.022, letterSpacing: 1.5)),
              SizedBox(height: h * 0.06),
              SizedBox(width: w * 0.08, height: w * 0.08,
                child: CircularProgressIndicator(color: statusColor.withOpacity(0.7), strokeWidth: 2)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSimpleUI(double w, double h) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: w * 0.7,
              padding: EdgeInsets.all(w * 0.06),
              decoration: BoxDecoration(
                color: const Color(0xFF0A2240).withOpacity(0.95),
                borderRadius: BorderRadius.circular(w * 0.04),
                border: Border.all(color: const Color(0xFF3FA9F5).withOpacity(0.5), width: 2),
                boxShadow: [BoxShadow(
                  color: const Color(0xFF3FA9F5).withOpacity(0.3), blurRadius: 20, spreadRadius: 5)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: w * 0.18, height: w * 0.18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF44D980), Color(0xFF2E9C5B)]),
                      boxShadow: [BoxShadow(
                        color: const Color(0xFF44D980).withOpacity(0.4), blurRadius: 15, spreadRadius: 3)],
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 40),
                  ),
                  SizedBox(height: h * 0.03),
                  const Text('SUCCESS!', style: TextStyle(
                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, 
                    fontFamily: 'TRTCENZODEMO', letterSpacing: 2)),
                  SizedBox(height: h * 0.02),
                  if (widget.message != null)
                    Text(widget.message!, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Poppins')),
                  SizedBox(height: h * 0.03),
                  const SizedBox(width: 40, height: 40,
                    child: CircularProgressIndicator(color: Color(0xFF3FA9F5), strokeWidth: 3)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
