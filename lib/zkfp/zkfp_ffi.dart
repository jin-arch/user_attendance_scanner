import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// Error codes
class ZkfpErrors {
  static const int OK = 0;
  static const int ALREADY_INIT = 1;
  static const int INITLIB = -1;
  static const int INIT = -2;
  static const int NO_DEVICE = -3;
  static const int NOT_SUPPORT = -4;
  static const int INVALID_PARAM = -5;
  static const int OPEN = -6;
  static const int INVALID_HANDLE = -7;
  static const int CAPTURE = -8;
  static const int EXTRACT_FP = -9;
  static const int ABSORT = -10;
  static const int MEMORY_NOT_ENOUGH = -11;
  static const int BUSY = -12;
  static const int ADD_FINGER = -13;
  static const int DEL_FINGER = -14;
  static const int FAIL = -17;
  static const int CANCEL = -18;
  static const int VERIFY_FP = -20;
  static const int MERGE = -22;

  static String getMessage(int code) {
    switch (code) {
      case OK: return 'Success';
      case ALREADY_INIT: return 'Already initialized';
      case INITLIB: return 'Failed to initialize algorithm library';
      case INIT: return 'Failed to initialize capture';
      case NO_DEVICE: return 'No device connected';
      case NOT_SUPPORT: return 'Not supported';
      case INVALID_PARAM: return 'Invalid parameter';
      case OPEN: return 'Failed to open device';
      case INVALID_HANDLE: return 'Invalid handle';
      case CAPTURE: return 'Capture failed';
      case EXTRACT_FP: return 'Failed to extract fingerprint template';
      case ABSORT: return 'Aborted';
      case MEMORY_NOT_ENOUGH: return 'Memory not enough';
      case BUSY: return 'Device busy - capture in progress';
      case ADD_FINGER: return 'Failed to add fingerprint template';
      case DEL_FINGER: return 'Failed to delete fingerprint';
      case FAIL: return 'Operation failed';
      case CANCEL: return 'Capture cancelled';
      case VERIFY_FP: return 'Fingerprint verification failed';
      case MERGE: return 'Failed to merge templates';
      default: return 'Unknown error: $code';
    }
  }
}

// Parameter codes
class ZkfpParams {
  static const int IMAGE_WIDTH = 1;
  static const int IMAGE_HEIGHT = 2;
  static const int IMAGE_DPI = 3;
  static const int SERIAL_NUMBER = 1101;
  static const int FP_THRESHOLD = 1;      // 1:1 threshold
  static const int FP_MTHRESHOLD = 2;     // 1:N threshold
}

// Constants
const int MAX_TEMPLATE_SIZE = 2048;

// FFI typedefs
typedef ZKFPM_InitNative = Int32 Function();
typedef ZKFPM_InitDart = int Function();

typedef ZKFPM_TerminateNative = Int32 Function();
typedef ZKFPM_TerminateDart = int Function();

typedef ZKFPM_GetDeviceCountNative = Int32 Function();
typedef ZKFPM_GetDeviceCountDart = int Function();

typedef ZKFPM_OpenDeviceNative = IntPtr Function(Int32 index);
typedef ZKFPM_OpenDeviceDart = int Function(int index);

typedef ZKFPM_CloseDeviceNative = Int32 Function(IntPtr hDevice);
typedef ZKFPM_CloseDeviceDart = int Function(int hDevice);

typedef ZKFPM_GetParametersNative = Int32 Function(
  IntPtr hDevice,
  Int32 paramCode,
  Pointer<Uint8> paramValue,
  Pointer<Uint32> cbParamValue,
);
typedef ZKFPM_GetParametersDart = int Function(
  int hDevice,
  int paramCode,
  Pointer<Uint8> paramValue,
  Pointer<Uint32> cbParamValue,
);

typedef ZKFPM_AcquireFingerprintNative = Int32 Function(
  IntPtr hDevice,
  Pointer<Uint8> fpImage,
  Uint32 cbFPImage,
  Pointer<Uint8> fpTemplate,
  Pointer<Uint32> cbTemplate,
);
typedef ZKFPM_AcquireFingerprintDart = int Function(
  int hDevice,
  Pointer<Uint8> fpImage,
  int cbFPImage,
  Pointer<Uint8> fpTemplate,
  Pointer<Uint32> cbTemplate,
);

