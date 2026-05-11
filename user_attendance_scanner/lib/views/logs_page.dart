// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/logs_controller.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key, this.siteId});

  final String? siteId;

  @override
  Widget build(BuildContext context) {
    return GetX<LogsController>(
      init: LogsController(siteId: siteId),
      global: false,
      builder: (controller) {
        final size = MediaQuery.sizeOf(context);
        final w = size.width;
        final filteredLogs = controller.filteredLogs;
        final errorMessage = controller.errorMessage.value;
        final statusMessage = controller.statusMessage.value;
        final isScanning = controller.isScanning.value;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: const Color(0xFF092238),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Get.back<void>(),
            ),
            title: const Text(
              'Time Logs',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: controller.fetchAndSaveTimeLogsFromApi,
                tooltip: 'Fetch time logs from server',
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: controller.refreshLogs,
              ),
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/Main BG.png'),
                fit: BoxFit.cover,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(w * 0.02),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(w * 0.04),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2240).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(w * 0.04),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(w * 0.02),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controller.searchController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Search logs...',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: Colors.white70,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF1A3A5C),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(w * 0.02),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: w * 0.01),
                              Expanded(
                                child: TextField(
                                  onChanged: (value) => controller.employeeIdSearch.value = value,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Employee ID...',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.person,
                                      color: Colors.white70,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.login, color: Color(0xFF3FA9F5)),
                                      onPressed: () => controller.authenticateByEmployeeId(controller.employeeIdSearch.value),
                                      tooltip: 'Authenticate with Employee ID',
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF1A3A5C),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(w * 0.02),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (statusMessage.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: w * 0.02),
                            child: Container(
                              padding: EdgeInsets.all(w * 0.02),
                              decoration: BoxDecoration(
                                color: isScanning 
                                    ? const Color(0xFF3FA9F5).withOpacity(0.2)
                                    : Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(w * 0.02),
                                border: Border.all(
                                  color: isScanning 
                                      ? const Color(0xFF3FA9F5).withOpacity(0.5)
                                      : Colors.green.withOpacity(0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (isScanning)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF3FA9F5),
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                  SizedBox(width: w * 0.02),
                                  Expanded(
                                    child: Text(
                                      statusMessage,
                                      style: TextStyle(
                                        color: isScanning ? const Color(0xFF3FA9F5) : Colors.green,
                                        fontSize: 12,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (errorMessage.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: w * 0.02),
                            child: Text(
                              errorMessage,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: w * 0.02),
                          child: Row(
                            children: [
                              _buildFilterChip(controller, 'All'),
                              SizedBox(width: w * 0.01),
                              _buildFilterChip(controller, 'Time In'),
                              SizedBox(width: w * 0.01),
                              _buildFilterChip(controller, 'Time Out'),
                            ],
                          ),
                        ),
                        const Divider(color: Color(0xFF3E7DDD)),
                        Expanded(
                          child: Stack(
                            children: [
                              if (filteredLogs.isEmpty)
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (isScanning)
                                        const Icon(
                                          Icons.fingerprint,
                                          size: 48,
                                          color: Color(0xFF3FA9F5),
                                        )
                                      else
                                        Icon(
                                          Icons.history,
                                          size: 48,
                                          color: Colors.white.withOpacity(0.6),
                                        ),
                                      SizedBox(height: w * 0.02),
                                      Text(
                                        isScanning
                                            ? 'Scanning fingerprint...'
                                            : controller.isAuthenticated.value
                                                ? 'No time logs found'
                                                : 'Place your finger on the scanner to authenticate',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (!isScanning && !controller.isAuthenticated.value)
                                        SizedBox(height: w * 0.01),
                                      if (!isScanning && !controller.isAuthenticated.value)
                                        Text(
                                          'The scanner is ready - simply place your finger to view your time logs',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.4),
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                              else
                                ListView.builder(
                                  itemCount: filteredLogs.length,
                                  itemBuilder: (context, index) {
                                    final log = filteredLogs[index];
                                    final type = (log['type'] ?? '').toString().toLowerCase();
                                    final isTimeIn = type.contains('in');

                                    // Generate unique key for this log entry
                                    final logKey = '${log['employee_id']}_${log['timestamp']}_${log['type']}';

                                    return Obx(() {
                                      final inCooldown = controller.isLogInCooldown(logKey);

                                      return ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: inCooldown
                                                  ? Colors.grey
                                                  : isTimeIn
                                                      ? Colors.green
                                                      : Colors.orange,
                                              child: Icon(
                                                inCooldown
                                                    ? Icons.timer_off
                                                    : isTimeIn
                                                        ? Icons.login
                                                        : Icons.logout,
                                                color: Colors.white,
                                              ),
                                            ),
                                            title: Text(
                                              (log['employee_name'] as String?) ?? 'Unknown',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: false,
                                              style: TextStyle(
                                                color: inCooldown
                                                    ? Colors.grey
                                                    : Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'ID: ${log['employee_id'] ?? 'N/A'}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  softWrap: false,
                                                  style: TextStyle(
                                                    color: inCooldown
                                                        ? Colors.grey.withOpacity(0.5)
                                                        : Colors.white.withOpacity(0.7),
                                                  ),
                                                ),
                                                if (log['period'] != null)
                                                  Text(
                                                    '${log['period']}',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      color: inCooldown
                                                          ? Colors.grey.withOpacity(0.4)
                                                          : Colors.white.withOpacity(0.6),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                if (inCooldown)
                                                  Text(
                                                    'Hidden - ${controller.formatCooldownTime(logKey)}',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    softWrap: false,
                                                    style: const TextStyle(
                                                      color: Colors.red,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            trailing: SizedBox(
                                              width: w * 0.22,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    inCooldown
                                                        ? 'Hidden'
                                                        : (log['type'] as String?) ?? 'Unknown',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      color: inCooldown
                                                          ? Colors.grey
                                                          : isTimeIn
                                                              ? Colors.green
                                                              : Colors.orange,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  if (!inCooldown)
                                                    Text(
                                                      (log['time_only'] as String?) ??
                                                          controller.formatTimestamp(log['timestamp']),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      softWrap: false,
                                                      style: TextStyle(
                                                        color: Colors.white.withOpacity(0.6),
                                                        fontSize: 12,
                                                      ),
                                                    )
                                                  else
                                                    Text(
                                                      controller.formatCooldownTime(logKey),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      softWrap: false,
                                                      style: const TextStyle(
                                                        color: Colors.red,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            onTap: inCooldown
                                                ? null
                                                : () {
                                                    // Start cooldown when log is tapped
                                                    controller.startLogCooldown(logKey);
                                                  },
                                      );
                                    });
                                  },
                                ),
                              if (controller.isLoading.value)
                                Container(
                                  color: Colors.black.withOpacity(0.3),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF3FA9F5),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(LogsController controller, String label) {
    final isSelected = controller.selectedFilter.value == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        controller.setFilter(label);
      },
      backgroundColor: const Color(0xFF1A3A5C),
      selectedColor: const Color(0xFF3FA9F5),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white.withOpacity(0.8),
      ),
    );
  }
}
