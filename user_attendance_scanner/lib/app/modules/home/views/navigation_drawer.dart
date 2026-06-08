// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:user_attendance_scanner/app/routes/app_routes.dart';
import 'package:user_attendance_scanner/app/modules/database/views/database_page.dart';
import 'package:user_attendance_scanner/app/modules/database/views/employee_database_page.dart';

class NavigationDrawer extends StatelessWidget {
  const NavigationDrawer({
    super.key,
    this.selectedSiteId,
    this.resolveSelectedSite,
    this.onNavigate,
    this.onSync,
  });

  final String? selectedSiteId;
  final Future<({String? siteId, String? siteName})> Function()?
      resolveSelectedSite;
  final Function(String)? onNavigate;
  final Future<void> Function()? onSync;

  Future<({String? siteId, String? siteName})> _resolveSite() async {
    if (resolveSelectedSite != null) {
      return resolveSelectedSite!();
    }
    return (siteId: selectedSiteId, siteName: null);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF092238),
      child: Column(
        children: [
          // Fixed Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF0B2742),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.85),
                      width: 2,
                    ),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3FA9F5), Color(0xFF1B75BB)],
                    ),
                  ),
                  child: const Icon(
                    Icons.menu,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ATTENDANCE SYSTEM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'TRTCENZODEMO',
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Biometric Attendance Management',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          
          // Scrollable List Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const Divider(color: Color(0xFF3E7DDD), height: 1),
                
                // Home Button
                ListTile(
                  leading: const Icon(
                    Icons.home_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                  title: const Text(
                    'Home',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Get.back<void>();
                    if (onNavigate != null) {
                      onNavigate!('home');
                    }
                  },
                ),

                // Enrollment Button (for updating existing users)
                ListTile(
                  leading: const Icon(
                    Icons.fingerprint,
                    color: Colors.white,
                    size: 24,
                  ),
                  title: const Text(
                    'Enrollment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    Get.back<void>();
                    final site = await _resolveSite();
                    if (site.siteId == null || site.siteId!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a site first'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Get.toNamed<void>(
                      AppRoutes.enrollment,
                      arguments: <String, dynamic>{
                        'siteId': site.siteId,
                        'isEditMode': true,
                      },
                    );
                  },
                ),
                
                // Logs Button
                ListTile(
                  leading: const Icon(
                    Icons.list_alt_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                  title: const Text(
                    'Logs',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    Get.back<void>();
                    final site = await _resolveSite();
                    if (site.siteId == null || site.siteId!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a site first'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Get.toNamed<void>(
                      AppRoutes.logs,
                      arguments: <String, dynamic>{
                        'siteId': site.siteId,
                      },
                    );
                  },
                ),

                // Employee Database Button (Pending Attendance Records)
                ListTile(
                  leading: const Icon(
                    Icons.people_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                  title: const Text(
                    'Pending Records',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: const Text(
                    'Offline attendance queue',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  onTap: () async {
                    Get.back<void>();
                    final site = await _resolveSite();
                    if (site.siteId == null || site.siteId!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a site first'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Get.to<void>(
                      () => EmployeeDatabasePage(
                        siteId: site.siteId!,
                        siteName: site.siteName ?? 'Current Site',
                      ),
                    );
                  },
                ),

                // Database Button
                ListTile(
                  leading: const Icon(
                    Icons.storage_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                  title: const Text(
                    'Database',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    Get.back<void>();
                    final site = await _resolveSite();
                    if (site.siteId == null || site.siteId!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a site first'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Get.to<void>(
                      () => DatabasePage(
                        siteId: site.siteId,
                      ),
                    );
                  },
                ),
                
                const Divider(color: Color(0xFF3E7DDD), height: 32),
                
                // Sync Button
                ListTile(
                  leading: const Icon(
                    Icons.sync_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                  title: const Text(
                    'Sync Data',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    Get.back<void>();
                    if (onSync != null) {
                      await onSync!.call();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sync action unavailable on this screen.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