typedef ZKFPM_DBInitNative = IntPtr Function();
typedef ZKFPM_DBInitDart = int Function();

typedef ZKFPM_DBFreeNative = Int32 Function(IntPtr hDBCache);
typedef ZKFPM_DBFreeDart = int Function(int hDBCache);

typedef ZKFPM_DBAddNative = Int32 Function(
  IntPtr hDBCache,
  Uint32 fid,
  Pointer<Uint8> fpTemplate,
  Uint32 cbTemplate,
);
typedef ZKFPM_DBAddDart = int Function(
  int hDBCache,
  int fid,
  Pointer<Uint8> fpTemplate,
  int cbTemplate,
);

typedef ZKFPM_DBDelNative = Int32 Function(IntPtr hDBCache, Uint32 fid);
typedef ZKFPM_DBDelDart = int Function(int hDBCache, int fid);

typedef ZKFPM_DBClearNative = Int32 Function(IntPtr hDBCache);
typedef ZKFPM_DBClearDart = int Function(int hDBCache);

typedef ZKFPM_DBCountNative = Int32 Function(IntPtr hDBCache, Pointer<Uint32> fpCount);
typedef ZKFPM_DBCountDart = int Function(int hDBCache, Pointer<Uint32> fpCount);

typedef ZKFPM_DBIdentifyNative = Int32 Function(
  IntPtr hDBCache,
  Pointer<Uint8> fpTemplate,
  Uint32 cbTemplate,
  Pointer<Uint32> fid,
  Pointer<Uint32> score,
);
typedef ZKFPM_DBIdentifyDart = int Function(
  int hDBCache,
  Pointer<Uint8> fpTemplate,
  int cbTemplate,
  Pointer<Uint32> fid,
  Pointer<Uint32> score,
);

typedef ZKFPM_DBMatchNative = Int32 Function(
  IntPtr hDBCache,
  Pointer<Uint8> template1,
  Uint32 cbTemplate1,
  Pointer<Uint8> template2,
  Uint32 cbTemplate2,
);
typedef ZKFPM_DBMatchDart = int Function(
  int hDBCache,
  Pointer<Uint8> template1,
  int cbTemplate1,
  Pointer<Uint8> template2,
  int cbTemplate2,
);

typedef ZKFPM_DBMergeNative = Int32 Function(
  IntPtr hDBCache,
  Pointer<Uint8> temp1,
  Pointer<Uint8> temp2,
  Pointer<Uint8> temp3,
  Pointer<Uint8> regTemp,
  Pointer<Uint32> cbRegTemp,
);
typedef ZKFPM_DBMergeDart = int Function(
  int hDBCache,
  Pointer<Uint8> temp1,
  Pointer<Uint8> temp2,
  Pointer<Uint8> temp3,
  Pointer<Uint8> regTemp,
  Pointer<Uint32> cbRegTemp,
);

/// ZKTeco Fingerprint SDK wrapper class
class ZkfpSdk {
  late final DynamicLibrary _lib;
  
  late final ZKFPM_InitDart _init;
  late final ZKFPM_TerminateDart _terminate;
  late final ZKFPM_GetDeviceCountDart _getDeviceCount;
  late final ZKFPM_OpenDeviceDart _openDevice;
  late final ZKFPM_CloseDeviceDart _closeDevice;
  late final ZKFPM_GetParametersDart _getParameters;
  late final ZKFPM_AcquireFingerprintDart _acquireFingerprint;
  late final ZKFPM_DBInitDart _dbInit;
  late final ZKFPM_DBFreeDart _dbFree;
  late final ZKFPM_DBAddDart _dbAdd;
  late final ZKFPM_DBDelDart _dbDel;
  late final ZKFPM_DBClearDart _dbClear;
  late final ZKFPM_DBCountDart _dbCount;
  late final ZKFPM_DBIdentifyDart _dbIdentify;
  late final ZKFPM_DBMatchDart _dbMatch;
  late final ZKFPM_DBMergeDart _dbMerge;

