import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'device_service.dart';
import 'local_db.dart';

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

    final rows = await LocalDb.getEmployeesBySite(siteId);
    var registered = 0;

    for (final row in rows) {
      final fid = row['fid'] as int?;
      final empId = row['employee_id']?.toString().trim() ?? '';
      if (fid == null || empId.isEmpty) continue;

      final templateRaw = row['finger_template'];
      final templateBytes = templateRaw is Uint8List
          ? templateRaw
          : (templateRaw is List<int> ? Uint8List.fromList(templateRaw) : null);
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
