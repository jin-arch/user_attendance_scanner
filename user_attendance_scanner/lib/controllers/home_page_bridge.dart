import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'home_page_controller.dart';

/// Bridge controller that provides backward compatibility
/// while introducing GetX architecture gradually
class HomePageBridge extends GetxController {
  late HomePageController _coreController;

  // Bridge properties that mirror the old StatefulWidget state
  final isLoadingSites = false.obs;
  final selectedSiteId = Rx<String?>(null);
  final biometricConnected = false.obs;
  final isScanning = false.obs;
  final statusMessage = ''.obs;
  final now = DateTime.now().obs;

  @override
  void onInit() {
    super.onInit();
    
    // Try to get the core controller if it's registered
    try {
      _coreController = Get.find<HomePageController>();
      
      // Bind core controller state to bridge state
      _bindCoreController();
    } catch (e) {
      // Core controller not available, use legacy mode
      debugPrint('Core controller not available, using legacy mode: $e');
      _initLegacyMode();
    }
  }

  void _bindCoreController() {
    // Sync core controller observables with bridge observables
    ever(_coreController.isLoadingSites, (loading) => isLoadingSites.value = loading);
    ever(_coreController.selectedSite, (site) => selectedSiteId.value = site?.id ?? '');
    ever(_coreController.isConnected, (connected) => biometricConnected.value = connected);
    ever(_coreController.isScanning, (scanning) => isScanning.value = scanning);
    ever(_coreController.statusMessage, (status) => statusMessage.value = status);
    ever(_coreController.now, (time) => now.value = time);
  }

  void _initLegacyMode() {
    // Initialize timer for legacy mode
    Timer.periodic(const Duration(seconds: 1), (_) {
      now.value = DateTime.now();
    });
  }

  // Bridge methods that delegate to core controller when available
  Future<void> loadSites() async {
    try {
      await _coreController.loadSites();
    } catch (e) {
      debugPrint('Failed to load sites via core controller: $e');
    }
  }

  Future<void> connectDevice() async {
    try {
      await _coreController.connectDevice();
    } catch (e) {
      debugPrint('Failed to connect device via core controller: $e');
    }
  }

  Future<void> startScanning() async {
    try {
      await _coreController.startScanning();
    } catch (e) {
      debugPrint('Failed to start scanning via core controller: $e');
    }
  }

  void setStatus(String status) {
    statusMessage.value = status;
    try {
      _coreController.setStatus(status);
    } catch (e) {
      // Legacy fallback
    }
  }

  void setConnected(bool connected) {
    biometricConnected.value = connected;
    try {
      _coreController.isConnected.value = connected;
    } catch (e) {
      // Legacy fallback
    }
  }

  void setScanning(bool scanning) {
    isScanning.value = scanning;
    try {
      _coreController.isScanning.value = scanning;
    } catch (e) {
      // Legacy fallback
    }
  }
}
