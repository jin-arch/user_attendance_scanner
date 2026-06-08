// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:user_attendance_scanner/app/modules/database/controllers/database_controller.dart';
import 'package:user_attendance_scanner/app/data/services/sync_service.dart';

class DatabasePage extends StatelessWidget {
  const DatabasePage({super.key, this.siteId});

  final String? siteId;

  @override
  Widget build(BuildContext context) {
    return GetX<DatabaseController>(
      init: DatabaseController(siteId: siteId),
      global: false,
      builder: (controller) {
        final size = MediaQuery.sizeOf(context);
        final w = size.width;
        final filteredEmployees = controller.filteredEmployees;
        final uniqueEmployees = controller.uniqueEmployees;
        final errorMessage = controller.errorMessage.value;

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
              'Employee Database',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: controller.refreshEmployees,
              ),
              IconButton(
                icon: const Icon(Icons.sync, color: Colors.white),
                onPressed: () async {
                  await SyncService.syncAllWithDialog(
                    context,
                    siteId: siteId,
                    onStatusUpdate: (status) {
                      controller.setStatus(status);
                    },
                  );
                  controller.refreshEmployees();
                },
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
                              hintText: 'Search employees...',
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Employees: ${uniqueEmployees.length}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 14,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                              Text(
                                'Showing: ${filteredEmployees.length}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 14,
                                  fontFamily: 'Poppins',
                                ),
                              ),
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
                              : filteredEmployees.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No employees found',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 16,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: filteredEmployees.length,
                                      itemBuilder: (context, index) {
                                        final emp = filteredEmployees[index];
                                        final fingerprintCount =
                                            emp['fingerprint_count'] as int;
                                        final title =
                                            (emp['employee_name'] as String?) ??
                                                'Unknown';
                                        return ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor:
                                                const Color(0xFF3FA9F5),
                                            child: Text(
                                              title.isEmpty
                                                  ? 'U'
                                                  : title[0].toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          title: Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'ID: ${emp['employee_id']}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: false,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.7),
                                                  fontSize: 12,
                                                ),
                                              ),
                                              Text(
                                                'Fingerprints: $fingerprintCount',
                                                style: TextStyle(
                                                  color: fingerprintCount >= 6
                                                      ? Colors.green
                                                      : Colors.orange,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
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
}
