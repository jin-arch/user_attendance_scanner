import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/connectivity_service.dart';
import '../services/inactivity_timer_service.dart';
import '../services/local_db.dart';
import '../services/offline_mode_sync_service.dart';
import '../services/pending_sync_service.dart';
import '../widgets/offline_mode_selection_modal.dart';
import 'employee_database_controller.dart';

class OfflineModeController extends GetxController {
  final _connectivityService = ConnectivityService();
  final _inactivityTimerService = InactivityTimerService();
  final _offlineModeSyncService = OfflineModeSyncService();

  final RxBool hasWiFi = false.obs;
  final RxBool hasInternet = false.obs;
  final RxBool isOfflineMode = true.obs;
  final RxBool showModeSelector = false.obs;
  final RxBool inDashboardOrEnrollment = false.obs;
  final RxBool isLoadingInitialData = false.obs;

  String _selectedSiteId = '';
  StreamSubscription? _connectivitySubscription;
  bool? _lastHadNetwork;
  bool? _lastHadWiFi;
  bool _presentingModeDialog = false;

  @override
  void onInit() {
    super.onInit();
    _initConnectivity();
    _setupTimerListener();
    unawaited(_bootstrapPersistedMode());
  }

  Future<void> _bootstrapPersistedMode() async {
    final persisted = await _offlineModeSyncService.loadPersistedMode();
    if (persisted == SyncMode.online) {
      isOfflineMode.value = false;
      _offlineModeSyncService.setMode(SyncMode.online);
    } else if (persisted == SyncMode.offline) {
      isOfflineMode.value = true;
      _offlineModeSyncService.setMode(SyncMode.offline);
    }
    await _updateConnectivityState(promptOnChange: false);
    if (!isOfflineMode.value && hasInternet.value) {
      unawaited(syncAllPendingNow());
    }
  }

  void _initConnectivity() {
    _connectivitySubscription =
        _connectivityService.onConnectivityChanged.listen((_) async {
      await _updateConnectivityState(promptOnChange: true);
    });

    unawaited(_updateConnectivityState(promptOnChange: false));
  }

  Future<void> refreshConnectivity() =>
      _updateConnectivityState(promptOnChange: false);

  Future<void> _updateConnectivityState({required bool promptOnChange}) async {
    final snapshot = await _connectivityService.getSnapshot();
    hasWiFi.value = snapshot.wifi;
    hasInternet.value = snapshot.hasNetwork;
    debugPrint(
      '[OFFLINE_MODE] network=${snapshot.hasNetwork} wifi=${snapshot.wifi} '
      'results=${snapshot.results} offlineMode=${isOfflineMode.value}',
    );

    final hadNetwork = _lastHadNetwork;
    final hadWiFi = _lastHadWiFi;
    _lastHadNetwork = snapshot.hasNetwork;
    _lastHadWiFi = snapshot.wifi;

    if (!promptOnChange) return;

    final networkLost = hadNetwork == true && !snapshot.hasNetwork;
    final networkAvailableNow = snapshot.hasNetwork && hadNetwork != true;

    if (networkLost) {
      _offlineModeSyncService.resetModeSelector();
      startOfflineMode();
      debugPrint('[OFFLINE_MODE] Network lost — switched to offline mode');
      return;
    }

    if (networkAvailableNow) {
      _offlineModeSyncService.resetModeSelector();
      startOnlineMode();
      debugPrint('[OFFLINE_MODE] Network available — switched to online mode');
      return;
    }

    if (snapshot.hasNetwork && !isOfflineMode.value) {
      unawaited(syncAllPendingNow());
      _refreshTimelogsInBackground();
    }
  }

  void _setupTimerListener() {
    _inactivityTimerService.timerExpired.addListener(() {
      if (_inactivityTimerService.timerExpired.value &&
          !inDashboardOrEnrollment.value &&
          !isLoadingInitialData.value) {
        unawaited(applyModeFromConnectivity());
        debugPrint(
          '[OFFLINE_MODE] Inactivity timer expired — re-applied mode from connectivity',
        );
      }
    });
  }

  void setSiteId(String siteId) {
    _selectedSiteId = siteId;
  }

  void startOfflineMode() {
    isOfflineMode.value = true;
    _offlineModeSyncService.setMode(SyncMode.offline);
    unawaited(_offlineModeSyncService.persistMode(SyncMode.offline));
    _startInactivityTimer();
    showModeSelector.value = false;
    debugPrint('[OFFLINE_MODE] Started offline mode');
  }

  void startOnlineMode() {
    isOfflineMode.value = false;
    _offlineModeSyncService.setMode(SyncMode.online);
    unawaited(_offlineModeSyncService.persistMode(SyncMode.online));
    _startInactivityTimer();
    showModeSelector.value = false;
    debugPrint('[OFFLINE_MODE] Started online mode');
    unawaited(syncAllPendingNow());
    _refreshTimelogsInBackground();
  }