  bool _initialized = false;
  int _deviceHandle = 0;
  int _dbHandle = 0;
  int _imageWidth = 0;
  int _imageHeight = 0;

  bool get isInitialized => _initialized;
  bool get isDeviceOpen => _deviceHandle != 0;
  int get imageWidth => _imageWidth;
  int get imageHeight => _imageHeight;

  ZkfpSdk() {
    _lib = DynamicLibrary.open('libzkfp.dll');
    _loadFunctions();
  }

  void _loadFunctions() {
    _init = _lib.lookupFunction<ZKFPM_InitNative, ZKFPM_InitDart>('ZKFPM_Init');
    _terminate = _lib.lookupFunction<ZKFPM_TerminateNative, ZKFPM_TerminateDart>('ZKFPM_Terminate');
    _getDeviceCount = _lib.lookupFunction<ZKFPM_GetDeviceCountNative, ZKFPM_GetDeviceCountDart>('ZKFPM_GetDeviceCount');
    _openDevice = _lib.lookupFunction<ZKFPM_OpenDeviceNative, ZKFPM_OpenDeviceDart>('ZKFPM_OpenDevice');
    _closeDevice = _lib.lookupFunction<ZKFPM_CloseDeviceNative, ZKFPM_CloseDeviceDart>('ZKFPM_CloseDevice');
    _getParameters = _lib.lookupFunction<ZKFPM_GetParametersNative, ZKFPM_GetParametersDart>('ZKFPM_GetParameters');
    _acquireFingerprint = _lib.lookupFunction<ZKFPM_AcquireFingerprintNative, ZKFPM_AcquireFingerprintDart>('ZKFPM_AcquireFingerprint');
    _dbInit = _lib.lookupFunction<ZKFPM_DBInitNative, ZKFPM_DBInitDart>('ZKFPM_DBInit');
    _dbFree = _lib.lookupFunction<ZKFPM_DBFreeNative, ZKFPM_DBFreeDart>('ZKFPM_DBFree');
    _dbAdd = _lib.lookupFunction<ZKFPM_DBAddNative, ZKFPM_DBAddDart>('ZKFPM_DBAdd');
    _dbDel = _lib.lookupFunction<ZKFPM_DBDelNative, ZKFPM_DBDelDart>('ZKFPM_DBDel');
    _dbClear = _lib.lookupFunction<ZKFPM_DBClearNative, ZKFPM_DBClearDart>('ZKFPM_DBClear');
    _dbCount = _lib.lookupFunction<ZKFPM_DBCountNative, ZKFPM_DBCountDart>('ZKFPM_DBCount');
    _dbIdentify = _lib.lookupFunction<ZKFPM_DBIdentifyNative, ZKFPM_DBIdentifyDart>('ZKFPM_DBIdentify');
    _dbMatch = _lib.lookupFunction<ZKFPM_DBMatchNative, ZKFPM_DBMatchDart>('ZKFPM_DBMatch');
    _dbMerge = _lib.lookupFunction<ZKFPM_DBMergeNative, ZKFPM_DBMergeDart>('ZKFPM_DBMerge');
  }

  /// Initialize the SDK
  int init() {
    final result = _init();
    if (result == ZkfpErrors.OK || result == ZkfpErrors.ALREADY_INIT) {
      _initialized = true;
    }
    return result;
  }

  /// Terminate the SDK
  int terminate() {
    if (_deviceHandle != 0) {
      closeDevice();
    }
    if (_dbHandle != 0) {
      dbFree();
    }
    final result = _terminate();
    _initialized = false;
    return result;
  }

  /// Get number of connected devices
  int getDeviceCount() {
    return _getDeviceCount();
  }

  /// Open device by index
  int openDevice(int index) {
    _deviceHandle = _openDevice(index);
    if (_deviceHandle != 0) {
      // Get image dimensions
      _imageWidth = getParameterInt(ZkfpParams.IMAGE_WIDTH) ?? 0;
      _imageHeight = getParameterInt(ZkfpParams.IMAGE_HEIGHT) ?? 0;
    }
    return _deviceHandle;
  }

