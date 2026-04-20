import 'package:get/get.dart';
import '../controllers/dashboard_page_controller.dart';
import '../controllers/home_page_controller.dart';
import '../legacy_home_page_controller.dart';
import '../site_repository.dart';
import '../employee_repository.dart';
import '../attendance_repository.dart';
import '../device_service.dart';
import '../site_repository_impl.dart';
import '../employee_repository_impl.dart';
import '../attendance_repository_impl.dart';
import '../device_service_impl.dart';
import '../home_page_bridge.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    // Services
    Get.lazyPut<DeviceService>(() => DeviceServiceImpl(), fenix: true);

    // Repositories
    Get.lazyPut<SiteRepository>(() => SiteRepositoryImpl(), fenix: true);
    Get.lazyPut<EmployeeRepository>(() => EmployeeRepositoryImpl(), fenix: true);
    Get.lazyPut<AttendanceRepository>(() => AttendanceRepositoryImpl(), fenix: true);

    // Presenter/Controller (GetX)
    Get.lazyPut<HomePageController>(
      () => HomePageController(
        Get.find<SiteRepository>(),
        Get.find<EmployeeRepository>(),
        Get.find<AttendanceRepository>(),
        Get.find<DeviceService>(),
      ),
      fenix: true,
    );

    // Legacy controller still used by the current Views.
    Get.lazyPut<LegacyHomePageController>(() => LegacyHomePageController(), fenix: true);

    // Dashboard business logic/state helper for the legacy dashboard view.
    Get.lazyPut<DashboardPageController>(() => DashboardPageController(), fenix: true);

    // Bridge is optional, but kept for gradual migration.
    Get.lazyPut<HomePageBridge>(() => HomePageBridge(), fenix: true);
  }
}