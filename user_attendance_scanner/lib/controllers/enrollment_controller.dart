import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../zkfp/zkteco_usb.dart';
import '../services/local_db.dart';

class EnrollmentController extends GetxController {
  // Device management
  final ZKTecoUSB _device = ZKTecoUSB();
  final RxBool deviceInitialized = false.obs;
  final RxBool isScanning = false.obs;
  final Rx<Uint8List?> lastFingerprintImage = Rx<Uint8List?>(null);
  
  // Form fields
  final TextEditingController idController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final RxBool showForm = false.obs;
  final Rx<Uint8List?> selfieImageBytes = Rx<Uint8List?>(null);
  
  // Fingerprint scanning state
  final RxInt leftThumbScans = 0.obs;
  final RxInt rightThumbScans = 0.obs;
  final RxList<Uint8List> leftThumbScansList = <Uint8List>[].obs;
  final RxList<Uint8List> rightThumbScansList = <Uint8List>[].obs;
  final Rxn<DateTime> lastScanTime = Rxn<DateTime>();
  
  // Constants
  static const int scansPerFinger = 3;
  static const int minTimeBetweenScansMs = 800;
  
  // Timer for scan loop
  Timer? _scanTimer;
  
  // Callbacks for UI updates
  VoidCallback? onStateChanged;
  Function(String)? onError;
  Function(String)? onSuccess;
  
  // Constructor parameters
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
  
  String get displayName {
    final fromForm = usernameController.text.trim();
    if (fromForm.isNotEmpty) return fromForm;
    final fromWidget = employeeName?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    return 'UNKNOWN USER';
  }
  
  String get displayId {
    final fromForm = idController.text.trim();
    if (fromForm.isNotEmpty) return fromForm;
    final fromWidget = employeeId?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    return 'N/A';
  }
  
  @override
  void onInit() {
    super.onInit();
    _setupFormListeners();
    _prefillEmployeeDetails();
    _loadEmployeePhoto();
    _clearScanState();
    _device.clearCachedCapture();
    _initDevice();
  }
  
  @override
  void onClose() {
    _removeFormListeners();
    idController.dispose();
    usernameController.dispose();
    _stopScanLoop();
    super.onClose();
  }
  
  void _setupFormListeners() {
    idController.addListener(_onFormChanged);
    usernameController.addListener(_onFormChanged);
  }
  
  void _removeFormListeners() {
    idController.removeListener(_onFormChanged);
    usernameController.removeListener(_onFormChanged);
  }
  
  void _onFormChanged() {
    final currentId = idController.text.trim();
    if (currentId.isEmpty) {
      if (selfieImageBytes.value != null) {
        selfieImageBytes.value = null;
      }
      onStateChanged?.call();
      return;
    }
    _loadEmployeePhotoForId(currentId);
    onStateChanged?.call();
  }
  
  void _prefillEmployeeDetails() {
    final initialId = employeeId?.trim();
    final initialName = employeeName?.trim();
    if (initialId != null && initialId.isNotEmpty) {
      idController.text = initialId;
    }
    if (initialName != null && initialName.isNotEmpty) {
      usernameController.text = initialName;
    }
    if ((initialId != null && initialId.isNotEmpty) ||
        (initialName != null && initialName.isNotEmpty)) {
      showForm.value = true;
    }
  }
  
