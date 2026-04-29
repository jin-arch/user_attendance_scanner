import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class LoadingPageController extends GetxController {
  LoadingPageController({
    required this.onFinish,
    this.loadFuture,
    this.progressListenable,
    this.stayOnScreen = false,
  });

  final Future<void>? loadFuture;
  final ValueListenable<double>? progressListenable;
  final VoidCallback onFinish;
  final bool stayOnScreen;

  final RxInt progress = 0.obs;

  Timer? _fallbackTimer;
  VoidCallback? _progressListener;
  bool _workComplete = false;
  bool _isFinishing = false;
  double _lastProgress = 0.0;

  @override
  void onInit() {
    super.onInit();

    if (progressListenable != null) {
      _progressListener = () {
        final value = progressListenable!.value;
        final clamped = value.clamp(0.0, 1.0).toDouble();
        if (clamped <= _lastProgress) return;
        _lastProgress = clamped;
        _setProgress((clamped * 100).round().clamp(0, 100));
      };
      progressListenable!.addListener(_progressListener!);
      _progressListener!();
    } else {
      _startFallbackProgress();
    }

    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      if (loadFuture != null) {
        await loadFuture;
      } else {
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    } catch (e) {
      debugPrint('LoadingPage loadFuture error: $e');
    }

    if (isClosed) return;

    _workComplete = true;
    await _completeProgress();
  }

  void _startFallbackProgress() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (_workComplete || isClosed) return;
      final next = (progress.value + 1).clamp(0, 95);
      if (next > progress.value) {
        _setProgress(next);
      }
    });
  }

  void _detachProgressListener() {
    final listener = _progressListener;
    if (listener != null && progressListenable != null) {
      progressListenable!.removeListener(listener);
    }
    _progressListener = null;
  }

  void _setProgress(int value) {
    if (isClosed) return;
    final clamped = value.clamp(0, 100);
    if (clamped == progress.value) return;
    progress.value = clamped;
    update();
  }

  Future<void> _completeProgress() async {
    if (_isFinishing || isClosed) return;
    _isFinishing = true;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _detachProgressListener();

    _setProgress(100);
    if (stayOnScreen) return;

    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (isClosed) return;

    onFinish();
  }

  @override
  void onClose() {
    _detachProgressListener();
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    super.onClose();
  }
}