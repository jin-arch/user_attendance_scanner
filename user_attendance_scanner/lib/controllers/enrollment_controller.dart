import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../zkfp/zkteco_usb.dart';
import '../services/local_db.dart';

class EnrollmentController extends GetxController {
  final ZKTecoUSB _device = ZKTecoUSB();

  final deviceInitialized = ValueNotifier<bool>(false);
  final isScanning = ValueNotifier<bool>(false);
  final lastFingerprintImage = ValueNotifier<Uint8List?>(null);

  final TextEditingController idController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final showForm = ValueNotifier<bool>(false);
  final selfieImageBytes = ValueNotifier<Uint8List?>(null);

  final leftThumbScans = ValueNotifier<int>(0);
  final rightThumbScans = ValueNotifier<int>(0);
  final leftThumbScansList = <Uint8List>[];
  final rightThumbScansList = <Uint8List>[];

  static const int scansPerFinger = 3;
  static const int minTimeBetweenScansMs = 800;

  Timer? _scanTimer;
  DateTime? _lastScanTime;

  Function(String)? onError;
  Function(String)? onSuccess;

  final String? siteId;
  final bool isEditMode;
  final String? employeeId;
  final String? employeeName;

  EnrollmentController({
    this.siteId,
    this.isEditMode = false,
    this.employeeId,
    this.employeeName,
  });

  @override
  void onInit() {
    super.onInit();
    _initialize();
  }

  void _initialize() {
    idController.addListener(_onFormChanged);
    usernameController.addListener(_onFormChanged);
    _prefillEmployeeDetails();
    _loadEmployeePhoto();
    _clearScanState();
    _device.clearCachedCapture();
    _initDevice();
  }

  @override
  void onClose() {
    idController.removeListener(_onFormChanged);
    usernameController.removeListener(_onFormChanged);
    idController.dispose();
    usernameController.dispose();
    _stopScanLoop();
    _device.clearCachedCapture();

    deviceInitialized.dispose();
    isScanning.dispose();
    lastFingerprintImage.dispose();
    showForm.dispose();
    selfieImageBytes.dispose();
    leftThumbScans.dispose();
    rightThumbScans.dispose();

    super.onClose();
  }

  void _onFormChanged() {
    if (!isEditMode) return;

    final currentId = idController.text.trim();
    if (currentId.isEmpty) {
      if (selfieImageBytes.value != null) {
        selfieImageBytes.value = null;
      }
    } else {
      _loadEmployeePhotoForId(currentId);
    }
  }

  void _prefillEmployeeDetails() {
    if (employeeId != null && employeeId!.isNotEmpty) {
      idController.text = employeeId!;
    }
    if (employeeName != null && employeeName!.isNotEmpty) {
      usernameController.text = employeeName!;
    }
    if ((employeeId != null && employeeId!.isNotEmpty) ||
        (employeeName != null && employeeName!.isNotEmpty)) {
      showForm.value = true;
    }
  }

  Future<void> _loadEmployeePhoto() async {
    if (!isEditMode) {
      selfieImageBytes.value = null;
      return;
    }

    final empId = employeeId?.trim();
    if (empId == null || empId.isEmpty) {
      selfieImageBytes.value = null;
      return;
    }
    final site = siteId ?? 'default';
    final photo = await LocalDb.getEmployeePhoto(
      employeeId: empId,
      siteId: site,
    );
    selfieImageBytes.value = photo;
  }

  Future<void> _loadEmployeePhotoForId(String empId) async {
    final site = siteId ?? 'default';
    final photo = await LocalDb.getEmployeePhoto(
      employeeId: empId,
      siteId: site,
    );
    selfieImageBytes.value = photo;
  }