  Future<void> _loadEmployeePhoto() async {
    final empId = employeeId?.trim();
    if (empId == null || empId.isEmpty) {
      if (selfieImageBytes.value != null) {
        selfieImageBytes.value = null;
      }
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
      debugPrint('Device initialized successfully - starting scan loop...');
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
      
      // Check if enrollment is complete
      if (leftThumbScans.value >= scansPerFinger && rightThumbScans.value >= scansPerFinger) {
        _stopScanLoop();
        return;
      }
      
      try {
        final template = await _device.captureFingerprint();
        if (template != null && template.isNotEmpty) {
          _onFingerprintCaptured(template);
        }
      } catch (e) {
        // Silent fail - keep trying
      }
    });
  }
  
  void _stopScanLoop() {
    _scanTimer?.cancel();
    _scanTimer = null;
    isScanning.value = false;
  }
  
  void _onFingerprintCaptured(Uint8List template) {
    // Determine which thumb we're scanning
    final isLeft = leftThumbScans.value < scansPerFinger;
    final isRight = rightThumbScans.value < scansPerFinger;
    
    // Debounce: prevent same finger from scanning too quickly
    final now = DateTime.now();
    if (lastScanTime.value != null) {
      final diff = now.difference(lastScanTime.value!).inMilliseconds;
      if (diff < minTimeBetweenScansMs) {
        debugPrint('Scan too fast (${diff}ms) - same finger detected, please use different finger');
        onError?.call(isLeft 
          ? 'Left thumb already scanned. Please scan RIGHT thumb now.' 
          : 'Right thumb already scanned. Please scan LEFT thumb now.');
        return;
      }
    }
    lastScanTime.value = now;
    
    if (leftThumbScans.value < scansPerFinger) {
      leftThumbScansList.add(template);
      leftThumbScans.value++;
    } else if (rightThumbScans.value < scansPerFinger) {
      rightThumbScansList.add(template);
      rightThumbScans.value++;
    }
    
    // Show feedback with clear next step
    final totalScans = leftThumbScans.value + rightThumbScans.value;
    final isComplete = totalScans >= (scansPerFinger * 2);
    
    if (isComplete) {
      onSuccess?.call('Both thumbs captured! Enter employee details.');
      showForm.value = true;
    } else if (totalScans == 1) {
      onSuccess?.call('Left thumb captured! Now scan RIGHT thumb.');
    } else {
      onSuccess?.call('Scan $totalScans/${scansPerFinger * 2} complete');
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
    lastScanTime.value = null;
    showForm.value = true;
    onSuccess?.call('Enter employee details');
  }
  
  Future<void> saveEnrollment() async {
    // Validate form
    if (idController.text.isEmpty || usernameController.text.isEmpty) {
      onError?.call('Please enter ID and username');
      return;
    }
    
    // Check if all fingerprints were captured
    if (leftThumbScans.value < scansPerFinger || rightThumbScans.value < scansPerFinger) {
      onError?.call('Please scan each thumb 3 times (3 left, 3 right)');
      return;
    }
    
    try {
      final site = siteId ?? 'default';
      final empId = idController.text.trim();
      final empName = usernameController.text.trim();
      
      debugPrint('Saving enrollment:');
      debugPrint('  ID: $empId');
      debugPrint('  Name: $empName');
      debugPrint('  Site: $site');
      debugPrint('  Left scans: ${leftThumbScansList.length}');
      debugPrint('  Right scans: ${rightThumbScansList.length}');
      
      // Save only 2 templates (1st scan from each finger)
      // fid 1 = left thumb, fid 2 = right thumb
      await LocalDb.upsertEmployee(
        fid: 1,
        employeeId: empId,
        employeeName: empName,
        template: leftThumbScansList[0],
        siteId: site,
      );
      debugPrint('Saved left thumb template');

      await LocalDb.upsertEmployee(
        fid: 2,
        employeeId: empId,
        employeeName: empName,
        template: rightThumbScansList[0],
        siteId: site,
      );
      debugPrint('Saved right thumb template');
      
      if (selfieImageBytes.value != null) {
        await LocalDb.upsertEmployeePhoto(
          employeeId: empId,
          siteId: site,
          photo: selfieImageBytes.value!,
        );
        debugPrint('Saved employee selfie');
      }
      
      // Clear all data after save
      _clearEnrollmentData();
      
      onSuccess?.call(
        isEditMode
            ? 'Enrollment updated successfully! Employee data refreshed.'
            : 'Enrollment saved successfully! Employee registered.'
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
    lastScanTime.value = null;
  }
  
  void _clearScanState() {
    leftThumbScans.value = 0;
    rightThumbScans.value = 0;
    leftThumbScansList.clear();
    rightThumbScansList.clear();
    lastFingerprintImage.value = null;
    lastScanTime.value = null;
  }
  
  String initialsFromName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.toUpperCase() == 'UNKNOWN USER') return '';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}
