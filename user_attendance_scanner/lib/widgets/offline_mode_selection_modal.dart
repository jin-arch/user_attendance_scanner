import 'package:flutter/material.dart';
import '../services/offline_mode_sync_service.dart';

class OfflineModeSelectionModal extends StatelessWidget {
  final VoidCallback onOnlineSelected;
  final VoidCallback onOfflineSelected;
  final bool? hasWiFi;
  final String? siteNameDisplay;

  const OfflineModeSelectionModal({
    super.key,
    required this.onOnlineSelected,
    required this.onOfflineSelected,
    this.hasWiFi,
    this.siteNameDisplay,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;

    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        barrierDismissible: false,
        child: Container(
          constraints: BoxConstraints(maxWidth: w * 0.50),
          decoration: BoxDecoration(
            color: const Color(0xFF0B2742).withOpacity(0.95),
            borderRadius: BorderRadius.circular(w * 0.025),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 2,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(w * 0.025),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SELECT MODE',
                  style: TextStyle(
                    fontFamily: 'CEORUSE',
                    fontSize: w * 0.018,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
                SizedBox(height: h * 0.025),
                Container(
                  padding: EdgeInsets.all(w * 0.015),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(w * 0.012),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose how you want to sync attendance:',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.013,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      SizedBox(height: h * 0.012),
                      if (hasWiFi != null)
                        Padding(
                          padding: EdgeInsets.only(bottom: h * 0.012),
                          child: Row(
                            children: [
                              Icon(
                                hasWiFi! ? Icons.wifi : Icons.wifi_off,
                                color: hasWiFi!
                                    ? const Color(0xFF44D980)
                                    : Colors.grey,
                                size: w * 0.015,
                              ),
                              SizedBox(width: w * 0.010),
                              Text(
                                hasWiFi! ? 'WiFi Connected' : 'No WiFi',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: w * 0.011,
                                  color: hasWiFi!
                                      ? const Color(0xFF44D980)
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: h * 0.025),
                _buildModeOption(
                  context,
                  w,
                  h,
                  icon: Icons.cloud_upload,
                  title: 'ONLINE MODE',
                  subtitle: 'Send data to server\n(requires WiFi)',
                  color: const Color(0xFF3E7DDD),
                  onTap: onOnlineSelected,
                  isAvailable: hasWiFi ?? true,
                ),
                SizedBox(height: h * 0.015),
                _buildModeOption(
                  context,
                  w,
                  h,
                  icon: Icons.storage,
                  title: 'OFFLINE MODE',
                  subtitle: 'Save data locally\n(sync later via WiFi)',
                  color: const Color(0xFF244D86),
                  onTap: onOfflineSelected,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeOption(
    BuildContext context,
    double w,
    double h, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isAvailable = true,
  }) {
    return GestureDetector(
      onTap: isAvailable ? onTap : null,
      child: Container(
        padding: EdgeInsets.all(w * 0.015),
        decoration: BoxDecoration(
          color: isAvailable ? color.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
          border: Border.all(
            color: isAvailable ? color : Colors.grey.withOpacity(0.5),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(w * 0.012),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(w * 0.010),
              decoration: BoxDecoration(
                color: isAvailable ? color : Colors.grey,
                borderRadius: BorderRadius.circular(w * 0.008),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: w * 0.020,
              ),
            ),
            SizedBox(width: w * 0.015),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'CEORUSE',
                      fontSize: w * 0.014,
                      fontWeight: FontWeight.bold,
                      color: isAvailable ? Colors.white : Colors.grey,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: h * 0.004),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: w * 0.010,
                      color: isAvailable
                          ? Colors.white.withOpacity(0.8)
                          : Colors.grey,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (isAvailable)
              Icon(
                Icons.arrow_forward_ios,
                color: color,
                size: w * 0.014,
              ),
          ],
        ),
      ),
    );
  }
}
