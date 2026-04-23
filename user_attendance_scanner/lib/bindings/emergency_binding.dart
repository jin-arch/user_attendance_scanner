// Emergency fallback configuration
// This temporarily disables complex GetX setup to get app running
import 'package:get/get.dart';
import '../controllers/legacy_home_page_controller.dart';

class EmergencyBinding extends Bindings {
  @override
  void dependencies() {
    // Only register the essential controllers that work
    Get.lazyPut<LegacyHomePageController>(() => LegacyHomePageController());
  }
}
