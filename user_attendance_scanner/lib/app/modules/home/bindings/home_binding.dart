import 'package:get/get.dart';

import 'package:user_attendance_scanner/app/modules/home/controllers/dashboard_page_controller.dart';
import 'package:user_attendance_scanner/app/modules/home/controllers/legacy_home_page_controller.dart';
import 'package:user_attendance_scanner/app/modules/home/controllers/offline_mode_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    // DashboardPageController and LegacyHomePageController are already registered globally in AppBinding
    // This binding ensures they're available and can be found when needed
    if (!Get.isRegistered<DashboardPageController>()) {
      Get.lazyPut(() => DashboardPageController(), fenix: true);
    }
    if (!Get.isRegistered<LegacyHomePageController>()) {
      Get.lazyPut(() => LegacyHomePageController(), fenix: true);
    }
    
    // OfflineModeController is module-specific and should be registered here
    if (!Get.isRegistered<OfflineModeController>()) {
      Get.lazyPut(() => OfflineModeController(), fenix: true);
    }
  }
}
