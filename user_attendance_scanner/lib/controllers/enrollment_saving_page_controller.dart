import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

class EnrollmentSavingPageController extends GetxController
    with GetSingleTickerProviderStateMixin {
  EnrollmentSavingPageController({
    required this.saveFuture,
    this.timeout = const Duration(minutes: 5),
    this.onLocalSaved,
  });

  final Future<bool> saveFuture;
  final Duration timeout;
  final VoidCallback? onLocalSaved;

  Timer? _timeoutTimer;
  bool _completed = false;

  late final AnimationController pulseController;
  late final Animation<double> pulseScale;

  @override
  void onInit() {
    super.onInit();
    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(
        parent: pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _timeoutTimer = Timer(timeout, _onTimeout);
    unawaited(_watchSave());
  }

  Future<void> _watchSave() async {
    var saved = false;
    try {
      saved = await saveFuture;
    } catch (_) {
      saved = false;
    }

    if (isClosed || _completed) return;
    _finish(saved: saved);
  }

  void _onTimeout() {
    if (isClosed || _completed) return;
    _finish(timedOut: true);
  }

  void _finish({bool saved = false, bool timedOut = false}) {
    _completed = true;
    _timeoutTimer?.cancel();

    if (saved) {
      onLocalSaved?.call();
    }

    // Saving page is pushed with Get.to (a route), not an overlay.
    if (Get.key.currentState?.canPop() ?? false) {
      Get.back<void>();
    }
  }

  @override
  void onClose() {
    _timeoutTimer?.cancel();
    pulseController.dispose();
    super.onClose();
  }
}
