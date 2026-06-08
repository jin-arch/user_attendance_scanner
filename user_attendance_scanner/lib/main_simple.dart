import 'dart:io' show Platform;

import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:user_attendance_scanner/app/bindings/app_binding.dart';
import 'package:user_attendance_scanner/app/modules/home/views/dashboard_page.dart';
import 'package:user_attendance_scanner/app/modules/home/views/home_page.dart';
import 'package:user_attendance_scanner/app/modules/splash/bindings/splash_binding.dart';
import 'package:user_attendance_scanner/app/modules/splash/views/splash_page.dart';
import 'package:user_attendance_scanner/app/routes/app_routes.dart';
import 'package:user_attendance_scanner/app/routes/route_observer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    DevicePreview(
      enabled: !kReleaseMode && (Platform.isWindows || Platform.isMacOS),
      builder: (context) => const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      navigatorObservers: [routeObserver],
      debugShowCheckedModeBanner: false,
      title: 'Attendance Scanner - Biometric System',
      initialBinding: AppBinding(),
      initialRoute: AppRoutes.home,
      getPages: [
        GetPage(name: AppRoutes.home, page: () => HomePage()),
        GetPage(name: AppRoutes.dashboard, page: () => DashboardPage()),
        GetPage(
          name: AppRoutes.splash,
          page: () => const SplashPage(),
          binding: SplashBinding(),
        ),
      ],
    );
  }
}
