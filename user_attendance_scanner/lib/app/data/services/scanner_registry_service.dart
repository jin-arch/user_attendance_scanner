import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:user_attendance_scanner/app/data/services/device_service.dart';
import 'package:user_attendance_scanner/app/data/services/local_db.dart';

/// Keeps the biometric device in sync with the offline employee DB.
class ScannerRegistryService extends GetxService {
  DeviceService get _device => Get.find<DeviceService>();

  /// Clear device templates and re-register every enrolled finger for the site.
  Future<int> reloadSiteFromLocalDb(String siteId) async {
    if (siteId.isEmpty) return 0;
    if (!_device.isConnected) {
      debugPrint('[SCANNER_REGISTRY] Device not connected, skip reload');
      return 0;
    }

    try {
      await _device.clearAllFingerprints();
    } catch (e) {
      debugPrint('[SCANNER_REGISTRY] clearAllFingerprints: $e');
    }

    final rows = await LocalDb.getEmployeesBySite(
      siteId,
      includeFingerTemplates: false,
    );
    var registered = 0;

    for (final row in rows) {
      final fid = row['fid'] as int?;
      final empId = row['employee_id']?.toString().trim() ?? '';
      if (fid == null || empId.isEmpty) continue;

      final templateBytes =
          await LocalDb.getFingerTemplateByFid(fid: fid, siteId: siteId);
      if (templateBytes == null || templateBytes.isEmpty) continue;

      final ok = await _device.registerFingerprint(fid, templateBytes);
      if (ok) registered++;
    }

    debugPrint(
      '[SCANNER_REGISTRY] Reloaded site=$siteId registered=$registered/${rows.length}',
    );
    return registered;
  }
}
