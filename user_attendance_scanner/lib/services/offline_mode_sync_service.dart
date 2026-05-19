import 'package:flutter/foundation.dart';

enum SyncMode { online, offline }

class OfflineModeSyncService {
  static final OfflineModeSyncService _instance =
      OfflineModeSyncService._internal();

  SyncMode _currentMode = SyncMode.offline;
  bool _hasShownModeSelector = false;

  final ValueNotifier<SyncMode> modeChanged = ValueNotifier<SyncMode>(SyncMode.offline);

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

  Future<void> dispose() async {
    await modeChanged.dispose();
  }
}
