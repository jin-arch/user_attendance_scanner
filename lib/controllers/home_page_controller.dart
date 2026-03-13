import 'dart:async';

import 'package:get/get.dart';

class HomePageController extends GetxController {
  final Rx<DateTime> now = DateTime.now().obs;
  final RxBool biometricConnected = false.obs;
  final RxBool isSearching = false.obs;
  final RxBool isScanning = false.obs;
  final RxString statusMessage = ''.obs;

  Timer? _clockTimer;

  @override
  void onInit() {
    super.onInit();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      now.value = DateTime.now();
    });
  }

  @override
  void onClose() {
    _clockTimer?.cancel();
    super.onClose();
  }

  void startSearching([String? status]) {
    isSearching.value = true;
    if (status != null) {
      statusMessage.value = status;
    }
  }

  void stopSearching([String? status]) {
    isSearching.value = false;
    if (status != null) {
      statusMessage.value = status;
    }
  }

  void setConnected(bool connected, {String? status}) {
    biometricConnected.value = connected;
    if (!connected) {
      isScanning.value = false;
    }
    if (status != null) {
      statusMessage.value = status;
    }
  }

  void setScanning(bool scanning) {
    isScanning.value = scanning;
  }

  void setStatus(String status) {
    statusMessage.value = status;
  }
}