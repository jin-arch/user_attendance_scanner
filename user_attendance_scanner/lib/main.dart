// Simplified main.dart without complex architecture
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:user_attendance_scanner/routes/app_pages.dart';
import 'package:user_attendance_scanner/routes/app_routes.dart';
import 'package:user_attendance_scanner/routes/route_observer.dart';

import 'bindings/app_binding.dart';

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
      getPages: AppPages.pages,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
    );
  }
}
