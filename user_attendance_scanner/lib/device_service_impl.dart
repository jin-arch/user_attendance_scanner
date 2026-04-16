import 'package:flutter/foundation.dart';

import 'device_service.dart';
import 'employee_model.dart';
import 'scan_result_model.dart';
import 'zkfp/zkteco_usb.dart';

class DeviceServiceImpl implements DeviceService {
  final ZKTecoUSB _device = ZKTecoUSB();

  @override
  bool get isConnected => _device.isConnected;

  @override
  Future<bool> connect() async {
    try {
      final result = await _device.connect();
      return result == true;
    } catch (e) {
      debugPrint('Device connection error: $e');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _device.disconnect();
    } catch (e) {
      debugPrint('Device disconnect error: $e');
    }
  }

  @override
  Future<Uint8List?> scanFingerprint() async {
    try {
      return await _device.captureFingerprint();
    } catch (e) {
      debugPrint('Fingerprint scan error: $e');
      return null;
    }
  }

  @override
  Future<ScanResult> matchFingerprint(Uint8List template, List<Employee> employees) async {
    try {
      if (!isConnected) {
        return ScanResult.deviceError(errorMessage: 'Device not connected');
      }

      if (ZKTecoUSB.isAndroidPlatform) {
        // On Android, the SDK does 1:N identification against its internal DB.
        // We map the returned fid back to an Employee using the same fid algorithm
        // used when saving employees locally.
        final res = await _device.identifyFingerprint();
        if (res.found && res.fid != null) {
          final matched = employees.where((e) => _computeFid(e.id).toString() == res.fid).toList();
          if (matched.isNotEmpty) {
            final confidence = res.score == null ? null : (res.score! / 100.0).clamp(0.0, 1.0);
            return ScanResult.success(
              employee: matched.first,
              template: template,
              matchConfidence: confidence,
            );
          }
          return ScanResult.employeeNotFound(
            template: template,
            errorMessage: 'Matched FID ${res.fid} not found in employee list',
          );
        }

        return ScanResult.fingerprintNotRecognized();
      }

      // Windows: match the captured template against locally stored templates.
      for (final employee in employees) {
        final enrolled = employee.fingerTemplate;
        if (enrolled == null || enrolled.isEmpty) continue;

        final score = _device.matchTemplates(template, enrolled);
        if (score > 0) {
          final confidence = (score / 100.0).clamp(0.0, 1.0);
          return ScanResult.success(
            employee: employee,
            template: template,
            matchConfidence: confidence,
          );
        }
      }

      return ScanResult.employeeNotFound(
        template: template,
        errorMessage: 'No matching employee found',
      );
    } catch (e) {
      return ScanResult.deviceError(
        errorMessage: 'Fingerprint matching error: $e',
      );
    }
  }

  int _computeFid(String employeeId) {
    final digits = employeeId.replaceAll(RegExp(r'\D'), '');
    final normalized = digits.length > 8 ? digits.substring(digits.length - 8) : digits;
    return int.tryParse(normalized) ?? (employeeId.hashCode.abs() % 999997 + 1);
  }

  @override
  Future<bool> registerFingerprint(int fingerId, Uint8List template) async {
    try {
      return await _device.registerFingerprint(fingerId, template);
    } catch (e) {
      debugPrint('Fingerprint registration error: $e');
      return false;
    }
  }

  @override
  Future<bool> clearAllFingerprints() async {
    try {
      return await _device.clearDatabase();
    } catch (e) {
      debugPrint('Clear fingerprints error: $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final version = await _device.getVersion();
      final serial = await _device.getSerialNumber();
      return {
        'isConnected': isConnected,
        'platform': ZKTecoUSB.isAndroidPlatform ? 'Android' : 'Windows',
        'deviceType': 'ZKTeco USB',
        'serialNumber': serial,
        'sdkVersion': version,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  @override
  Future<void> startScanningMode() async {
    // Device-specific initialization if needed
    try {
      if (ZKTecoUSB.isAndroidPlatform) {
        // Android scanning is event-driven
        // Setup callbacks would be done in the view layer
      }
    } catch (e) {
      debugPrint('Start scanning mode error: $e');
    }
  }

  @override
  Future<void> stopScanningMode() async {
    // Device-specific cleanup if needed
    try {
      if (ZKTecoUSB.isAndroidPlatform) {
        // Stop Android scanning
      }
    } catch (e) {
      debugPrint('Stop scanning mode error: $e');
    }
  }
}