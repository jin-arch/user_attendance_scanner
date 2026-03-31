import 'package:flutter/material.dart';
import 'logs_page.dart';
import 'database_page.dart';
import 'enrollment_page.dart';

class NavigationDrawer extends StatelessWidget {
  const NavigationDrawer({
    super.key,
    this.selectedSiteId,
    this.onNavigate,
  });

  final String? selectedSiteId;
  final Function(String)? onNavigate;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF092238),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
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
                  'HIRS SYSTEM',
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
                  'Human Resources Information System',
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
              Navigator.of(context).pop();
              if (onNavigate != null) {
                onNavigate!('home');
              }
            },
          ),
          
          // Register Button
          ListTile(
            leading: const Icon(
              Icons.person_add_outlined,
              color: Colors.white,
              size: 24,
            ),
            title: const Text(
              'Register',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EnrollmentPage(
                    // Don't pass employeeId/employeeName - let user input their own
                    siteId: selectedSiteId,
                  ),
                ),
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
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LogsPage(
                    siteId: selectedSiteId,
                  ),
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
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DatabasePage(
                    siteId: selectedSiteId,
                  ),
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
              Navigator.of(context).pop();
              
              // Show simple sync message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 16),
                      Text('Syncing data...'),
                    ],
                  ),
                  duration: Duration(seconds: 3),
                  backgroundColor: Color(0xFF3FA9F5),
                ),
              );

              // Simulate sync completion after delay
              await Future.delayed(const Duration(seconds: 3));
              
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sync completed successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
