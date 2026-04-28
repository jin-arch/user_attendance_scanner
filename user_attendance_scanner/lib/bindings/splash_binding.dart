import 'package:get/get.dart';

import '../controllers/splash_controller.dart';

class SplashBinding extends Bindings {
  @override
  void dependencies() {
    if (Get.isRegistered<SplashController>()) {
      Get.delete<SplashController>(force: true);
    }
    Get.put(SplashController());
  }
}