  void _startInactivityTimer() {
    if (inDashboardOrEnrollment.value) return;
    _inactivityTimerService.start();
  }

  /// Upload every queued time-in/out (and HRIS queue) while Online mode is active.
  Future<void> syncAllPendingNow() async {
    if (_selectedSiteId.isEmpty || isOfflineMode.value) return;

    await refreshConnectivity();
    if (!hasInternet.value) {
      debugPrint('[OFFLINE_MODE] Pending upload skipped — no network');
      return;
    }

    if (!Get.isRegistered<PendingSyncService>()) {
      Get.put(PendingSyncService(), permanent: true);
    }

    try {
      final result = await Get.find<PendingSyncService>().flushAllPending(
        siteId: _selectedSiteId,
      );
      debugPrint(
        '[OFFLINE_MODE] Pending flush: synced=${result.synced} '
        'failed=${result.failed} remaining=${result.remaining}',
      );
      _refreshEmployeeDatabasePendingUi();
    } catch (e) {
      debugPrint('[OFFLINE_MODE] Pending flush failed: $e');
    }
  }

  void _refreshEmployeeDatabasePendingUi() {
    if (_selectedSiteId.isEmpty) return;
    final tag = 'employee_db_$_selectedSiteId';
    if (!Get.isRegistered<EmployeeDatabaseController>(tag: tag)) return;
    final controller = Get.find<EmployeeDatabaseController>(tag: tag);
    unawaited(controller.loadEmployeesWithPendingRecords());
  }

  void _refreshTimelogsInBackground() {
    if (_selectedSiteId.isEmpty || !hasInternet.value || isOfflineMode.value) {
      return;
    }
    Future.microtask(() async {
      try {
        final count = await LocalDb.syncTimelogsFromApi(_selectedSiteId);
        debugPrint('[OFFLINE_MODE] Refreshed $count timelog rows from API');
      } catch (e) {
        debugPrint('[OFFLINE_MODE] Timelog refresh failed: $e');
      }
    });
  }

  void recordInteraction() {
    if (!inDashboardOrEnrollment.value && !isLoadingInitialData.value) {
      if (!_inactivityTimerService.isActive) {
        _startInactivityTimer();
      } else {
        _inactivityTimerService.recordInteraction();
      }
    }
  }

  void setLoadingInitialData(bool loading) {
    isLoadingInitialData.value = loading;
    if (loading) {
      _inactivityTimerService.stop();
      debugPrint('[OFFLINE_MODE] Started initial data loading...');
    } else {
      debugPrint('[OFFLINE_MODE] Completed initial data loading');
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
    _inactivityTimerService.reset();
  }

  /// Picks Online when network is available, otherwise Offline (no dialog).
  Future<void> applyModeFromConnectivity() async {
    if (_presentingModeDialog) return;

    await refreshConnectivity();
    if (hasInternet.value) {
      startOnlineMode();
      debugPrint('[OFFLINE_MODE] Auto-selected online mode (network available)');
    } else {
      startOfflineMode();
      debugPrint('[OFFLINE_MODE] Auto-selected offline mode (no network)');
    }
  }

  /// Show offline/online mode dialog from any screen (Pending Records, Home, etc.).
  ///
  /// By default applies mode from connectivity without blocking the user.
  /// Pass [showPicker: true] when the user explicitly opens the mode picker.
  Future<void> presentModeSelectionDialog({
    bool force = false,
    bool showPicker = false,
  }) async {
    if (!force && isLoadingInitialData.value) return;
    if (_presentingModeDialog) return;

    await refreshConnectivity();

    if (!showPicker) {
      await applyModeFromConnectivity();
      return;
    }

    final ctx = Get.overlayContext ?? Get.context;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(presentModeSelectionDialog(force: force));
      });
      return;
    }

    _presentingModeDialog = true;
    try {
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogContext) {
          return OfflineModeSelectionModal(
            onOnlineSelected: () {
              Navigator.pop(dialogContext);
              startOnlineMode();
              dismissModeSelector();
            },
            onOfflineSelected: () {
              Navigator.pop(dialogContext);
              startOfflineMode();
              dismissModeSelector();
            },
            hasWiFi: hasWiFi.value,
            hasInternet: hasInternet.value,
          );
        },
      );
    } finally {
      _presentingModeDialog = false;
      dismissModeSelector();
    }
  }

  void requestModeSelection() {
    showModeSelector.value = true;
    unawaited(presentModeSelectionDialog(showPicker: true));
  }

  @override
  void onClose() {
    _connectivitySubscription?.cancel();
    super.onClose();
  }
}
