import 'package:get/get.dart';

import 'package:user_attendance_scanner/app/modules/splash/controllers/splash_controller.dart';

class SplashBinding extends Bindings {
  @override
  void dependencies() {
    if (Get.isRegistered<SplashController>()) {
      Get.delete<SplashController>(force: true);
    }
    Get.put(SplashController());
  }
}
