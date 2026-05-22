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
    if (!Get.isRegistered<EmployeeDatabaseController>(tag: tag)) {
      Get.put(EmployeeDatabaseController(), tag: tag);
    }

    return GetX<EmployeeDatabaseController>(
      tag: tag,
      builder: (controller) {
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
                borderRadius: BorderRadius.circular(R.wp(context, 0.012, max: 14)),
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
                    'EMPLOYEE DATABASE',
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
                  siteName ?? 'Pending Attendance Records',
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
              'No pending attendance records',
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
              return _buildEmployeeCard(
                context,
                controller,
                w,
                h,
                emp['employee_id']?.toString() ?? '',
                emp['employee_name']?.toString() ?? 'Unknown',
                emp['pending_count'] as int? ?? 0,
              );
            },
          ),
        ),
        Padding(
          padding: R.screenPadding(context),
          child: R.primaryButton(
            context: context,
            label: 'UPLOAD ALL PENDING',
            onTap: controller.isUploading.value
                ? null
                : controller.uploadAllPending,
            background: const Color(0xFF44D980),
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
                borderRadius: BorderRadius.circular(R.wp(context, 0.008, max: 10)),
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
                  SizedBox(height: R.hp(context, 0.004, max: 6)),
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
                    borderRadius: BorderRadius.circular(R.wp(context, 0.008, max: 10)),
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
                SizedBox(height: R.hp(context, 0.006, max: 8)),
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
                      record['attendance_time']?.toString() ?? '',
                      record['record_type']?.toString() ?? 'attendance',
                    );
                  },
                ),
        ),
        Padding(
          padding: R.screenPadding(context),
          child: R.primaryButton(
            context: context,
            label: 'UPLOAD RECORDS',
            onTap: controller.isUploading.value
                ? null
                : () => controller.uploadPendingForEmployee(
                      employeeId: controller.selectedEmployeeId.value,
                    ),
            isLoading: controller.isUploading.value,
          ),
        ),
      ],
    );
  }

  Widget _buildPendingRecordCard(
    BuildContext context,
    double w,
    double h,
    String timestamp,
    String recordType,
  ) {
    try {
      final dt = DateTime.parse(timestamp);
      final dateStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
      final label = recordType.toLowerCase() == 'fingerprint'
          ? 'Fingerprint update'
          : 'Attendance';

      return Container(
        margin: EdgeInsets.only(bottom: R.hp(context, 0.010, max: 12)),
        padding: R.screenPadding(context),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(R.wp(context, 0.012, max: 14)),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(
              recordType.toLowerCase() == 'fingerprint'
                  ? Icons.fingerprint
                  : Icons.schedule,
              color: const Color(0xFF3FA9F5),
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
                borderRadius: BorderRadius.circular(R.wp(context, 0.008, max: 10)),
                border: Border.all(color: const Color(0xFFFF9800)),
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
    } catch (e) {
      return const SizedBox.shrink();
    }
  }
}
