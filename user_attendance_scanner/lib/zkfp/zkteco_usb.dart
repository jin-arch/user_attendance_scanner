import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'zkfp_ffi_export.dart';

/// ZKTeco Live20R USB communication class
/// Supports both Windows (FFI) and Android (Platform Channel)
/// Singleton pattern - use ZKTecoUSB.instance to access
class ZKTecoUSB {
  static const int vendorId = 0x1B55;
  static const int productId = 0x0120;

  // Singleton instance
  static final ZKTecoUSB _instance = ZKTecoUSB._internal();
  factory ZKTecoUSB() => _instance;
  static ZKTecoUSB get instance => _instance;

  // Platform channel for Android
  static const MethodChannel _channel = MethodChannel('com.example.user_attendance_scanner/zkfinger');

  // Windows FFI SDK
  ZkfpSdk? _sdk;
  
  // State
  bool _sdkInitialized = false;
  bool _deviceOpened = false;
  String? _serialNumber;
  Uint8List? _lastCapturedImage;
  Uint8List? _lastTemplate;
  final _attendanceController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Enrollment state
  final List<Uint8List> _enrollmentTemplates = [];
  int _enrollmentCount = 0;
  static const int REGISTER_FINGER_COUNT = 3;

  // Internal constructor
  ZKTecoUSB._internal() {
    // Set up method call handler for Android callbacks
    if (isAndroidPlatform) {
      _channel.setMethodCallHandler(_handleAndroidCallback);
    }
  }

  // Platform check
  static bool get isWindowsPlatform {
    try {
      return !kIsWeb && Platform.isWindows;
    } catch (e) {
      return false;
    }
  }

  static bool get isAndroidPlatform {
    try {
      return !kIsWeb && Platform.isAndroid;
    } catch (e) {
      return false;
    }
  }

  static bool get isSupportedPlatform => isWindowsPlatform || isAndroidPlatform;

  // Callbacks for Android platform events
  Function(int width, int height, Uint8List imageData)? onImageCaptured;
  Function(Uint8List template, int size)? onTemplateExtracted;
  Function(bool success, String message, String? fid, Uint8List? template)? onEnrollResult;
  Function(int current, int total, String message)? onEnrollProgress;
  Function()? onDeviceAttached;
  Function()? onDeviceDetached;
  Function()? onDeviceException;
  Function(int errorCode)? onExtractError;

