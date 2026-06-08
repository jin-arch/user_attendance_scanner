import 'dart:async';
import 'dart:typed_data';
import 'package:user_attendance_scanner/app/data/models/employee_model.dart';
import 'package:user_attendance_scanner/app/data/models/scan_result_model.dart';

abstract class DeviceService {
  /// Check if device is connected
  bool get isConnected;
  
  /// Connect to fingerprint scanner device
  Future<bool> connect();
  
  /// Disconnect from device
  Future<void> disconnect();
  
  /// Scan fingerprint and return template
  Future<Uint8List?> scanFingerprint();
  
  /// Match fingerprint template against employee database
  Future<ScanResult> matchFingerprint(Uint8List template, List<Employee> employees);

  /// Identify finger against templates registered on the device (home-page flow).
  Future<({int? fingerId, String? fidRaw})> identifyOnDevice({
    Uint8List? capturedTemplate,
  });
  
  /// Register employee fingerprint on device
  Future<bool> registerFingerprint(int fingerId, Uint8List template);
  
  /// Clear all fingerprints from device
  Future<bool> clearAllFingerprints();
  
  /// Get device information
  Future<Map<String, dynamic>> getDeviceInfo();
  
  /// Start continuous scanning mode
  Future<void> startScanningMode();
  
  /// Stop scanning mode
  Future<void> stopScanningMode();
}
