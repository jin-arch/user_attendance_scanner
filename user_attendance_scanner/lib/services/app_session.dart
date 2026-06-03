import 'package:shared_preferences/shared_preferences.dart';

/// Session flags for site setup flow (survives tab refresh; cleared with site prefs).
abstract final class AppSession {
  static const String _setupCompletedKey = 'initial_site_setup_completed_v1';
  static const String _dataLoadedKey = 'initial_site_data_loaded_v1';
  static const String _selectedSiteIdKey = 'selected_site_id_v1';
  static const String _selectedSiteNameKey = 'selected_site_name_v1';

  static bool initialSiteSetupCompleted = false;
  /// True after the first full API→local DB load finished (skip loading screen on reopen).
  static bool initialSiteDataLoaded = false;
  static String? cachedSelectedSiteId;
  static String? cachedSelectedSiteName;

  static Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    initialSiteSetupCompleted = prefs.getBool(_setupCompletedKey) ?? false;
    initialSiteDataLoaded =
        prefs.getBool(_dataLoadedKey) ?? initialSiteSetupCompleted;
    cachedSelectedSiteId = prefs.getString(_selectedSiteIdKey);
    cachedSelectedSiteName = prefs.getString(_selectedSiteNameKey);
  }

  static Future<void> saveSelectedSite({
    required String siteId,
    String? siteName,
  }) async {
    cachedSelectedSiteId = siteId;
    cachedSelectedSiteName = siteName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedSiteIdKey, siteId);
    if (siteName != null && siteName.isNotEmpty) {
      await prefs.setString(_selectedSiteNameKey, siteName);
    }
  }

  static Future<void> clearSelectedSite() async {
    cachedSelectedSiteId = null;
    cachedSelectedSiteName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedSiteIdKey);
    await prefs.remove(_selectedSiteNameKey);
  }

  static Future<void> markSiteDataLoaded() async {
    initialSiteDataLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dataLoadedKey, true);
  }

  static Future<void> markSiteSetupCompleted() async {
    initialSiteSetupCompleted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupCompletedKey, true);
    await markSiteDataLoaded();
  }

  static Future<void> resetSiteSetup() async {
    initialSiteSetupCompleted = false;
    initialSiteDataLoaded = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_setupCompletedKey);
    await prefs.remove(_dataLoadedKey);
  }
}