  /// Close currently open device
  int closeDevice() {
    if (_deviceHandle == 0) return ZkfpErrors.OK;
    final result = _closeDevice(_deviceHandle);
    _deviceHandle = 0;
    _imageWidth = 0;
    _imageHeight = 0;
    return result;
  }

  /// Get parameter as integer
  int? getParameterInt(int paramCode) {
    final paramValue = calloc<Uint8>(4);
    final paramSize = calloc<Uint32>();
    paramSize.value = 4;
    
    final result = _getParameters(_deviceHandle, paramCode, paramValue, paramSize);
    
    int? value;
    if (result == ZkfpErrors.OK) {
      // Convert 4 bytes to int (little-endian)
      value = paramValue[0] | 
              (paramValue[1] << 8) | 
              (paramValue[2] << 16) | 
              (paramValue[3] << 24);
    }
    
    calloc.free(paramValue);
    calloc.free(paramSize);
    return value;
  }

  /// Get parameter as string (for serial number)
  String? getParameterString(int paramCode) {
    final paramValue = calloc<Uint8>(256);
    final paramSize = calloc<Uint32>();
    paramSize.value = 256;
    
    final result = _getParameters(_deviceHandle, paramCode, paramValue, paramSize);
    
    String? value;
    if (result == ZkfpErrors.OK && paramSize.value > 0) {
      // Convert null-terminated bytes to string
      final bytes = <int>[];
      for (int i = 0; i < paramSize.value; i++) {
        if (paramValue[i] == 0) break;
        bytes.add(paramValue[i]);
      }
      value = String.fromCharCodes(bytes);
    }
    
    calloc.free(paramValue);
    calloc.free(paramSize);
    return value;
  }

  /// Acquire fingerprint image and template
  /// Returns (image, template) or null on failure
  ({Uint8List? image, Uint8List? template, int error}) acquireFingerprint() {
    if (_deviceHandle == 0 || _imageWidth == 0 || _imageHeight == 0) {
      return (image: null, template: null, error: ZkfpErrors.INVALID_HANDLE);
    }

    final imageSize = _imageWidth * _imageHeight;
    final fpImage = calloc<Uint8>(imageSize);
    final fpTemplate = calloc<Uint8>(MAX_TEMPLATE_SIZE);
    final cbTemplate = calloc<Uint32>();
    cbTemplate.value = MAX_TEMPLATE_SIZE;

    final result = _acquireFingerprint(
      _deviceHandle,
      fpImage,
      imageSize,
      fpTemplate,
      cbTemplate,
    );

    Uint8List? imageData;
    Uint8List? templateData;

    if (result == ZkfpErrors.OK) {
      // Copy image data
      imageData = Uint8List(imageSize);
      for (int i = 0; i < imageSize; i++) {
        imageData[i] = fpImage[i];
      }

      // Copy template data
      final templateSize = cbTemplate.value;
      templateData = Uint8List(templateSize);
      for (int i = 0; i < templateSize; i++) {
        templateData[i] = fpTemplate[i];
      }
    }

    calloc.free(fpImage);
    calloc.free(fpTemplate);
    calloc.free(cbTemplate);

    return (image: imageData, template: templateData, error: result);
  }

  /// Initialize fingerprint database/algorithm cache
  int dbInit() {
    _dbHandle = _dbInit();
    return _dbHandle;
  }

  /// Free fingerprint database
  int dbFree() {
    if (_dbHandle == 0) return ZkfpErrors.OK;
    final result = _dbFree(_dbHandle);
    _dbHandle = 0;
    return result;
  }

  /// Add fingerprint template to database
  int dbAdd(int fingerId, Uint8List template) {
    if (_dbHandle == 0) return ZkfpErrors.INVALID_HANDLE;
    
    final fpTemplate = calloc<Uint8>(template.length);
    for (int i = 0; i < template.length; i++) {
      fpTemplate[i] = template[i];
    }
    
    final result = _dbAdd(_dbHandle, fingerId, fpTemplate, template.length);
    calloc.free(fpTemplate);
    return result;
  }

