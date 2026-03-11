import 'dart:typed_data';

/// Stub implementation of ZkfpSdk for platforms that don't support dart:ffi (e.g., web).
/// All operations return error codes indicating unsupported platform.

// Error codes (mirrored from zkfp_ffi.dart)
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

class ZkfpParams {
  static const int IMAGE_WIDTH = 1;
  static const int IMAGE_HEIGHT = 2;
  static const int IMAGE_DPI = 3;
  static const int SERIAL_NUMBER = 1101;
  static const int FP_THRESHOLD = 1;
  static const int FP_MTHRESHOLD = 2;
}

const int MAX_TEMPLATE_SIZE = 2048;

class ZkfpSdk {
  bool get isInitialized => false;
  bool get isDeviceOpen => false;
  int get imageWidth => 0;
  int get imageHeight => 0;

  int init() => ZkfpErrors.NOT_SUPPORT;
  int terminate() => ZkfpErrors.OK;
  int getDeviceCount() => 0;
  int openDevice(int index) => 0;
  int closeDevice() => ZkfpErrors.OK;
  int? getParameterInt(int paramCode) => null;
  String? getParameterString(int paramCode) => null;

  ({Uint8List? image, Uint8List? template, int error}) acquireFingerprint() {
    return (image: null, template: null, error: ZkfpErrors.NOT_SUPPORT);
  }

  int dbInit() => 0;
  int dbFree() => ZkfpErrors.OK;
  int dbAdd(int fingerId, Uint8List template) => ZkfpErrors.NOT_SUPPORT;
  int dbDel(int fingerId) => ZkfpErrors.NOT_SUPPORT;
  int dbClear() => ZkfpErrors.NOT_SUPPORT;
  int? dbCount() => null;

  ({int? fingerId, int? score, int error}) dbIdentify(Uint8List template) {
    return (fingerId: null, score: null, error: ZkfpErrors.NOT_SUPPORT);
  }

  int dbMatch(Uint8List template1, Uint8List template2) => ZkfpErrors.NOT_SUPPORT;
  Uint8List? dbMerge(Uint8List template1, Uint8List template2, Uint8List template3) => null;
  String? getSerialNumber() => null;
}
