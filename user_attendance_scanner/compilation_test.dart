// ignore_for_file: unused_import

// Compilation test - import all critical files
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:user_attendance_scanner/app/bindings/app_binding.dart';

// Import our models and controllers from lib

// Import views (new module paths)
import 'lib/app/modules/home/views/home_page.dart';

// Note: dashboard_page.dart isn't required for this compilation smoke test.



// Test basic instantiation
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Compilation Test',
      // No binding in this compilation smoke-test.
home: const HomePage(),



    );
  }
}