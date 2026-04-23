import 'dart:async';
import 'package:get/get.dart';

/// Legacy controller to maintain backward compatibility with existing home_page.dart
class LegacyHomePageController extends GetxController {
  final Rx<DateTime> now = DateTime.now().obs;
  final RxBool biometricConnected = false.obs;
  final RxBool isSearching = false.obs;
  final RxBool isScanning = false.obs;
  final RxString statusMessage = ''.obs;
  final RxString lastDbSyncLabel = ''.obs;

  Timer? _clockTimer;

  // Getter for backward compatibility
  RxString get status => statusMessage;

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

  void setLastDbSync([DateTime? syncedAt]) {
    final dateTime = syncedAt ?? DateTime.now();
    final hour12 = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    lastDbSyncLabel.value =
        'Last DB Sync: ${hour12.toString().padLeft(2, '0')}:$minute:$second $period';
  }
}
