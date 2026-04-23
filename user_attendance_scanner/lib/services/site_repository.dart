import 'dart:async';
import '../models/site_model.dart';

abstract class SiteRepository {
  /// Fetch all available sites from API
  Future<List<Site>> fetchSites();
  
  /// Get cached sites from local storage
  Future<List<Site>> getCachedSites();
  
  /// Save sites to local cache
  Future<void> cacheSites(List<Site> sites);
  
  /// Get site by ID
  Future<Site?> getSiteById(String siteId);
  
  /// Clear site cache
  Future<void> clearCache();
}
