// ignore_for_file: unused_field

import 'dart:async';
import 'package:flutter/foundation.dart';

class InactivityTimerService {
  static final InactivityTimerService _instance =
      InactivityTimerService._internal();
  Timer? _inactivityTimer;
  DateTime? _lastInteractionTime;
  bool _isActive = false;
  bool _isPaused = false;

  final ValueNotifier<bool> timerExpired = ValueNotifier<bool>(false);

  factory InactivityTimerService() {
    return _instance;
  }

  InactivityTimerService._internal();

  void start() {
    if (_isActive) return;
    _isActive = true;
    _isPaused = false;
    _lastInteractionTime = DateTime.now();
    _startTimer();
    debugPrint('[INACTIVITY_TIMER] Started 10-minute timer');
  }

  void pause() {
    if (!_isActive || _isPaused) return;
    _isPaused = true;
    _inactivityTimer?.cancel();
    debugPrint('[INACTIVITY_TIMER] Paused');
  }

  void resume() {
    if (!_isActive || !_isPaused) return;
    _isPaused = false;
    _lastInteractionTime = DateTime.now();
    _startTimer();
    debugPrint('[INACTIVITY_TIMER] Resumed');
  }

  void recordInteraction() {
    if (!_isActive || _isPaused) return;
    _lastInteractionTime = DateTime.now();
    timerExpired.value = false;
    debugPrint('[INACTIVITY_TIMER] Interaction recorded - timer reset');
  }

  void stop() {
    _inactivityTimer?.cancel();
    _isActive = false;
    _isPaused = false;
    _lastInteractionTime = null;
    timerExpired.value = false;
    debugPrint('[INACTIVITY_TIMER] Stopped');
  }

  void reset() {
    stop();
    start();
    debugPrint('[INACTIVITY_TIMER] Reset');
  }

  void _startTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer =
        Timer(const Duration(minutes: 10), () {
      timerExpired.value = true;
      debugPrint('[INACTIVITY_TIMER] 10-minute timer expired');
    });
  }

  bool get isActive => _isActive;

  bool get isPaused => _isPaused;

  bool get hasExpired => timerExpired.value;

  void dispose() {
    stop();
    timerExpired.dispose();
  }
}
