import 'package:flutter/foundation.dart';

enum SyncMode { online, offline }

class OfflineModeSyncService {
  static final OfflineModeSyncService _instance =
      OfflineModeSyncService._internal();

  SyncMode _currentMode = SyncMode.offline;
  bool _hasShownModeSelector = false;
  bool _isSyncing = false;

  final ValueNotifier<SyncMode> modeChanged = ValueNotifier<SyncMode>(SyncMode.offline);
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);

  factory OfflineModeSyncService() {
    return _instance;
  }

  OfflineModeSyncService._internal();

  void setMode(SyncMode mode) {
    if (_currentMode == mode) return;
    _currentMode = mode;
    modeChanged.value = mode;
    _hasShownModeSelector = false;
    debugPrint('[OFFLINE_MODE_SYNC] Mode changed to: ${mode.name}');
  }

  SyncMode getMode() => _currentMode;

  bool isOnlineMode() => _currentMode == SyncMode.online;

  bool isOfflineMode() => _currentMode == SyncMode.offline;

  void setHasShownModeSelector(bool shown) {
    _hasShownModeSelector = shown;
  }

  bool hasShownModeSelector() => _hasShownModeSelector;

  void resetModeSelector() {
    _hasShownModeSelector = false;
  }

  /// Mark that a sync operation has started
  void startSync() {
    _isSyncing = true;
    isSyncingNotifier.value = true;
    debugPrint('[OFFLINE_MODE_SYNC] Sync operation started');
  }

  /// Mark that a sync operation has completed
  void completeSync() {
    _isSyncing = false;
    isSyncingNotifier.value = false;
    debugPrint('[OFFLINE_MODE_SYNC] Sync operation completed');
  }

  /// Check if sync is currently in progress
  bool isSyncing() => _isSyncing;

  /// Watch sync status
  ValueNotifier<bool> getSyncingNotifier() => isSyncingNotifier;

  void dispose() {
    modeChanged.dispose();
    isSyncingNotifier.dispose();
  }
}
