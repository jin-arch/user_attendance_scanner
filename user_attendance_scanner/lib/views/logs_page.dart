// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/logs_controller.dart';
import '../utils/responsive.dart';

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
          ),
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => controller.onUserInteraction(),
            onPointerMove: (_) => controller.onUserInteraction(),
            onPointerSignal: (_) => controller.onUserInteraction(),
            child: Container(
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
                            padding: R.screenPadding(context),
                              child: _logsSearchField(
                                context,
                                controller,
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
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                controller.onUserInteraction();
                                return false;
                              },
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
                                        
                                        debugPrint('[LOGS_PAGE] Log $index: emp=${log['employee_id']}, name=${log['employee_name']}, type=${log['type']}, timestamp=${log['timestamp']}, time_only=${log['time_only']}');
                                        
                                        // Generate unique key for this log entry
                                        final logKey = '${log['employee_id']}_${log['timestamp']}_${log['type']}';
                                        
                                        return Dismissible(
                                          key: Key(logKey),
                                          direction: DismissDirection.endToStart,
                                          background: Container(
                                            color: Colors.green,
                                            alignment: Alignment.centerRight,
                                            padding: EdgeInsets.only(right: w * 0.04),
                                            child: const Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.send, color: Colors.white, size: 24),
                                                Text(
                                                  'Send to Server',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          confirmDismiss: (direction) async {
                                            // Show confirmation dialog but never dismiss (always return false)
                                            await _showSendToServerDialog(context, controller, log);
                                            return false; // Never remove the item
                                          },
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: isTimeIn
                                                  ? Colors.green
                                                  : Colors.orange,
                                              child: Icon(
                                                isTimeIn
                                                    ? Icons.login
                                                    : Icons.logout,
                                                color: Colors.white,
                                              ),
                                            ),
                                            title: Text(
                                              (log['employee_name'] as String?) ??
                                              (log['name'] as String?) ??
                                              'Unknown',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: false,
                                              style: const TextStyle(
                                                color: Colors.white,
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
                                                    color: Colors.white.withOpacity(0.7),
                                                  ),
                                                ),
                                                if (log['period'] != null)
                                                  Text(
                                                    '${log['period']}',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      color: Colors.white.withOpacity(0.6),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            trailing: SizedBox(
                                              width: w * 0.28,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    controller.getTimeInOut(log),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      color: isTimeIn
                                                          ? Colors.green
                                                          : Colors.orange,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  Text(
                                                    controller.formatDate(log['timestamp']),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      color: Colors.white.withOpacity(0.5),
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  Text(
                                                    (log['time_only'] as String?) ??
                                                        controller.formatTimestamp(log['timestamp']),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      color: Colors.white.withOpacity(0.7),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
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
                          ),
                        ],
                      ),
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

  Future<bool> _showSendToServerDialog(BuildContext context, LogsController controller, Map<String, dynamic> log) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A2240),
          title: const Text(
            'Send to Server',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send this log entry to server?',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Employee: ${log['employee_name'] ?? 'Unknown'}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
              Text(
                'ID: ${log['employee_id'] ?? 'N/A'}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
              Text(
                'Type: ${log['type'] ?? 'Unknown'}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
              Text(
                'Time: ${log['time_only'] ?? 'N/A'}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF3FA9F5),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              child: const Text(
                'Send',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    ) ?? false;
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

Widget _logsSearchField(
  BuildContext context,
  LogsController controller,
) {
  final radius = R.wp(context, 0.02, max: 12);
  final isAuthenticated = controller.isAuthenticated.value;
  final selectedDate = controller.selectedDate.value;
  return TextField(
    controller: controller.searchController,
    readOnly: true,
    onTap: () async {
      controller.onUserInteraction();
      if (!isAuthenticated) {
        controller.setStatus('Scan fingerprint to enable date search');
        controller.onUserInteraction();
        return;
      }
      final now = DateTime.now();
      final initial = selectedDate ?? now;
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1, now.month, now.day),
      );
      if (picked != null) {
        controller.setSelectedDate(picked);
      }
    },
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: isAuthenticated
          ? 'Select date (YYYY-MM-DD)'
          : 'Scan fingerprint to search by date',
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
      prefixIcon: const Icon(Icons.calendar_today, color: Colors.white70),
      suffixIcon: selectedDate == null
          ? null
          : IconButton(
              icon: const Icon(Icons.clear, color: Colors.white70),
              onPressed: controller.clearSearch,
              tooltip: 'Clear date filter',
            ),
      filled: true,
      fillColor: const Color(0xFF1A3A5C),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
