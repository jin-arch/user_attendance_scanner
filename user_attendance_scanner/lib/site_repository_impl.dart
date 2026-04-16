import 'dart:convert';
import 'dart:io';
import 'site_model.dart';
import 'site_repository.dart';

class SiteRepositoryImpl implements SiteRepository {
  static const String _siteApiUrl = 'https://fastdevs-api.com/HRIS_BIOMETRICS/public/api/v1/site/all';
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';

  @override
  Future<List<Site>> fetchSites() async {
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
        return sitesData.map((json) => Site.fromJson(json)).toList();
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
    // For now, return empty list - could implement SharedPreferences caching
    return [];
  }

  @override
  Future<void> cacheSites(List<Site> sites) async {
    // For now, no-op - could implement SharedPreferences caching
  }

  @override
  Future<Site?> getSiteById(String siteId) async {
    final sites = await fetchSites();
    try {
      return sites.firstWhere((site) => site.id == siteId);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> clearCache() async {
    // For now, no-op - could implement SharedPreferences clearing
  }

  String _basicAuth(String username, String password) {
    final token = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }
}