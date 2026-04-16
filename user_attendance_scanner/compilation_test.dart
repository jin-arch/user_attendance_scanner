// ignore_for_file: unused_import

// Compilation test - import all critical files
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// Import our models and controllers from lib
import 'lib/site_model.dart';
import 'lib/employee_model.dart';
import 'lib/attendance_model.dart';
import 'lib/legacy_home_page_controller.dart';
import 'lib/app_binding.dart';

// Import views
import 'lib/views/home_page.dart';
import 'lib/views/dashboard_page.dart';

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
      initialBinding: AppBinding(),
      home: HomePage(),
    );
  }
}