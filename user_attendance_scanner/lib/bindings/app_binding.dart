import 'package:get/get.dart';
import '../controllers/dashboard_page_controller.dart';
import '../controllers/home_page_controller.dart';
import '../controllers/legacy_home_page_controller.dart';
import '../services/site_repository.dart';
import '../services/employee_repository.dart';
import '../services/attendance_repository.dart';
import '../services/device_service.dart';
import '../services/site_repository_impl.dart';
import '../services/employee_repository_impl.dart';
import '../services/attendance_repository_impl.dart';
import '../services/device_service_impl.dart';
import '../controllers/home_page_bridge.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    // Register dependencies
    Get.lazyPut<DeviceService>(() => DeviceServiceImpl(), fenix: true);
    Get.lazyPut<SiteRepository>(() => SiteRepositoryImpl(), fenix: true);
    Get.lazyPut<EmployeeRepository>(() => EmployeeRepositoryImpl(), fenix: true);
    Get.lazyPut<AttendanceRepository>(() => AttendanceRepositoryImpl(), fenix: true);

    // Register controllers with dependencies
    Get.lazyPut(
      () => HomePageController(
        Get.find<SiteRepository>(),
        Get.find<EmployeeRepository>(),
        Get.find<AttendanceRepository>(),
        Get.find<DeviceService>(),
      ),
      fenix: true,
    );

    // Legacy controller still used by the current Views
    Get.lazyPut(() => LegacyHomePageController(), fenix: true);

    // Dashboard business logic/state helper for the legacy dashboard view
    Get.lazyPut(() => DashboardPageController(), fenix: true);

    // Bridge is optional, but kept for gradual migration
    Get.lazyPut(() => HomePageBridge(), fenix: true);
  }
}
