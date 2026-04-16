import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app_routes.dart';
import '../attendance_model.dart';
import '../employee_model.dart';

class DashboardMvpPage extends StatefulWidget {
  const DashboardMvpPage({super.key});

  @override
  State<DashboardMvpPage> createState() => _DashboardMvpPageState();
}

class _DashboardMvpPageState extends State<DashboardMvpPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) Get.offAllNamed(AppRoutes.home);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments;
    final map = args is Map ? args : const {};

    final employee = map['employee'] is Employee ? map['employee'] as Employee : null;
    final attendance = map['attendance'] is Attendance ? map['attendance'] as Attendance : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.offAllNamed(AppRoutes.home),
        ),
      ),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  employee != null ? Icons.check_circle : Icons.error,
                  size: 64,
                  color: employee != null ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 12),
                Text(
                  employee?.name ?? 'Not recognized',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  attendance?.type.displayName ?? 'No attendance recorded',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Get.offAllNamed(AppRoutes.home),
                  child: const Text('Back to scanner'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