  /// Delete fingerprint from database
  int dbDel(int fingerId) {
    if (_dbHandle == 0) return ZkfpErrors.INVALID_HANDLE;
    return _dbDel(_dbHandle, fingerId);
  }

  /// Clear all fingerprints from database
  int dbClear() {
    if (_dbHandle == 0) return ZkfpErrors.INVALID_HANDLE;
    return _dbClear(_dbHandle);
  }

  /// Get count of fingerprints in database
  int? dbCount() {
    if (_dbHandle == 0) return null;
    final count = calloc<Uint32>();
    final result = _dbCount(_dbHandle, count);
    final value = result == ZkfpErrors.OK ? count.value : null;
    calloc.free(count);
    return value;
  }

  /// Identify fingerprint against database (1:N matching)
  /// Returns (fingerId, score) or null if not found
  ({int? fingerId, int? score, int error}) dbIdentify(Uint8List template) {
    if (_dbHandle == 0) {
      return (fingerId: null, score: null, error: ZkfpErrors.INVALID_HANDLE);
    }

    final fpTemplate = calloc<Uint8>(template.length);
    for (int i = 0; i < template.length; i++) {
      fpTemplate[i] = template[i];
    }
    
    final fid = calloc<Uint32>();
    final score = calloc<Uint32>();
    
    final result = _dbIdentify(_dbHandle, fpTemplate, template.length, fid, score);
    
    int? fingerId;
    int? scoreValue;
    if (result == ZkfpErrors.OK) {
      fingerId = fid.value;
      scoreValue = score.value;
    }
    
    calloc.free(fpTemplate);
    calloc.free(fid);
    calloc.free(score);
    
    return (fingerId: fingerId, score: scoreValue, error: result);
  }

  /// Match two fingerprint templates (1:1 matching)
  /// Returns match score (>0 if matched) or error (<0)
  int dbMatch(Uint8List template1, Uint8List template2) {
    if (_dbHandle == 0) return ZkfpErrors.INVALID_HANDLE;
    
    final t1 = calloc<Uint8>(template1.length);
    final t2 = calloc<Uint8>(template2.length);
    
    for (int i = 0; i < template1.length; i++) {
      t1[i] = template1[i];
    }
    for (int i = 0; i < template2.length; i++) {
      t2[i] = template2[i];
    }
    
    final result = _dbMatch(_dbHandle, t1, template1.length, t2, template2.length);
    
    calloc.free(t1);
    calloc.free(t2);
    
    return result;
  }

  /// Merge 3 fingerprint templates into 1 registration template
  Uint8List? dbMerge(Uint8List template1, Uint8List template2, Uint8List template3) {
    if (_dbHandle == 0) return null;
    
    final t1 = calloc<Uint8>(template1.length);
    final t2 = calloc<Uint8>(template2.length);
    final t3 = calloc<Uint8>(template3.length);
    final regTemp = calloc<Uint8>(MAX_TEMPLATE_SIZE);
    final cbRegTemp = calloc<Uint32>();
    cbRegTemp.value = MAX_TEMPLATE_SIZE;
    
    for (int i = 0; i < template1.length; i++) {
      t1[i] = template1[i];
    }
    for (int i = 0; i < template2.length; i++) {
      t2[i] = template2[i];
    }
    for (int i = 0; i < template3.length; i++) {
      t3[i] = template3[i];
    }
    
    final result = _dbMerge(_dbHandle, t1, t2, t3, regTemp, cbRegTemp);
    
    Uint8List? merged;
    if (result == ZkfpErrors.OK) {
      final size = cbRegTemp.value;
      merged = Uint8List(size);
      for (int i = 0; i < size; i++) {
        merged[i] = regTemp[i];
      }
    }
    
    calloc.free(t1);
    calloc.free(t2);
    calloc.free(t3);
    calloc.free(regTemp);
    calloc.free(cbRegTemp);
    
    return merged;
  }

  /// Get the serial number of the connected device
  String? getSerialNumber() {
    return getParameterString(ZkfpParams.SERIAL_NUMBER);
  }
}
