import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SuccessLoadingPageController extends GetxController
  with GetSingleTickerProviderStateMixin {
  SuccessLoadingPageController({
    this.message,
    this.employeeName,
    this.attendanceType,
    this.timestamp,
    required this.duration,
    this.onComplete,
  });

  final String? message;
  final String? employeeName;
  final String? attendanceType;
  final DateTime? timestamp;
  final Duration duration;
  final VoidCallback? onComplete;

  Timer? _completionTimer;
  late final AnimationController animationController;
  late final Animation<double> scaleAnimation;
  late final Animation<double> opacityAnimation;

  bool get hasEmployeeInfo => employeeName != null && attendanceType != null;

  bool get isTimeIn => (attendanceType?.toUpperCase().contains('IN') ?? true);

  Color get statusColor =>
      isTimeIn ? const Color(0xFF90EE90) : const Color(0xFF7A9BBD);

  String get statusText => isTimeIn ? 'TIME IN SUCCESSFUL' : 'TIME OUT SUCCESSFUL';

  String get formattedTime {
    final time = timestamp ?? DateTime.now();
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  String get formattedDate {
    final time = timestamp ?? DateTime.now();
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
    return '${months[time.month - 1]} ${time.day}, ${time.year}';
  }

  @override
  void onInit() {
    super.onInit();
    animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: animationController,
        curve: const Interval(0.3, 0.8, curve: Curves.easeIn),
      ),
    );

    animationController.forward();

    _completionTimer = Timer(duration, () {
      onComplete?.call();
    });
  }

  @override
  void onClose() {
    _completionTimer?.cancel();
    _completionTimer = null;
    animationController.dispose();
    super.onClose();
  }
}
