import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/site_model.dart';
import 'site_repository.dart';
import 'local_db.dart';

class SiteRepositoryImpl implements SiteRepository {
  static const String _siteApiUrl = 'https://fastdevs-api.com/HRIS_BIOMETRICS/public/api/v1/site/all';
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';

  @override
  Future<List<Site>> fetchSites() async {
    // OFFLINE-FIRST: Try to get from local cache first
    try {
      final cachedSites = await LocalDb.getSitesFromCache();
      if (cachedSites.isNotEmpty) {
        debugPrint('[SITE_REPO] Returning ${cachedSites.length} sites from OFFLINE cache');
        return cachedSites.map((json) => Site.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('[SITE_REPO] Error reading from cache: $e');
    }

    // Fallback to API if cache is empty
    debugPrint('[SITE_REPO] Cache empty, fetching from API');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);

    try {
      final request = await client.getUrl(Uri.parse(_siteApiUrl));
      request.headers.add('Authorization', _basicAuth(_apiUsername, _apiPassword));

      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> data = jsonDecode(responseBody);

        final List sitesData = data['data'] ?? [];
        final sites = sitesData.map((json) => Site.fromJson(json)).toList();
        
        // Save to cache for future use
        await LocalDb.saveSitesToCache(sitesData.cast<Map<String, dynamic>>());
        
        return sites;
      } else {
        throw Exception('Failed to fetch sites: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<Site>> getCachedSites() async {
    // OFFLINE-FIRST: Retrieve cached sites from local database
    try {
      final cachedSites = await LocalDb.getSitesFromCache();
      return cachedSites.map((json) => Site.fromJson(json)).toList();
    } catch (e) {
      debugPrint('[SITE_REPO] Error getting cached sites: $e');
      return [];
    }
  }

  @override
  Future<void> cacheSites(List<Site> sites) async {
    // Convert sites to Map format and save to cache
    final sitesData = sites.map((site) => {
      'site_id': site.id,
      'site_name': site.name,
    }).toList();
    await LocalDb.saveSitesToCache(sitesData);
  }

  @override
  Future<Site?> getSiteById(String siteId) async {
    // OFFLINE-FIRST: Try to get from cache first
    final cachedSites = await getCachedSites();
    try {
      return cachedSites.firstWhere((site) => site.id == siteId);
    } catch (e) {
      // Fallback to API if not in cache
      final sites = await fetchSites();
      try {
        return sites.firstWhere((site) => site.id == siteId);
      } catch (e) {
        return null;
      }
    }
  }

  @override
  Future<void> clearCache() async {
    await LocalDb.clearSelectedSite();
  }

  /// Save selected site with persistence
  Future<void> selectSite(Site site) async {
    await LocalDb.saveSelectedSite(
      siteId: site.id,
      siteName: site.name,
    );
  }

  /// Get the last selected site
  Future<Site?> getSelectedSite() async {
    final prefs = await LocalDb.getSelectedSite();
    if (prefs == null) return null;

    final siteId = prefs['selected_site_id']?.toString();
    final siteName = prefs['selected_site_name']?.toString();

    if (siteId == null) return null;

    return Site(
      id: siteId,
      name: siteName ?? 'Unknown Site',
    );
  }

  String _basicAuth(String username, String password) {
    final token = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }
}
