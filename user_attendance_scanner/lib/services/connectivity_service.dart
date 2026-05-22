import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  final Connectivity _connectivity = Connectivity();

  factory ConnectivityService() {
    return _instance;
  }

  ConnectivityService._internal();

  Stream<ConnectivityResult> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;

  Future<bool> isWiFiConnected() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result == ConnectivityResult.wifi;
    } catch (e) {
      debugPrint('[CONNECTIVITY] Error checking WiFi: $e');
      return false;
    }
  }

  Future<bool> isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      debugPrint('[CONNECTIVITY] Error checking connectivity: $e');
      return false;
    }
  }

  Future<ConnectivityResult> getConnectivityStatus() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result;
    } catch (e) {
      debugPrint('[CONNECTIVITY] Error getting status: $e');
      return ConnectivityResult.none;
    }
  }
}
