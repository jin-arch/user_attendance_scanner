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

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: const Color(0xFF092238),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
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
                          child: controller.isLoading.value
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF3FA9F5),
                                  ),
                                )
                              : filteredLogs.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No logs found',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 16,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: filteredLogs.length,
                                      itemBuilder: (context, index) {
                                        final log = filteredLogs[index];
                                        final type =
                                            (log['type'] ?? '')
                                                .toString()
                                                .toLowerCase();
                                        final isTimeIn = type.contains('in');

                                        return ListTile(
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
                                                'Unknown',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'ID: ${log['employee_id'] ?? 'N/A'}',
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.7),
                                                ),
                                              ),
                                              if (log['period'] != null)
                                                Text(
                                                  '${log['period']}',
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.6),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          trailing: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                (log['type'] as String?) ??
                                                    'Unknown',
                                                style: TextStyle(
                                                  color: isTimeIn
                                                      ? Colors.green
                                                      : Colors.orange,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                (log['time_only'] as String?) ??
                                                    controller.formatTimestamp(
                                                      log['timestamp'],
                                                    ),
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.6),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
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
