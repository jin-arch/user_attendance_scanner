import 'package:get/get.dart';

import '../bindings/enrollment_binding.dart';
import '../bindings/splash_binding.dart';
import '../views/dashboard_page.dart';
import '../views/database_page.dart';
import '../views/enrollment_page.dart';
import '../views/home_page.dart';
import '../views/logs_page.dart';
import '../views/splash_page.dart';
import 'app_routes.dart';

abstract class AppPages {
  static final pages = [
    // Splash page
    GetPage(
      name: AppRoutes.splash,
      page: () => const SplashPage(),
      binding: SplashBinding(),
      transition: Transition.fadeIn,
    ),
    // Home page
    GetPage(
      name: AppRoutes.home,
      page: () => HomePage(),
      transition: Transition.rightToLeft,
    ),
    // Dashboard page
    GetPage(
      name: AppRoutes.dashboard,
      page: () => DashboardPage(),
      transition: Transition.rightToLeft,
    ),
    // Enrollment page
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
    // Logs page
    GetPage(
      name: AppRoutes.logs,
      page: () => const LogsPage(),
      transition: Transition.rightToLeft,
    ),
    // Database page
    GetPage(
      name: AppRoutes.database,
      page: () => const DatabasePage(),
      transition: Transition.rightToLeft,
    ),
    // Legacy UI routes
    GetPage(
      name: AppRoutes.legacyHome,
      page: () => HomePage(),
      transition: Transition.leftToRight,
    ),
    GetPage(
      name: AppRoutes.legacyDashboard,
      page: () => DashboardPage(),
      transition: Transition.leftToRight,
    ),
  ];
}
