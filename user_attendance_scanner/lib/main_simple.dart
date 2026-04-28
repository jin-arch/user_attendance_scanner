// Simplified main.dart without complex architecture
import 'dart:io' show Platform;

import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'bindings/app_binding.dart';
import 'bindings/splash_binding.dart';
import 'routes/app_routes.dart';
import 'routes/route_observer.dart';

import 'views/splash_page.dart';

import 'views/home_page.dart';
import 'views/dashboard_page.dart';

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
      initialRoute: AppRoutes.legacyHome,
      getPages: [
        // Legacy UI (default)
        GetPage(name: AppRoutes.legacyHome, page: () => const HomePage()),
        GetPage(name: AppRoutes.legacyDashboard, page: () => const DashboardPage()),

        // MVP UI (kept for migration)
        GetPage(
          name: AppRoutes.splash,
          page: () => const SplashPage(),
          binding: SplashBinding(),
        ),
        GetPage(name: AppRoutes.home, page: () => const HomePage()),
        GetPage(name: AppRoutes.dashboard, page: () => const DashboardPage()),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
    );
  }
}
