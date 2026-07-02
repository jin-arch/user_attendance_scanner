import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:user_attendance_scanner/app/modules/database/controllers/employee_database_controller.dart';
import 'package:user_attendance_scanner/app/data/services/app_session.dart';
import 'package:user_attendance_scanner/app/data/services/connectivity_service.dart';
import 'package:user_attendance_scanner/app/data/services/hris_push_policy.dart';
import 'package:user_attendance_scanner/app/data/services/offline_mode_sync_service.dart';
import 'package:user_attendance_scanner/app/data/services/pending_sync_service.dart';

/// Background upload of all pending attendance when network + Online UI mode.
class PendingUploadService extends GetxService {
  final _connectivity = ConnectivityService();
  final _mode = OfflineModeSyncService();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  VoidCallback? _modeListener;
  Timer? _debounce;
  bool _flushInProgress = false;

  final isUploading = false.obs;

  @override
  void onInit() {
    super.onInit();
    _bindListeners();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await AppSession.loadFromStorage();
    await flushAllPending(reason: 'startup');
  }

  void _bindListeners() {
    _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((_) {
      _scheduleFlush('connectivity');
    });

    _modeListener ??= () => _scheduleFlush('mode_changed');
    _mode.modeChanged.removeListener(_modeListener!);
    _mode.modeChanged.addListener(_modeListener!);
  }

  /// Call when user selects or restores a site (keeps uploads scoped when possible).
  void notifySiteChanged(String siteId) {
    if (siteId.trim().isEmpty) return;
    _scheduleFlush('site_changed');
  }

  void _scheduleFlush(String reason) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(flushAllPending(reason: reason));
    });
  }

  /// Resolves site from argument, [AppSession], or flushes all sites when unknown.
  Future<({int synced, int failed, int remaining})> flushAllPending({
    String? siteId,
    String reason = 'manual',
  }) async {
    if (_flushInProgress) {
      debugPrint('[PENDING_UPLOAD] Skip ($reason) — flush already running');
      return (synced: 0, failed: 0, remaining: 0);
    }

    if (!HrisPushPolicy.isOnlineUiMode()) {
      debugPrint('[PENDING_UPLOAD] Skip ($reason) — Offline UI mode');
      return (synced: 0, failed: 0, remaining: 0);
    }

    if (!await _connectivity.hasNetworkConnection()) {
      debugPrint('[PENDING_UPLOAD] Skip ($reason) — no network');
      return (synced: 0, failed: 0, remaining: 0);
    }

    final resolvedSite = _resolveSiteId(siteId);
    _flushInProgress = true;
    isUploading.value = true;

    try {
      if (!Get.isRegistered<PendingSyncService>()) {
        Get.put(PendingSyncService(), permanent: true);
      }

      debugPrint(
        '[PENDING_UPLOAD] Flush start reason=$reason site=${resolvedSite ?? "(all)"}',
      );

      final result = await Get.find<PendingSyncService>().flushAllPending(
        siteId: resolvedSite,
      );

      debugPrint(
        '[PENDING_UPLOAD] Flush done reason=$reason synced=${result.synced} '
        'failed=${result.failed} remaining=${result.remaining}',
      );

      _refreshPendingRecordsUi(resolvedSite);
      return result;
    } catch (e, st) {
      debugPrint('[PENDING_UPLOAD] Flush failed ($reason): $e');
      debugPrintStack(stackTrace: st, label: 'PENDING_UPLOAD');
      return (synced: 0, failed: 0, remaining: 0);
    } finally {
      isUploading.value = false;
      _flushInProgress = false;
    }
  }

  String? _resolveSiteId(String? siteId) {
    final fromArg = siteId?.trim();
    if (fromArg != null && fromArg.isNotEmpty) return fromArg;
    final fromSession = AppSession.cachedSelectedSiteId?.trim();
    if (fromSession != null && fromSession.isNotEmpty) return fromSession;
    return null;
  }

  void _refreshPendingRecordsUi(String? siteId) {
    if (siteId == null || siteId.isEmpty) return;
    final tag = 'employee_db_$siteId';
    debugPrint('[PENDING_UPLOAD] Refreshing UI for site=$siteId tag=$tag');
    if (!Get.isRegistered<EmployeeDatabaseController>(tag: tag)) {
      debugPrint('[PENDING_UPLOAD] Controller not registered with tag=$tag');
      return;
    }
    final controller = Get.find<EmployeeDatabaseController>(tag: tag);
    unawaited(controller.loadEmployeesWithPendingRecords());
    final employeeId = controller.selectedEmployeeId.value;
    if (employeeId.isNotEmpty) {
      unawaited(
        controller.loadPendingRecordsForEmployee(
          employeeId: employeeId,
          employeeName: controller.selectedEmployeeName.value,
        ),
      );
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    _connectivitySub?.cancel();
    if (_modeListener != null) {
      _mode.modeChanged.removeListener(_modeListener!);
    }
    super.onClose();
  }
}
