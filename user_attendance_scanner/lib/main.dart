// Simplified main.dart without complex architecture
import 'dart:io' show Platform;
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:user_attendance_scanner/routes/app_routes.dart';
import 'package:user_attendance_scanner/routes/route_observer.dart';

import 'bindings/app_binding.dart';
import 'views/dashboard_mvp_page.dart';
import 'views/home_mvp_page.dart';
import 'views/splash_page.dart';

import 'views/home_page.dart';
import 'views/dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Dependencies are registered via AppBinding on GetMaterialApp.
  
  if (!kIsWeb) {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
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
      useInheritedMediaQuery: previewEnabled,
      locale: previewEnabled ? DevicePreview.locale(context) : null,
      builder: previewEnabled ? DevicePreview.appBuilder : null,
      navigatorObservers: [routeObserver],
      debugShowCheckedModeBanner: false,
      title: 'HIRS - Human Resources Information System',
      initialBinding: AppBinding(),
      initialRoute: AppRoutes.legacyHome,
      getPages: [
        // Legacy UI (default)
        GetPage(name: AppRoutes.legacyHome, page: () => const HomePage()),
        GetPage(name: AppRoutes.legacyDashboard, page: () => const DashboardPage()),

        // MVP UI (kept for migration)
        GetPage(name: AppRoutes.splash, page: () => const SplashPage()),
        GetPage(name: AppRoutes.home, page: () => const HomeMvpPage()),
        GetPage(name: AppRoutes.dashboard, page: () => const DashboardMvpPage()),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
    );
  }
}