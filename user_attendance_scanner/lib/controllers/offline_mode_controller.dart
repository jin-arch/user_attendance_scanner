import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/connectivity_service.dart';
import '../services/inactivity_timer_service.dart';
import '../services/offline_mode_sync_service.dart';

class OfflineModeController extends GetxController {
  final _connectivityService = ConnectivityService();
  final _inactivityTimerService = InactivityTimerService();
  final _offlineModeSyncService = OfflineModeSyncService();

  final RxBool hasWiFi = false.obs;
  final RxBool isOfflineMode = true.obs;
  final RxBool showModeSelector = false.obs;
  final RxBool inDashboardOrEnrollment = false.obs;

  String _selectedSiteId = '';

  @override
  void onInit() {
    super.onInit();
    _initConnectivity();
    _setupTimerListener();
  }

  void _initConnectivity() {
    _connectivityService.onConnectivityChanged.listen((result) {
      hasWiFi.value = result.name == 'wifi';
      debugPrint('[OFFLINE_MODE] WiFi status: ${hasWiFi.value}');

      if (hasWiFi.value && isOfflineMode.value) {
        _offlineModeSyncService.resetModeSelector();
        showModeSelector.value = true;
        debugPrint('[OFFLINE_MODE] WiFi detected - showing mode selector');
      }
    });

    // Check initial WiFi status
    _checkWiFiStatus();
  }

  Future<void> _checkWiFiStatus() async {
    final isConnected = await _connectivityService.isWiFiConnected();
    hasWiFi.value = isConnected;
  }

  void _setupTimerListener() {
    _inactivityTimerService.timerExpired.addListener(() {
      if (_inactivityTimerService.timerExpired.value &&
          isOfflineMode.value &&
          !inDashboardOrEnrollment.value) {
        showModeSelector.value = true;
        debugPrint('[OFFLINE_MODE] Inactivity timer expired - showing mode selector');
      }
    });
  }

  void setSiteId(String siteId) {
    _selectedSiteId = siteId;
  }

  void startOfflineMode() {
    isOfflineMode.value = true;
    _offlineModeSyncService.setMode(SyncMode.offline);
    _inactivityTimerService.start();
    showModeSelector.value = false;
    debugPrint('[OFFLINE_MODE] Started offline mode');
  }

  void startOnlineMode() {
    isOfflineMode.value = false;
    _offlineModeSyncService.setMode(SyncMode.online);
    _inactivityTimerService.stop();
    showModeSelector.value = false;
    debugPrint('[OFFLINE_MODE] Started online mode');
  }

  void recordInteraction() {
    if (isOfflineMode.value && !inDashboardOrEnrollment.value) {
      _inactivityTimerService.recordInteraction();
    }
  }

  void pauseInactivityTimer() {
    _inactivityTimerService.pause();
  }

  void resumeInactivityTimer() {
    _inactivityTimerService.resume();
  }

  void setInDashboardOrEnrollment(bool value) {
    inDashboardOrEnrollment.value = value;
    if (value) {
      pauseInactivityTimer();
    } else {
      resumeInactivityTimer();
    }
  }

  void dismissModeSelector() {
    showModeSelector.value = false;
    if (isOfflineMode.value) {
      _inactivityTimerService.reset();
    }
  }

  @override
  void onClose() {
    _inactivityTimerService.dispose();
    _offlineModeSyncService.dispose();
    super.onClose();
  }
}
