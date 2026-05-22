// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/connectivity_service.dart';
import '../services/inactivity_timer_service.dart';
import '../services/offline_mode_sync_service.dart';
import '../services/pending_sync_service.dart';

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
      final wasWiFi = hasWiFi.value;
      hasWiFi.value = result.name == 'wifi';
      debugPrint('[OFFLINE_MODE] WiFi status: ${hasWiFi.value} (was: $wasWiFi)');

      // Show mode selector if WiFi is detected in offline mode
      if (hasWiFi.value && isOfflineMode.value) {
        _offlineModeSyncService.resetModeSelector();
        showModeSelector.value = true;
        debugPrint('[OFFLINE_MODE] WiFi detected - showing mode selector');
      }

      // Also show mode selector if WiFi is lost while in online mode
      if (!hasWiFi.value && !isOfflineMode.value && wasWiFi) {
        _offlineModeSyncService.resetModeSelector();
        showModeSelector.value = true;
        debugPrint('[OFFLINE_MODE] WiFi lost in online mode - showing mode selector');
      }

      if (hasWiFi.value && !isOfflineMode.value) {
        _syncPendingInBackground();
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
    _syncPendingInBackground();
  }

  void _syncPendingInBackground() {
    if (_selectedSiteId.isEmpty) return;
    if (!Get.isRegistered<PendingSyncService>()) return;

    Future.microtask(() async {
      try {
        final result = await Get.find<PendingSyncService>().syncAllPending(
          siteId: _selectedSiteId,
        );
        debugPrint(
          '[OFFLINE_MODE] Auto-sync pending: synced=${result.synced} failed=${result.failed}',
        );
      } catch (e) {
        debugPrint('[OFFLINE_MODE] Auto-sync pending failed: $e');
      }
    });
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