  Future<void> _initDevice() async {
    try {
      final env = await _device.getAndroidSdkEnvironment();
      if (env['canUseSdk'] != true) {
        debugPrint('SDK not compatible: ${env['reason']}');
        onError?.call('SDK not compatible: ${env['reason']}');
        return;
      }

      final initResult = await _device.initSdk();
      if (!initResult) {
        debugPrint('SDK init failed');
        onError?.call('SDK initialization failed');
        return;
      }

      final count = await _device.getDeviceCountAsync();
      if (count == 0) {
        debugPrint('No device found');
        onError?.call('No fingerprint device found');
        await _device.terminateSdk();
        return;
      }

      final opened = await _device.openDevice(0);
      if (!opened) {
        debugPrint('Failed to open device');
        onError?.call('Failed to open fingerprint device');
        return;
      }

      _device.onImageCaptured = (int width, int height, Uint8List imageData) {
        debugPrint('Image captured: ${width}x$height');
        lastFingerprintImage.value = imageData;
      };

      _device.clearCachedCapture();
      _clearScanState();
      deviceInitialized.value = true;
      debugPrint('Device initialized successfully');
      onSuccess?.call('Device ready for fingerprint scanning');
      _startScanLoop();
    } catch (e) {
      debugPrint('Device initialization error: $e');
      onError?.call('Device initialization error: $e');
    }
  }

  void _startScanLoop() {
    if (isScanning.value) return;
    isScanning.value = true;
    debugPrint('Starting enrollment scan loop...');

    _scanTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!isScanning.value || !_device.isConnected) return;

      if (leftThumbScans.value >= scansPerFinger &&
          rightThumbScans.value >= scansPerFinger) {
        _stopScanLoop();
        return;
      }