  Future<dynamic> _handleAndroidCallback(MethodCall call) async {
    switch (call.method) {
      case 'onImageCaptured':
        final args = call.arguments as Map;
        final width = args['width'] as int;
        final height = args['height'] as int;
        final imageBase64 = args['imageData'] as String;
        final imageData = base64Decode(imageBase64);
        _lastCapturedImage = imageData;
        onImageCaptured?.call(width, height, imageData);
        break;
      case 'onTemplateExtracted':
        final args = call.arguments as Map;
        final templateBase64 = args['template'] as String;
        final size = args['size'] as int;
        final template = base64Decode(templateBase64);
        _lastTemplate = template;
        onTemplateExtracted?.call(template, size);
        break;
      case 'onEnrollResult':
        final args = call.arguments as Map;
        final success = args['success'] as bool;
        final message = args['message'] as String;
        final fid = args['fid'] as String?;
        final templateBase64 = args['template'] as String?;
        final template = templateBase64 != null ? base64Decode(templateBase64) : null;
        onEnrollResult?.call(success, message, fid, template);
        break;
      case 'onEnrollProgress':
        final args = call.arguments as Map;
        final current = args['current'] as int;
        final total = args['total'] as int;
        final message = args['message'] as String;
        onEnrollProgress?.call(current, total, message);
        break;
      case 'onDeviceAttached':
        onDeviceAttached?.call();
        break;
      case 'onDeviceDetached':
        _deviceOpened = false;
        onDeviceDetached?.call();
        break;
      case 'onDeviceException':
        onDeviceException?.call();
        break;
      case 'onExtractError':
        final errorCode = call.arguments as int;
        onExtractError?.call(errorCode);
        break;
    }
    return null;
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
  Uint8List? get lastTemplate => _lastTemplate;

  void clearCachedCapture() {
    _lastCapturedImage = null;
    _lastTemplate = null;
  }

  // ==================== SDK Operations ====================

  /// Initialize the SDK
  Future<bool> initSdk() async {
    if (!isSupportedPlatform) {
      debugPrint('ZKFinger SDK only supported on Windows and Android');
      return false;
    }
    
    try {
      debugPrint('Initializing ZKFinger SDK...');
      
      if (isAndroidPlatform) {
        final result = await _channel.invokeMethod<bool>('initSdk');
        _sdkInitialized = result ?? false;
        debugPrint('Android SDK initialized: $_sdkInitialized');
        return _sdkInitialized;
      } else {
        // Windows FFI
        _sdk = ZkfpSdk();
        int result = _sdk!.init();
        
        if (result != ZkfpErrors.OK && result != ZkfpErrors.ALREADY_INIT) {
          debugPrint('SDK Init failed: ${ZkfpErrors.getMessage(result)}');
          _sdk = null;
          return false;
        }
        
        _sdkInitialized = true;
        debugPrint('Windows SDK initialized successfully');
        return true;
      }
    } catch (e, stackTrace) {
      debugPrint('SDK Init error: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Terminate the SDK
  Future<void> terminateSdk() async {
    if (_deviceOpened) {
      await closeDevice();
    }
    
    try {
      if (isAndroidPlatform) {
        await _channel.invokeMethod('freeSdk');
      } else if (_sdk != null) {
        _sdk!.terminate();
        _sdk = null;
      }
    } catch (e) {
      debugPrint('terminateSdk error: $e');
    }
    
    _sdkInitialized = false;
    _lastCapturedImage = null;
    _lastTemplate = null;
    debugPrint('SDK terminated');
  }

  Future<Map<String, dynamic>> getAndroidSdkEnvironment() async {
    if (!isAndroidPlatform) {
      return const {
        'canUseSdk': true,
        'reason': 'Not running on Android',
      };
    }

    try {
      final result = await _channel.invokeMethod<Map>('getSdkEnvironment');
      if (result == null) {
        return const {
          'canUseSdk': false,
          'reason': 'Android runtime environment is unavailable',
        };
      }
      return Map<String, dynamic>.from(result.cast<dynamic, dynamic>());
    } catch (e) {
      debugPrint('getAndroidSdkEnvironment error: $e');
      return {
        'canUseSdk': false,
        'reason': 'Failed to inspect Android runtime environment: $e',
      };
    }
  }

  /// Get number of connected devices
  Future<int> getDeviceCountAsync() async {
    if (!_sdkInitialized) return 0;
    
    try {
      if (isAndroidPlatform) {
        final count = await _channel.invokeMethod<int>('getDeviceCount');
        return count ?? 0;
      } else {
        return _sdk?.getDeviceCount() ?? 0;
      }
    } catch (e) {
      debugPrint('getDeviceCount error: $e');
      return 0;
    }
  }

  /// Sync version for backward compatibility (Windows only)
  int getDeviceCount() {
    if (!_sdkInitialized || _sdk == null || isAndroidPlatform) return 0;
    return _sdk!.getDeviceCount();
  }

  // ==================== Device Operations ====================

  /// Open device by index
  Future<bool> openDevice(int index) async {
    if (!_sdkInitialized) {
      debugPrint('SDK not initialized');
      return false;
    }
    
    try {
      debugPrint('Opening device $index...');
      
      if (isAndroidPlatform) {
        final result = await _channel.invokeMethod<bool>('openDevice', {'index': index});
        _deviceOpened = result ?? false;
        
        if (_deviceOpened) {
          // Start capture immediately on Android
          await _channel.invokeMethod('startCapture');
          
          // Get device info
          final info = await _channel.invokeMethod<Map>('getDeviceInfo');
          if (info != null) {
            _serialNumber = info['serialNumber'] as String?;
          }
        }
        
        debugPrint('Android device opened: $_deviceOpened');
        return _deviceOpened;
      } else {
        // Windows FFI
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
      }
    } catch (e) {
      debugPrint('Open device error: $e');
      return false;
    }
  }

  /// Close the currently open device
  Future<void> closeDevice() async {
    try {
      if (isAndroidPlatform) {
        await _channel.invokeMethod('stopCapture');
        await _channel.invokeMethod('closeDevice');
      } else if (_sdk != null && _deviceOpened) {
        _sdk!.dbFree();
        _sdk!.closeDevice();
      }
    } catch (e) {
      debugPrint('closeDevice error: $e');
    }
    
    _deviceOpened = false;
    _serialNumber = null;
    _enrollmentTemplates.clear();
    _enrollmentCount = 0;
    _lastCapturedImage = null;
    _lastTemplate = null;
    debugPrint('Device closed');
  }

  /// Legacy connect method (combines initSdk + openDevice)
  Future<bool> connect() async {
    if (!await initSdk()) return false;
    
    final count = await getDeviceCountAsync();
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
    if (!_deviceOpened) return null;
    return _serialNumber;
  }

  /// Get firmware version info
  Future<String?> getVersion() async {
    if (!_deviceOpened) return null;
    
    if (isAndroidPlatform) {
      try {
        final info = await _channel.invokeMethod<Map>('getDeviceInfo');
        return info?['sdkVersion'] as String?;
      } catch (e) {
        return 'ZKFinger Android SDK';
      }
    }
    
    return 'ZKFinger SDK 5.3.0.33';
  }

  /// Capture fingerprint (Windows: active capture, Android: returns last captured)
  Future<Uint8List?> captureFingerprint() async {
    if (!_deviceOpened) return null;
    
    try {
      if (isAndroidPlatform) {
        // On Android, capture is event-based - return last template
        // Wait a bit for capture if not available
        if (_lastTemplate == null) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
        // Clear the template after returning to prevent false detections
        final template = _lastTemplate;
        _lastTemplate = null;
        return template;
      } else {
        // Windows: Poll for fingerprint with strict timeout
        debugPrint('Waiting for fingerprint...');
        
        const maxAttempts = 100; // 10 seconds at 100ms intervals
        int consecutiveErrors = 0;
        const maxConsecutiveErrors = 10; // Stop after 10 consecutive errors
        
        for (int attempt = 0; attempt < maxAttempts; attempt++) {
          final result = _sdk!.acquireFingerprint();
          
          if (result.error == ZkfpErrors.OK && result.template != null) {
            debugPrint('Fingerprint captured! Template size: ${result.template!.length} bytes');
            
            if (result.image != null) {
              _lastCapturedImage = result.image;
            }
            _lastTemplate = result.template;
            consecutiveErrors = 0;
            
            return result.template;
          }
          
          // Count consecutive errors
          if (result.error != ZkfpErrors.OK) {
            consecutiveErrors++;
            // Exit early if too many consecutive errors (likely no finger)
            if (consecutiveErrors >= maxConsecutiveErrors) {
              debugPrint('Fingerprint capture: No finger detected (error count: $consecutiveErrors)');
              return null;
            }
          } else {
            consecutiveErrors = 0;
          }
          
          if (result.error == ZkfpErrors.BUSY || 
              result.error == ZkfpErrors.CAPTURE) {
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          }
          
          await Future.delayed(const Duration(milliseconds: 100));
        }
        
        debugPrint('Fingerprint capture timeout after $maxAttempts attempts');
        return null;
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      return null;
    }
  }

  /// Single capture attempt (non-blocking, Windows only)
  ({Uint8List? image, Uint8List? template, int error}) acquireFingerprintOnce() {
    if (!_deviceOpened || _sdk == null || isAndroidPlatform) {
      return (image: _lastCapturedImage, template: _lastTemplate, error: isAndroidPlatform ? 0 : ZkfpErrors.INVALID_HANDLE);
    }
    final result = _sdk!.acquireFingerprint();
    if (result.image != null) {
      _lastCapturedImage = result.image;
    }
    if (result.template != null) {
      _lastTemplate = result.template;
    }
    return result;
  }

  // ==================== Enrollment ====================

  /// Start enrollment on Android
  Future<bool> startEnrollmentAndroid(String fid) async {
    if (!isAndroidPlatform || !_deviceOpened) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('startEnroll', {'fid': fid});
      return result ?? false;
    } catch (e) {
      debugPrint('startEnrollmentAndroid error: $e');
      return false;
    }
  }

  /// Cancel enrollment on Android
  Future<bool> cancelEnrollmentAndroid() async {
    if (!isAndroidPlatform) return false;
    
    try {
      await _channel.invokeMethod('cancelEnroll');
      return true;
    } catch (e) {
      debugPrint('cancelEnrollmentAndroid error: $e');
      return false;
    }
  }

  /// Merge three enrollment captures into a single template.
  Future<Uint8List?> mergeEnrollmentTemplates(
    Uint8List template1,
    Uint8List template2,
    Uint8List template3,
  ) async {
    if (!_deviceOpened) return null;

    try {
      if (isAndroidPlatform) {
        final result = await _channel.invokeMethod<Map>(
          'mergeTemplatesForEnroll',
          {
            'template1': base64Encode(template1),
            'template2': base64Encode(template2),
            'template3': base64Encode(template3),
          },
        );
        if (result == null) return null;
        final map = Map<String, dynamic>.from(result);
        final success = map['success'] == true;
        final mergedBase64 = map['template'] as String?;
        if (!success || mergedBase64 == null || mergedBase64.isEmpty) {
          return null;
        }
        return base64Decode(mergedBase64);
      }

      if (_sdk != null) {
        return _sdk!.dbMerge(template1, template2, template3);
      }
    } catch (e) {
      debugPrint('mergeEnrollmentTemplates error: $e');
    }

    return null;
  }

  /// Start enrollment process (Windows)
  void startEnrollment() {
    _enrollmentTemplates.clear();
    _enrollmentCount = 0;
    debugPrint('Enrollment started - please capture 3 fingerprints');
  }

  /// Capture fingerprint for enrollment (Windows, need to capture 3 times)
  Future<({int count, Uint8List? mergedTemplate, String? error})> captureForEnrollment() async {
    if (!_deviceOpened || _sdk == null || isAndroidPlatform) {
      return (count: 0, mergedTemplate: null, error: 'Not connected or wrong platform');
    }

    final template = await captureFingerprint();
    if (template == null) {
      return (count: _enrollmentCount, mergedTemplate: null, error: 'Capture failed');
    }

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

  // ==================== Database Operations ====================

  /// Register a fingerprint to the database
  Future<bool> registerFingerprint(int fingerId, Uint8List template) async {
    if (!_deviceOpened) return false;
    
    try {
      if (isAndroidPlatform) {
        final templateBase64 = base64Encode(template);
        final result = await _channel.invokeMethod<bool>('addTemplate', {
          'fid': fingerId.toString(),
          'template': templateBase64,
        });
        return result ?? false;
      } else if (_sdk != null) {
        final result = _sdk!.dbAdd(fingerId, template);
        if (result == ZkfpErrors.OK) {
          debugPrint('Fingerprint registered for ID: $fingerId');
          return true;
        } else {
          debugPrint('Failed to register fingerprint: ${ZkfpErrors.getMessage(result)}');
          return false;
        }
      }
    } catch (e) {
      debugPrint('registerFingerprint error: $e');
    }
    
    return false;
  }

  /// Identify fingerprint against database (1:N matching)
  Future<({String? fid, int? score, bool found})> identifyFingerprint() async {
    if (!_deviceOpened) {
      return (fid: null, score: null, found: false);
    }
    
    try {
      if (isAndroidPlatform) {
        final result = await _channel.invokeMethod<Map>('identify');
        if (result != null) {
          final found = result['found'] as bool? ?? false;
          if (found) {
            return (
              fid: result['fid'] as String?,
              score: result['score'] as int?,
              found: true,
            );
          }
        }
        return (fid: null, score: null, found: false);
      } else if (_sdk != null) {
        final template = await captureFingerprint();
        if (template == null) {
          return (fid: null, score: null, found: false);
        }
        
        final result = _sdk!.dbIdentify(template);
        if (result.error == ZkfpErrors.OK && result.fingerId != null) {
          return (
            fid: result.fingerId.toString(),
            score: result.score,
            found: true,
          );
        }
      }
    } catch (e) {
      debugPrint('identifyFingerprint error: $e');
    }
    
    return (fid: null, score: null, found: false);
  }

  /// Identify a template against database (Windows only)
  ({int? fingerId, int? score, int error}) identifyTemplate(Uint8List template) {
    if (!_deviceOpened || _sdk == null || isAndroidPlatform) {
      return (fingerId: null, score: null, error: ZkfpErrors.INVALID_HANDLE);
    }
    return _sdk!.dbIdentify(template);
  }

  /// Verify fingerprint against a specific ID
  Future<({bool match, int? score})> verifyFingerprint(String fid) async {
    if (!_deviceOpened) {
      return (match: false, score: null);
    }
    
    try {
      if (isAndroidPlatform) {
        final result = await _channel.invokeMethod<Map>('verify', {'fid': fid});
        if (result != null) {
          return (
            match: result['match'] as bool? ?? false,
            score: result['score'] as int?,
          );
        }
      }
    } catch (e) {
      debugPrint('verifyFingerprint error: $e');
    }
    
    return (match: false, score: null);
  }

  /// Match two templates (Windows only)
  int matchTemplates(Uint8List template1, Uint8List template2) {
    if (!_deviceOpened || _sdk == null || isAndroidPlatform) return -1;
    return _sdk!.dbMatch(template1, template2);
  }

  /// Match two templates across supported platforms.
  /// Returns null when matching is unavailable.
  Future<int?> matchTemplatesAsync(
      Uint8List template1, Uint8List template2) async {
    if (!_deviceOpened) return null;

    try {
      if (isAndroidPlatform) {
        try {
          final score = await _channel.invokeMethod<int>('matchTemplates', {
            'template1': base64Encode(template1),
            'template2': base64Encode(template2),
          });
          if (score != null) return score;
        } catch (_) {
          // Fall through to compatibility path for older native plugin builds.
        }

        // Compatibility fallback: add template1 to the SDK DB temporarily and
        // verify it against the current captured template (held by native side).
        final tempFid = '__tmp_match_${DateTime.now().microsecondsSinceEpoch}';
        final addOk = await _channel.invokeMethod<bool>('addTemplate', {
          'fid': tempFid,
          'template': base64Encode(template1),
        });
        if (addOk != true) return null;

        try {
          final verifyResult = await _channel.invokeMethod<Map>('verify', {
            'fid': tempFid,
          });
          if (verifyResult == null) return null;
          final map = Map<String, dynamic>.from(verifyResult);
          final rawScore = map['score'];
          if (rawScore is int) return rawScore;
          if (rawScore is num) return rawScore.toInt();
          return (map['match'] == true) ? 1 : 0;
        } finally {
          await _channel.invokeMethod<bool>('removeTemplate', {'fid': tempFid});
        }
      } else if (_sdk != null) {
        return _sdk!.dbMatch(template1, template2);
      }
    } catch (e) {
      debugPrint('matchTemplatesAsync error: $e');
    }

    return null;
  }

  /// Get number of fingerprints in database
  Future<int> getDatabaseCountAsync() async {
    if (!_deviceOpened) return 0;
    
    try {
      if (isAndroidPlatform) {
        final count = await _channel.invokeMethod<int>('getDbCount');
        return count ?? 0;
      } else if (_sdk != null) {
        return _sdk!.dbCount() ?? 0;
      }
    } catch (e) {
      debugPrint('getDatabaseCount error: $e');
    }
    
    return 0;
  }

  /// Sync version (Windows only)
  int? getDatabaseCount() {
    if (!_deviceOpened || _sdk == null || isAndroidPlatform) return null;
    return _sdk!.dbCount();
  }

  /// Clear all fingerprints from database
  Future<bool> clearDatabase() async {
    if (!_deviceOpened) return false;
    
    try {
      if (isAndroidPlatform) {
        final result = await _channel.invokeMethod<bool>('clearDb');
        return result ?? false;
      } else if (_sdk != null) {
        return _sdk!.dbClear() == ZkfpErrors.OK;
      }
    } catch (e) {
      debugPrint('clearDatabase error: $e');
    }
    
    return false;
  }

  /// Remove a fingerprint from database
  Future<bool> removeFingerprint(String fid) async {
    if (!_deviceOpened) return false;
    
    try {
      if (isAndroidPlatform) {
        final result = await _channel.invokeMethod<bool>('removeTemplate', {'fid': fid});
        return result ?? false;
      } else if (_sdk != null) {
        final fingerId = int.tryParse(fid);
        if (fingerId != null) {
          return _sdk!.dbDel(fingerId) == ZkfpErrors.OK;
        }
      }
    } catch (e) {
      debugPrint('removeFingerprint error: $e');
    }
    
    return false;
  }

  /// Dispose resources
  void dispose() {
    _attendanceController.close();
    disconnect();
  }
}
