import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'zkfp_ffi_export.dart';

/// ZKTeco Live20R USB communication class using the official SDK
/// API similar to the C# Demo for easier use
/// Note: Only works on Windows - Android not supported
class ZKTecoUSB {
  static const int vendorId = 0x1B55;
  static const int productId = 0x0120;

  ZkfpSdk? _sdk;
  bool _sdkInitialized = false;
  bool _deviceOpened = false;
  String? _serialNumber;
  Uint8List? _lastCapturedImage;
  final _attendanceController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Enrollment state
  final List<Uint8List> _enrollmentTemplates = [];
  int _enrollmentCount = 0;
  static const int REGISTER_FINGER_COUNT = 3;

  // Platform check
  static bool get isWindowsPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows;
  }

  // Getters
  bool get isConnected => _deviceOpened;
  bool get isSdkInitialized => _sdkInitialized;
  bool get isDeviceOpened => _deviceOpened;
  String? get serialNumber => _serialNumber;
  Stream<Map<String, dynamic>> get onAttendanceReceived => _attendanceController.stream;
  int get imageWidth => _sdk?.imageWidth ?? 0;
  int get imageHeight => _sdk?.imageHeight ?? 0;
  Uint8List? get lastCapturedImage => _lastCapturedImage;

  // ==================== SDK Operations ====================

  /// Initialize the SDK (like bnInit_Click in C# demo)
  Future<bool> initSdk() async {
    if (!isWindowsPlatform) {
      debugPrint('ZKFinger SDK only supported on Windows');
      return false;
    }
    
    try {
      debugPrint('Initializing ZKFinger SDK...');
      
      _sdk = ZkfpSdk();
      int result = _sdk!.init();
      
      if (result != ZkfpErrors.OK && result != ZkfpErrors.ALREADY_INIT) {
        debugPrint('SDK Init failed: ${ZkfpErrors.getMessage(result)}');
        _sdk = null;
        return false;
      }
      
      _sdkInitialized = true;
      debugPrint('SDK initialized successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('SDK Init error: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Terminate the SDK (like bnFree_Click in C# demo)
  Future<void> terminateSdk() async {
    if (_deviceOpened) {
      await closeDevice();
    }
    if (_sdk != null) {
      _sdk!.terminate();
      _sdk = null;
    }
    _sdkInitialized = false;
    _lastCapturedImage = null;
    debugPrint('SDK terminated');
  }

  /// Get number of connected devices
  int getDeviceCount() {
    if (!_sdkInitialized || _sdk == null) return 0;
    return _sdk!.getDeviceCount();
  }

  // ==================== Device Operations ====================

  /// Open device by index (like bnOpen_Click in C# demo)
  Future<bool> openDevice(int index) async {
    if (!_sdkInitialized || _sdk == null) {
      debugPrint('SDK not initialized');
      return false;
    }
    
    try {
      debugPrint('Opening device $index...');
      
      int handle = _sdk!.openDevice(index);
      if (handle == 0) {
        debugPrint('Failed to open device');
        return false;
      }
      debugPrint('Device opened (handle: $handle)');
      debugPrint('Image size: ${_sdk!.imageWidth}x${_sdk!.imageHeight}');
      
      // Initialize fingerprint database
      int dbHandle = _sdk!.dbInit();
      if (dbHandle == 0) {
        debugPrint('Failed to initialize fingerprint database');
        _sdk!.closeDevice();
        return false;
      }
      debugPrint('Fingerprint database initialized');
      
      // Get serial number
      _serialNumber = _sdk!.getSerialNumber();
      debugPrint('Serial Number: $_serialNumber');
      
      _deviceOpened = true;
      return true;
    } catch (e) {
      debugPrint('Open device error: $e');
      return false;
    }
  }

  /// Close the currently open device (like bnClose_Click in C# demo)
  Future<void> closeDevice() async {
    if (_sdk != null && _deviceOpened) {
      _sdk!.dbFree();
      _sdk!.closeDevice();
    }
    _deviceOpened = false;
    _serialNumber = null;
    _enrollmentTemplates.clear();
    _enrollmentCount = 0;
    _lastCapturedImage = null;
    debugPrint('Device closed');
  }

  /// Legacy connect method (combines initSdk + openDevice)
  Future<bool> connect() async {
    if (!await initSdk()) return false;
    
    final count = getDeviceCount();
    if (count == 0) {
      await terminateSdk();
      return false;
    }
    
    return await openDevice(0);
  }

  /// Legacy disconnect method (combines closeDevice + terminateSdk)
  Future<void> disconnect() async {
    await closeDevice();
    await terminateSdk();
  }

  // ==================== Fingerprint Operations ====================

  /// Get device serial number
  Future<String?> getSerialNumber() async {
    if (!_deviceOpened || _sdk == null) return null;
    return _serialNumber ?? _sdk!.getSerialNumber();
  }

  /// Get firmware version info
  Future<String?> getVersion() async {
    if (!_deviceOpened || _sdk == null) return null;
    return 'ZKFinger SDK 5.3.0.33';
  }

  /// Capture fingerprint image and template
  /// Returns the fingerprint template data and stores image in lastCapturedImage
  Future<Uint8List?> captureFingerprint() async {
    if (!_deviceOpened || _sdk == null) return null;
    
    try {
      debugPrint('Waiting for fingerprint...');
      
      // Poll for fingerprint with timeout
      const maxAttempts = 50; // 10 seconds at 200ms intervals
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        final result = _sdk!.acquireFingerprint();
        
        if (result.error == ZkfpErrors.OK && result.template != null) {
          debugPrint('Fingerprint captured! Template size: ${result.template!.length} bytes');
          
          // Store the image
          if (result.image != null) {
            _lastCapturedImage = result.image;
          }
          
          return result.template;
        }
        
        // If busy or capture pending, wait and retry
        if (result.error == ZkfpErrors.BUSY || 
            result.error == ZkfpErrors.CAPTURE) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        
        // For other errors, wait and retry a few times
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      debugPrint('Fingerprint capture timeout');
      return null;
    } catch (e) {
      debugPrint('Capture error: $e');
      return null;
    }
  }

  /// Single capture attempt (non-blocking)
  ({Uint8List? image, Uint8List? template, int error}) acquireFingerprintOnce() {
    if (!_deviceOpened || _sdk == null) {
      return (image: null, template: null, error: ZkfpErrors.INVALID_HANDLE);
    }
    final result = _sdk!.acquireFingerprint();
    if (result.image != null) {
      _lastCapturedImage = result.image;
    }
    return result;
  }

  /// Start enrollment process - call this, then captureForEnrollment 3 times
  void startEnrollment() {
    _enrollmentTemplates.clear();
    _enrollmentCount = 0;
    debugPrint('Enrollment started - please capture 3 fingerprints');
  }

  /// Capture fingerprint for enrollment (need to capture 3 times)
  /// Returns progress info and merged template when complete
  Future<({int count, Uint8List? mergedTemplate, String? error})> captureForEnrollment() async {
    if (!_deviceOpened || _sdk == null) {
      return (count: 0, mergedTemplate: null, error: 'Not connected');
    }

    final template = await captureFingerprint();
    if (template == null) {
      return (count: _enrollmentCount, mergedTemplate: null, error: 'Capture failed');
    }

    // Check if same finger as previous captures
    if (_enrollmentCount > 0) {
      final matchScore = _sdk!.dbMatch(template, _enrollmentTemplates.last);
      if (matchScore <= 0) {
        return (count: _enrollmentCount, mergedTemplate: null, 
                error: 'Please use the same finger for all 3 captures');
      }
    }

    _enrollmentTemplates.add(template);
    _enrollmentCount++;

    if (_enrollmentCount >= REGISTER_FINGER_COUNT) {
      // Merge 3 templates into registration template
      final merged = _sdk!.dbMerge(
        _enrollmentTemplates[0],
        _enrollmentTemplates[1],
        _enrollmentTemplates[2],
      );
      
      _enrollmentTemplates.clear();
      final count = _enrollmentCount;
      _enrollmentCount = 0;
      
      if (merged == null) {
        return (count: count, mergedTemplate: null, error: 'Failed to merge templates');
      }
      
      debugPrint('Enrollment complete! Merged template: ${merged.length} bytes');
      return (count: count, mergedTemplate: merged, error: null);
    }

    return (count: _enrollmentCount, mergedTemplate: null, error: null);
  }

  /// Register a fingerprint to the database
  /// fingerId should be unique identifier for the user
  Future<bool> registerFingerprint(int fingerId, Uint8List template) async {
    if (!_deviceOpened || _sdk == null) return false;
    
    final result = _sdk!.dbAdd(fingerId, template);
    if (result == ZkfpErrors.OK) {
      debugPrint('Fingerprint registered for ID: $fingerId');
      return true;
    } else {
      debugPrint('Failed to register fingerprint: ${ZkfpErrors.getMessage(result)}');
      return false;
    }
  }

  /// Identify a template against the database (1:N matching)
  /// Does not capture - use with already captured template
  ({int? fingerId, int? score, int error}) identifyTemplate(Uint8List template) {
    if (!_deviceOpened || _sdk == null) {
      return (fingerId: null, score: null, error: ZkfpErrors.INVALID_HANDLE);
    }
    return _sdk!.dbIdentify(template);
  }

  /// Identify fingerprint (1:N matching against database) - captures first
  Future<int?> identifyFingerprint() async {
    if (!_deviceOpened || _sdk == null) return null;
    
    final template = await captureFingerprint();
    if (template == null) return null;
    
    final result = _sdk!.dbIdentify(template);
    if (result.error == ZkfpErrors.OK && result.fingerId != null) {
      debugPrint('Identified! User ID: ${result.fingerId}, Score: ${result.score}');
      return result.fingerId;
    }
    
    debugPrint('Fingerprint not found in database');
    return null;
  }

  /// Verify fingerprint against a specific user (1:1 matching)
  Future<bool> verifyFingerprint(int userId) async {
    final identified = await identifyFingerprint();
    return identified == userId;
  }

  /// Match two fingerprint templates
  int matchTemplates(Uint8List template1, Uint8List template2) {
    if (!_deviceOpened || _sdk == null) return -1;
    return _sdk!.dbMatch(template1, template2);
  }

  /// Get number of fingerprints in database
  int? getDatabaseCount() {
    if (!_deviceOpened || _sdk == null) return null;
    return _sdk!.dbCount();
  }

  /// Clear all fingerprints from database
  bool clearDatabase() {
    if (!_deviceOpened || _sdk == null) return false;
    return _sdk!.dbClear() == ZkfpErrors.OK;
  }

  /// Remove a fingerprint from database
  bool removeFingerprint(int fingerId) {
    if (!_deviceOpened || _sdk == null) return false;
    return _sdk!.dbDel(fingerId) == ZkfpErrors.OK;
  }

  /// Dispose resources
  void dispose() {
    _attendanceController.close();
    disconnect();
  }
}
