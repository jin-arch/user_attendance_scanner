import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/employee_database_controller.dart';

class EmployeeDatabasePage extends StatefulWidget {
  final String siteId;
  final String? siteName;

  const EmployeeDatabasePage({
    super.key,
    required this.siteId,
    this.siteName,
  });

  @override
  State<EmployeeDatabasePage> createState() => _EmployeeDatabasePageState();
}

class _EmployeeDatabasePageState extends State<EmployeeDatabasePage> {
  late EmployeeDatabaseController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(EmployeeDatabaseController());
    controller.setSiteId(widget.siteId);
    controller.loadEmployeesWithPendingRecords();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

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
              // Header
              Container(
                padding: EdgeInsets.all(w * 0.020),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Get.back(),
                      child: Container(
                        padding: EdgeInsets.all(w * 0.008),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B2742).withOpacity(0.7),
                          borderRadius: BorderRadius.circular(w * 0.012),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: w * 0.020,
                        ),
                      ),
                    ),
                    SizedBox(width: w * 0.015),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EMPLOYEE DATABASE',
                            style: TextStyle(
                              fontFamily: 'CEORUSE',
                              fontSize: w * 0.020,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            'Pending Attendance Records',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: w * 0.012,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Obx(() {
                  if (controller.selectedEmployeeId.value.isNotEmpty) {
                    return _buildDetailView(w, h);
                  }
                  return _buildEmployeeListView(w, h);
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeListView(double w, double h) {
    return Obx(() {
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
                size: w * 0.060,
              ),
              SizedBox(height: h * 0.020),
              Text(
                'All Synced!',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: w * 0.018,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: h * 0.010),
              Text(
                'No pending attendance records',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: w * 0.014,
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
              padding: EdgeInsets.all(w * 0.015),
              itemCount: controller.employeesWithPending.length,
              itemBuilder: (context, index) {
                final emp = controller.employeesWithPending[index];
                return _buildEmployeeCard(
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
            padding: EdgeInsets.all(w * 0.015),
            child: GestureDetector(
              onTap: controller.isUploading.value
                  ? null
                  : () => controller.uploadAllPending(),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: h * 0.018),
                decoration: BoxDecoration(
                  color: controller.isUploading.value
                      ? Colors.grey
                      : const Color(0xFF44D980),
                  borderRadius: BorderRadius.circular(w * 0.012),
                ),
                child: Center(
                  child: controller.isUploading.value
                      ? SizedBox(
                          height: w * 0.018,
                          width: w * 0.018,
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'UPLOAD ALL PENDING',
                          style: TextStyle(
                            fontFamily: 'CEORUSE',
                            fontSize: w * 0.014,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildEmployeeCard(
    double w,
    double h,
    String employeeId,
    String employeeName,
    int pendingCount,
  ) {
    return GestureDetector(
      onTap: () => controller.loadPendingRecordsForEmployee(
        employeeId: employeeId,
        employeeName: employeeName,
      ),
      child: Container(
        margin: EdgeInsets.only(bottom: h * 0.012),
        padding: EdgeInsets.all(w * 0.015),
        decoration: BoxDecoration(
          color: const Color(0xFF0B2742).withOpacity(0.70),
          borderRadius: BorderRadius.circular(w * 0.016),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.050,
              height: w * 0.050,
              decoration: BoxDecoration(
                color: const Color(0xFF3FA9F5),
                borderRadius: BorderRadius.circular(w * 0.008),
              ),
              child: Center(
                child: Text(
                  employeeName.isNotEmpty ? employeeName[0] : '?',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: w * 0.020,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            SizedBox(width: w * 0.015),
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
                      fontSize: w * 0.014,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: h * 0.004),
                  Text(
                    'ID: $employeeId',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: w * 0.011,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: w * 0.012,
                    vertical: h * 0.006,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B),
                    borderRadius: BorderRadius.circular(w * 0.008),
                  ),
                  child: Text(
                    '$pendingCount pending',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: w * 0.010,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(height: h * 0.006),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.5),
                  size: w * 0.012,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailView(double w, double h) {
    return Obx(() {
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.all(w * 0.015),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => controller.clearSelection(),
                  child: Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: w * 0.018,
                  ),
                ),
                SizedBox(width: w * 0.015),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.selectedEmployeeName.value,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.016,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'ID: ${controller.selectedEmployeeId.value}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.012,
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
                    padding: EdgeInsets.all(w * 0.015),
                    itemCount: controller.selectedEmployeePending.length,
                    itemBuilder: (context, index) {
                      final record = controller.selectedEmployeePending[index];
                      return _buildPendingRecordCard(
                        w,
                        h,
                        record['attendance_time']?.toString() ?? '',
                      );
                    },
                  ),
          ),
          Padding(
            padding: EdgeInsets.all(w * 0.015),
            child: GestureDetector(
              onTap: controller.isUploading.value
                  ? null
                  : () => controller.uploadPendingForEmployee(
                        employeeId: controller.selectedEmployeeId.value,
                      ),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: h * 0.018),
                decoration: BoxDecoration(
                  color: controller.isUploading.value
                      ? Colors.grey
                      : const Color(0xFF3E7DDD),
                  borderRadius: BorderRadius.circular(w * 0.012),
                ),
                child: Center(
                  child: controller.isUploading.value
                      ? SizedBox(
                          height: w * 0.018,
                          width: w * 0.018,
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'UPLOAD RECORDS',
                          style: TextStyle(
                            fontFamily: 'CEORUSE',
                            fontSize: w * 0.014,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildPendingRecordCard(double w, double h, String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      final dateStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

      return Container(
        margin: EdgeInsets.only(bottom: h * 0.010),
        padding: EdgeInsets.all(w * 0.015),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(w * 0.012),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.schedule,
              color: const Color(0xFF3FA9F5),
              size: w * 0.018,
            ),
            SizedBox(width: w * 0.012),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: w * 0.012,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: w * 0.010,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.010,
                vertical: h * 0.005,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withOpacity(0.3),
                borderRadius: BorderRadius.circular(w * 0.008),
                border: Border.all(
                  color: const Color(0xFFFF9800),
                ),
              ),
              child: Text(
                'pending',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF9800),
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
