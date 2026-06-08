import 'package:get/get.dart';
import 'package:user_attendance_scanner/app/modules/database/views/database_page.dart';
import 'package:user_attendance_scanner/app/modules/enrollment/bindings/enrollment_binding.dart';
import 'package:user_attendance_scanner/app/modules/enrollment/views/enrollment_page.dart';
import 'package:user_attendance_scanner/app/modules/home/views/dashboard_page.dart';
import 'package:user_attendance_scanner/app/modules/home/views/home_page.dart';
import 'package:user_attendance_scanner/app/modules/splash/bindings/splash_binding.dart';
import 'package:user_attendance_scanner/app/modules/splash/views/splash_page.dart';
import 'package:user_attendance_scanner/app/modules/time_logs/bindings/time_logs_binding.dart';
import 'package:user_attendance_scanner/app/modules/time_logs/views/logs_page.dart';

import 'app_routes.dart';

abstract class AppPages {
  static final pages = [
    GetPage(
      name: AppRoutes.splash,
      page: () => const SplashPage(),
      binding: SplashBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.home,
      page: () => HomePage(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.dashboard,
      page: () => DashboardPage(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.enrollment,
      page: () {
        final args = Get.arguments;
        final map = args is Map ? args : const <Object?, Object?>{};
        return EnrollmentPage(
          siteId: map['siteId']?.toString(),
          isEditMode: map['isEditMode'] == true,
          employeeId: map['employeeId']?.toString(),
          employeeName: map['employeeName']?.toString(),
        );
      },
      binding: EnrollmentBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.logs,
      page: () {
        final args = Get.arguments;
        final map = args is Map ? args : const <Object?, Object?>{};
        return LogsPage(siteId: map['siteId']?.toString());
      },
      binding: TimeLogsBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.database,
      page: () => const DatabasePage(),
      transition: Transition.rightToLeft,
    ),
  ];
}
