import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/employee_database_controller.dart';
import '../utils/responsive.dart';

class EmployeeDatabasePage extends StatelessWidget {
  final String siteId;
  final String? siteName;

  const EmployeeDatabasePage({
    super.key,
    required this.siteId,
    this.siteName,
  });

  @override
  Widget build(BuildContext context) {
    final tag = 'employee_db_$siteId';
    EmployeeDatabaseController controller;

    try {
      if (!Get.isRegistered<EmployeeDatabaseController>(tag: tag)) {
        Get.put(EmployeeDatabaseController(), tag: tag);
      }
      controller = Get.find<EmployeeDatabaseController>(tag: tag);
      controller.initializeForSite(siteId);
    } catch (e) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Pending Records init error: $e',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.redAccent,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Obx(
      () {
        final w = R.sizeOf(context).width;
        final h = R.sizeOf(context).height;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/Main BG.png'),
                fit: BoxFit.cover,
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context, w),
                  if (controller.isOfflineUiMode.value)
                    Padding(
                      padding: R.screenPadding(context),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(
                          R.wp(context, 0.012, min: 8, max: 14),
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(
                            R.wp(context, 0.010, max: 12),
                          ),
                          border: Border.all(
                            color: const Color(0xFFFF9800),
                          ),
                        ),
                        child: Text(
                          'Offline mode — records are saved locally. Tap the button below to choose Online mode and upload.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: R.font(context, 0.011, min: 10, max: 13),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (controller.errorMessage.value.isNotEmpty)
                    Padding(
                      padding: R.screenPadding(context),
                      child: Text(
                        controller.errorMessage.value,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: R.font(context, 0.012, min: 10, max: 14),
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  Expanded(
                    child: controller.selectedEmployeeId.value.isNotEmpty
                        ? _buildDetailView(context, controller, w, h)
                        : _buildEmployeeListView(context, controller, w, h),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

extension on EmployeeDatabasePage {
  Widget _buildHeader(BuildContext context, double w) {
    return Padding(
      padding: R.screenPadding(context),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Get.back<void>(),
            child: Container(
              padding: EdgeInsets.all(R.wp(context, 0.008, min: 6, max: 12)),
              decoration: BoxDecoration(
                color: const Color(0xFF0B2742).withOpacity(0.7),
                borderRadius: BorderRadius.circular(
                  R.wp(context, 0.012, max: 14),
                ),
              ),
              child: Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: R.font(context, 0.020, min: 18, max: 28),
              ),
            ),
          ),
          SizedBox(width: R.wp(context, 0.015, max: 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Pending Records',
                    style: TextStyle(
                      fontFamily: 'CEORUSE',
                      fontSize: R.font(context, 0.020, min: 14, max: 22),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Text(
                  siteName ?? 'Pending time in / time out uploads',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: R.font(context, 0.012, min: 10, max: 14),
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeListView(
    BuildContext context,
    EmployeeDatabaseController controller,
    double w,
    double h,
  ) {
    if (controller.isLoading.value) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (controller.employeesWithPending.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              color: const Color(0xFF44D980),
              size: R.wp(context, 0.060, min: 40, max: 72),
            ),
            SizedBox(height: R.hp(context, 0.020, max: 24)),
            Text(
              'All Synced!',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: R.font(context, 0.018, min: 14, max: 20),
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: R.hp(context, 0.010, max: 12)),
            Text(
              'No pending time in / time out records',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: R.font(context, 0.014, min: 11, max: 16),
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: R.screenPadding(context),
            itemCount: controller.employeesWithPending.length,
            itemBuilder: (context, index) {
              final emp = controller.employeesWithPending[index];
              final pendingCount =
                  int.tryParse(emp['pending_count']?.toString() ?? '0') ?? 0;
              return _buildEmployeeCard(
                context,
                controller,
                w,
                h,
                emp['employee_id']?.toString() ?? '',
                emp['employee_name']?.toString() ?? 'Unknown',
                pendingCount,
              );
            },
          ),
        ),
        Padding(
          padding: R.screenPadding(context),
          child: R.primaryButton(
            context: context,
            label: controller.isOfflineUiMode.value
                ? 'CHOOSE OFFLINE / ONLINE MODE'
                : 'UPLOAD ALL PENDING',
            onTap: controller.isUploading.value
                ? null
                : () async {
                    if (controller.isOfflineUiMode.value) {
                      await controller.promptSyncModeSelection();
                    } else {
                      await controller.uploadAllPending();
                    }
                  },
            background: controller.isOfflineUiMode.value
                ? const Color(0xFF3E7DDD)
                : const Color(0xFF44D980),
            isLoading: controller.isUploading.value,
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(
    BuildContext context,
    EmployeeDatabaseController controller,
    double w,
    double h,
    String employeeId,
    String employeeName,
    int pendingCount,
  ) {
    final avatarSize = R.wp(context, 0.050, min: 36, max: 56);

    return GestureDetector(
      onTap: () => controller.loadPendingRecordsForEmployee(
        employeeId: employeeId,
        employeeName: employeeName,
      ),
      child: Container(
        margin: EdgeInsets.only(bottom: R.hp(context, 0.012, max: 14)),
        padding: R.screenPadding(context),
        decoration: BoxDecoration(
          color: const Color(0xFF0B2742).withOpacity(0.70),
          borderRadius: BorderRadius.circular(R.wp(context, 0.016, max: 16)),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                color: const Color(0xFF3FA9F5),
                borderRadius: BorderRadius.circular(
                  R.wp(context, 0.008, max: 10),
                ),
              ),
              child: Center(
                child: Text(
                  employeeName.isNotEmpty ? employeeName[0] : '?',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: R.font(context, 0.020, min: 14, max: 22),
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            SizedBox(width: R.wp(context, 0.015, max: 16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employeeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: R.font(context, 0.014, min: 12, max: 16),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: R.hp(context, 0.004, min: 4, max: 6)),
                  Text(
                    'ID: $employeeId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: R.font(context, 0.011, min: 10, max: 13),
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: R.wp(context, 0.012, min: 8, max: 12),
                    vertical: R.hp(context, 0.006, min: 4, max: 8),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B),
                    borderRadius: BorderRadius.circular(
                      R.wp(context, 0.008, max: 10),
                    ),
                  ),
                  child: Text(
                    '$pendingCount pending',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: R.font(context, 0.010, min: 9, max: 12),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(height: R.hp(context, 0.006, min: 6, max: 8)),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.5),
                  size: R.font(context, 0.012, min: 12, max: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailView(
    BuildContext context,
    EmployeeDatabaseController controller,
    double w,
    double h,
  ) {
    return Column(
      children: [
        Padding(
          padding: R.screenPadding(context),
          child: Row(
            children: [
              GestureDetector(
                onTap: controller.clearSelection,
                child: Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: R.font(context, 0.018, min: 20, max: 28),
                ),
              ),
              SizedBox(width: R.wp(context, 0.015, max: 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.selectedEmployeeName.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: R.font(context, 0.016, min: 13, max: 18),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'ID: ${controller.selectedEmployeeId.value}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: R.font(context, 0.012, min: 10, max: 14),
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: controller.isLoading.value
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : ListView.builder(
                  padding: R.screenPadding(context),
                  itemCount: controller.selectedEmployeePending.length,
                  itemBuilder: (context, index) {
                    final record = controller.selectedEmployeePending[index];
                    return _buildPendingRecordCard(
                      context,
                      w,
                      h,
                      label: record['display_label']?.toString() ?? 'Attendance',
                      date: record['display_date']?.toString() ?? '',
                      time: record['display_time']?.toString() ?? '',
                    );
                  },
                ),
        ),
        Padding(
          padding: R.screenPadding(context),
          child: R.primaryButton(
            context: context,
            label: controller.isOfflineUiMode.value
                ? 'CHOOSE OFFLINE / ONLINE MODE'
                : 'UPLOAD RECORDS',
            onTap: controller.isUploading.value
                ? null
                : () async {
                    if (controller.isOfflineUiMode.value) {
                      await controller.promptSyncModeSelection();
                    } else {
                      await controller.uploadPendingForEmployee(
                        employeeId: controller.selectedEmployeeId.value,
                      );
                    }
                  },
            background: controller.isOfflineUiMode.value
                ? const Color(0xFF3E7DDD)
                : const Color(0xFF44D980),
            isLoading: controller.isUploading.value,
          ),
        ),
      ],
    );
  }

  Widget _buildPendingRecordCard(
    BuildContext context,
    double w,
    double h, {
    required String label,
    required String date,
    required String time,
  }) {
    final isTimeIn = label.toLowerCase().contains('time in');
    final dateStr = date.isEmpty ? 'Unknown date' : date;
    final timeStr = time.isEmpty ? '--:--:--' : time;

    return Container(
      margin: EdgeInsets.only(bottom: R.hp(context, 0.010, max: 12)),
      padding: R.screenPadding(context),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2742).withOpacity(0.60),
        borderRadius: BorderRadius.circular(R.wp(context, 0.012, max: 14)),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(
            isTimeIn ? Icons.login : Icons.logout,
            color: isTimeIn ? const Color(0xFF44D980) : const Color(0xFFFF6B6B),
            size: R.font(context, 0.018, min: 18, max: 26),
          ),
          SizedBox(width: R.wp(context, 0.012, max: 14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: R.font(context, 0.012, min: 11, max: 14),
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: R.hp(context, 0.003, min: 2, max: 4)),
                Text(
                  '$dateStr $timeStr',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: R.font(context, 0.010, min: 9, max: 12),
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: R.wp(context, 0.010, min: 6, max: 10),
              vertical: R.hp(context, 0.005, min: 3, max: 6),
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withOpacity(0.3),
              borderRadius: BorderRadius.circular(
                R.wp(context, 0.008, max: 10),
              ),
              border: Border.all(
                color: const Color(0xFFFF9800),
              ),
            ),
            child: Text(
              'pending',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: R.font(context, 0.010, min: 9, max: 11),
                fontWeight: FontWeight.bold,
                color: const Color(0xFFFF9800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