      try {
        final template = await _device.captureFingerprint();
        if (template != null && template.isNotEmpty) {
          await _onFingerprintCaptured(template);
        }
      } catch (e) {
        // Silent fail
      }
    });
  }

  void _stopScanLoop() {
    _scanTimer?.cancel();
    _scanTimer = null;
    isScanning.value = false;
  }

  Future<void> _onFingerprintCaptured(Uint8List template) async {
    final isLeftTurn = leftThumbScans.value < scansPerFinger;
    final isRightTurn = rightThumbScans.value < scansPerFinger;

    final now = DateTime.now();
    if (_lastScanTime != null) {
      final diff = now.difference(_lastScanTime!).inMilliseconds;
      if (diff < minTimeBetweenScansMs) {
        // Ignore duplicate captures fired too quickly while the same finger is held.
        return;
      }
    }

    _lastScanTime = now;

    if (isLeftTurn) {
      if (leftThumbScansList.isNotEmpty) {
        final score = await _device.matchTemplatesAsync(
          leftThumbScansList.first,
          template,
        );
        if (score != null && score <= 0) {
          onError?.call(
              'Different finger detected. Please use the same LEFT thumb.');
          return;
        }
      }
      leftThumbScansList.add(template);
      leftThumbScans.value = leftThumbScans.value + 1;
      debugPrint('Left thumb scan ${leftThumbScans.value}/$scansPerFinger');
    } else if (isRightTurn) {
      if (rightThumbScansList.isEmpty && leftThumbScansList.isNotEmpty) {
        final scoreVsLeft = await _device.matchTemplatesAsync(
          leftThumbScansList.first,
          template,
        );
        if (scoreVsLeft != null && scoreVsLeft > 0) {
          onError?.call(
              'Please use your RIGHT thumb, not the same finger as the left.');
          return;
        }
      }
      if (rightThumbScansList.isNotEmpty) {
        final score = await _device.matchTemplatesAsync(
          rightThumbScansList.first,
          template,
        );
        if (score != null && score <= 0) {
          onError?.call(
              'Different finger detected. Please keep using the same RIGHT thumb.');
          return;
        }
      }
      rightThumbScansList.add(template);
      rightThumbScans.value = rightThumbScans.value + 1;
      debugPrint('Right thumb scan ${rightThumbScans.value}/$scansPerFinger');
    }

    final totalScans = leftThumbScans.value + rightThumbScans.value;
    final isComplete = totalScans >= (scansPerFinger * 2);

    if (isComplete) {
      onSuccess?.call('Both thumbs captured! Enter employee details.');
      showForm.value = true;
    } else if (leftThumbScans.value < scansPerFinger) {
      onSuccess?.call('Left thumb scan ${leftThumbScans.value}/$scansPerFinger captured');
    } else if (rightThumbScans.value == 0) {
      onSuccess?.call('Left thumb complete. Now scan RIGHT thumb 3 times.');
    } else {
      onSuccess?.call('Right thumb scan ${rightThumbScans.value}/$scansPerFinger captured');
    }
  }

  Future<void> takeSelfie() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        selfieImageBytes.value = bytes;
      }
    } catch (e) {
      debugPrint('Error taking selfie: $e');
      onError?.call('Error taking photo: $e');
    }
  }

  void resetFingerprints() {
    _device.clearCachedCapture();
    leftThumbScans.value = 0;
    rightThumbScans.value = 0;
    leftThumbScansList.clear();
    rightThumbScansList.clear();
    lastFingerprintImage.value = null;
    _lastScanTime = null;
    showForm.value = true;
    onSuccess?.call('Enter employee details');
  }

  Future<void> saveEnrollment() async {
    if (idController.text.isEmpty || usernameController.text.isEmpty) {
      onError?.call('Please enter ID and username');
      return;
    }

    if (leftThumbScans.value < scansPerFinger ||
        rightThumbScans.value < scansPerFinger) {
      onError?.call('Please scan each thumb 3 times (3 left, 3 right)');
      return;
    }

    try {
      final site = siteId ?? 'default';
      final empId = idController.text.trim();
      final empName = usernameController.text.trim();

      if (!isEditMode) {
        final existing = await LocalDb.getEmployeesBySite(site);
        final found = existing.any(
          (emp) => emp['employee_id'].toString() == empId,
        );

        if (found) {
          onError?.call('Employee with this ID already exists!');
          return;
        }
      }

      if (isEditMode) {
        await LocalDb.deleteEmployeeFingerprints(
          employeeId: empId,
          siteId: site,
        );
      }

      await _saveFingerTemplates(
        employeeId: empId,
        employeeName: empName,
        siteId: site,
      );

      if (selfieImageBytes.value != null) {
        await LocalDb.upsertEmployeePhoto(
          employeeId: empId,
          siteId: site,
          photo: selfieImageBytes.value!,
        );
      }

      _clearEnrollmentData();

      onSuccess?.call(
        isEditMode
            ? 'Enrollment updated successfully!'
            : 'Enrollment saved successfully!'
      );
    } catch (e) {
      debugPrint('Save error: $e');
      onError?.call('Save failed: $e');
    }
  }

  void _clearEnrollmentData() {
    showForm.value = false;
    leftThumbScans.value = 0;
    rightThumbScans.value = 0;
    leftThumbScansList.clear();
    rightThumbScansList.clear();
    idController.clear();
    usernameController.clear();
    lastFingerprintImage.value = null;
    selfieImageBytes.value = null;
    _lastScanTime = null;
  }

  void _clearScanState() {
    leftThumbScans.value = 0;
    rightThumbScans.value = 0;
    leftThumbScansList.clear();
    rightThumbScansList.clear();
    lastFingerprintImage.value = null;
    _lastScanTime = null;
  }

  Future<void> _saveFingerTemplates({
    required String employeeId,
    required String employeeName,
    required String siteId,
  }) async {
    final leftTemplate = await _resolveEnrollmentTemplate(leftThumbScansList);
    final rightTemplate = await _resolveEnrollmentTemplate(rightThumbScansList);
    if (leftTemplate == null || rightTemplate == null) {
      throw Exception('Unable to prepare fingerprint templates');
    }

    await LocalDb.upsertEmployee(
      fid: _stableFingerprintId(employeeId, 'left'),
      employeeId: employeeId,
      employeeName: employeeName,
      template: leftTemplate,
      siteId: siteId,
    );

    await LocalDb.upsertEmployee(
      fid: _stableFingerprintId(employeeId, 'right'),
      employeeId: employeeId,
      employeeName: employeeName,
      template: rightTemplate,
      siteId: siteId,
    );
  }

  Future<Uint8List?> _resolveEnrollmentTemplate(
      List<Uint8List> captures) async {
    if (captures.isEmpty) return null;
    if (captures.length >= scansPerFinger) {
      final merged = await _device.mergeEnrollmentTemplates(
        captures[0],
        captures[1],
        captures[2],
      );
      if (merged != null && merged.isNotEmpty) {
        return merged;
      }
    }
    return captures.first;
  }

  int _stableFingerprintId(String employeeId, String thumbKey) {
    var hash = 0x811C9DC5;
    final input = '$employeeId:$thumbKey';
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
