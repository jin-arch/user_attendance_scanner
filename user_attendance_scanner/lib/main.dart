// Simplified main.dart without complex architecture
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:user_attendance_scanner/routes/app_routes.dart';
import 'package:user_attendance_scanner/routes/route_observer.dart';

import 'bindings/app_binding.dart';
import 'bindings/enrollment_binding.dart';
import 'bindings/splash_binding.dart';
import 'views/splash_page.dart';

import 'views/home_page.dart';
import 'views/dashboard_page.dart';
import 'views/enrollment_page.dart';
import 'views/logs_page.dart';
import 'views/database_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Dependencies are registered via AppBinding on GetMaterialApp.
  
  if (!kIsWeb) {
    try {
      final target = defaultTargetPlatform;
      final isSupportedPlatform = target == TargetPlatform.android ||
          target == TargetPlatform.iOS ||
          target == TargetPlatform.windows ||
          target == TargetPlatform.linux ||
          target == TargetPlatform.macOS;

      if (isSupportedPlatform) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } catch (_) {}
  }

  runApp(
    DevicePreview(
      enabled: kDebugMode,
      builder: (context) => const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final previewEnabled = kDebugMode;

    return GetMaterialApp(
      locale: previewEnabled ? DevicePreview.locale(context) : null,
      builder: previewEnabled ? DevicePreview.appBuilder : null,
      navigatorObservers: [routeObserver],
      debugShowCheckedModeBanner: false,
      title: 'Attendance Scanner - Biometric System',
      initialBinding: AppBinding(),
      initialRoute: AppRoutes.home,
      getPages: [
        // Refactored UI (using controllers and services)
        GetPage(name: AppRoutes.home, page: () => HomePage()),
        GetPage(name: AppRoutes.dashboard, page: () => DashboardPage()),
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
        ),
        GetPage(name: AppRoutes.logs, page: () => const LogsPage()),
        GetPage(name: AppRoutes.database, page: () => const DatabasePage()),

        // Legacy UI routes
        GetPage(name: AppRoutes.legacyHome, page: () => HomePage()),
        GetPage(name: AppRoutes.legacyDashboard, page: () => DashboardPage()),

        // Splash page
        GetPage(
          name: AppRoutes.splash,
          page: () => const SplashPage(),
          binding: SplashBinding(),
        ),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
    );
  }
}
