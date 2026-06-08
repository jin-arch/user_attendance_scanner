import 'package:get/get.dart';
import 'package:user_attendance_scanner/app/data/services/attendance_repository.dart';
import 'package:user_attendance_scanner/app/data/services/attendance_repository_impl.dart';
import 'package:user_attendance_scanner/app/data/services/device_service.dart';
import 'package:user_attendance_scanner/app/data/services/device_service_impl.dart';
import 'package:user_attendance_scanner/app/data/services/employee_repository.dart';
import 'package:user_attendance_scanner/app/data/services/employee_repository_impl.dart';
import 'package:user_attendance_scanner/app/data/services/pending_sync_service.dart';
import 'package:user_attendance_scanner/app/data/services/pending_upload_service.dart';
import 'package:user_attendance_scanner/app/data/services/scanner_registry_service.dart';
import 'package:user_attendance_scanner/app/data/services/site_repository.dart';
import 'package:user_attendance_scanner/app/data/services/site_repository_impl.dart';
import 'package:user_attendance_scanner/app/modules/home/controllers/dashboard_page_controller.dart';
import 'package:user_attendance_scanner/app/modules/home/controllers/legacy_home_page_controller.dart';

/// Global dependency injection (GetX) — data services + shared controllers.
class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeviceService>(() => DeviceServiceImpl(), fenix: true);
    Get.lazyPut<ScannerRegistryService>(
      () => ScannerRegistryService(),
      fenix: true,
    );

    Get.put<PendingSyncService>(PendingSyncService(), permanent: true);
    Get.put<PendingUploadService>(PendingUploadService(), permanent: true);

    Get.lazyPut<SiteRepository>(() => SiteRepositoryImpl(), fenix: true);
    Get.lazyPut<EmployeeRepository>(
      () => EmployeeRepositoryImpl(),
      fenix: true,
    );
    Get.lazyPut<AttendanceRepository>(
      () => AttendanceRepositoryImpl(),
      fenix: true,
    );

    Get.lazyPut(() => LegacyHomePageController(), fenix: true);
    Get.lazyPut(() => DashboardPageController(), fenix: true);
  }
}
