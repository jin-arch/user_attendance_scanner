import '../utils/hris_log.dart';
import 'connectivity_service.dart';
import 'offline_mode_sync_service.dart';

/// When to push local changes to the HRIS server.
class HrisPushPolicy {
  static final _connectivity = ConnectivityService();
  static final _mode = OfflineModeSyncService();

  /// User selected Online mode on the mode selector.
  static bool isOnlineUiMode() => _mode.isOnlineMode();

  /// HRIS upload only when the user picked Online mode on the mode selector.
  static Future<bool> shouldPushToHrisApi() async {
    if (!isOnlineUiMode()) {
      hrisLog('push skipped: Offline UI mode selected');
      return false;
    }

    final snapshot = await _connectivity.getSnapshot();
    if (snapshot.hasNetwork) {
      hrisLog(
        'push allowed: Online UI mode with network '
        '(wifi=${snapshot.wifi} types=${snapshot.results})',
      );
      return true;
    }
    hrisLog('push skipped: Online UI mode and no network');
    return false;
  }
}
