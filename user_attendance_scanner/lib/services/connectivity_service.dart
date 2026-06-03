import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Network reachability from [Connectivity] (interface type, not a live ping).
class ConnectivitySnapshot {
  const ConnectivitySnapshot({
    required this.results,
    required this.wifi,
    required this.hasNetwork,
  });

  final List<ConnectivityResult> results;
  final bool wifi;
  final bool hasNetwork;
}

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  final Connectivity _connectivity = Connectivity();

  factory ConnectivityService() {
    return _instance;
  }

  ConnectivityService._internal();

  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged.map(_normalizeResults);

  List<ConnectivityResult> _normalizeResults(dynamic value) {
    if (value is List<ConnectivityResult>) return value;
    if (value is ConnectivityResult) return <ConnectivityResult>[value];
    return const <ConnectivityResult>[ConnectivityResult.none];
  }

  static bool _isUsableNetwork(ConnectivityResult status) {
    switch (status) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.mobile:
      case ConnectivityResult.ethernet:
      case ConnectivityResult.vpn:
      case ConnectivityResult.other:
        return true;
      case ConnectivityResult.none:
      case ConnectivityResult.bluetooth:
        return false;
    }
  }

  Future<List<ConnectivityResult>> _currentResults() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _normalizeResults(result);
    } catch (e) {
      debugPrint('[CONNECTIVITY] checkConnectivity failed: $e');
      return const <ConnectivityResult>[ConnectivityResult.none];
    }
  }

  Future<ConnectivitySnapshot> getSnapshot() async {
    final results = await _currentResults();
    final wifi = results.contains(ConnectivityResult.wifi);
    final hasNetwork = results.any(_isUsableNetwork);
    return ConnectivitySnapshot(
      results: results,
      wifi: wifi,
      hasNetwork: hasNetwork,
    );
  }

  Future<bool> isWiFiConnected() async {
    final snapshot = await getSnapshot();
    return snapshot.wifi;
  }

  /// Wi‑Fi, mobile data, ethernet, or VPN — suitable for API sync.
  Future<bool> hasNetworkConnection() async {
    final snapshot = await getSnapshot();
    return snapshot.hasNetwork;
  }

  Future<bool> isOnline() async => hasNetworkConnection();

  Future<ConnectivityResult> getConnectivityStatus() async {
    try {
      final results = await _currentResults();
      if (results.isEmpty) return ConnectivityResult.none;
      if (results.contains(ConnectivityResult.wifi)) {
        return ConnectivityResult.wifi;
      }
      final usable = results.where(_isUsableNetwork);
      if (usable.isNotEmpty) return usable.first;
      return results.first;
    } catch (e) {
      debugPrint('[CONNECTIVITY] Error getting status: $e');
      return ConnectivityResult.none;
    }
  }
}
