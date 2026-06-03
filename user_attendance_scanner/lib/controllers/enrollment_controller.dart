import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/hris_log.dart';
import '../zkfp/zkteco_usb.dart';
import '../services/local_db.dart';
import '../services/pending_sync_service.dart';
import '../services/scanner_registry_service.dart';

/// Returned after fingerprints are stored in the local DB (ready for HRIS upload).
class EnrollmentSaveContext {
  const EnrollmentSaveContext({
    required this.employeeId,
    required this.employeeName,
    required this.siteId,
    required this.leftFingerThumb,
    required this.rightFingerThumb,
  });

  final String employeeId;
  final String employeeName;
  final String siteId;
  final String leftFingerThumb;
  final String rightFingerThumb;
}

class EnrollmentController extends GetxController {
  final ZKTecoUSB _device = ZKTecoUSB();

  final deviceInitialized = ValueNotifier<bool>(false);
  final isScanning = ValueNotifier<bool>(false);
  final lastFingerprintImage = ValueNotifier<Uint8List?>(null);

  final TextEditingController idController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final showForm = ValueNotifier<bool>(false);
  final selfieImageBytes = ValueNotifier<Uint8List?>(null);
  final isIdentifyingEmployee = ValueNotifier<bool>(false);
  final employeePosition = ValueNotifier<String>('');
  final employeeSbu = ValueNotifier<String>('');
  final showEmployeeIdFloater = ValueNotifier<bool>(false);
  final fingerprintEnrollmentAllowed = ValueNotifier<bool>(true);

  final leftThumbScans = ValueNotifier<int>(0);
  final rightThumbScans = ValueNotifier<int>(0);
  final leftThumbScansList = <Uint8List>[];
  final rightThumbScansList = <Uint8List>[];
  final isSaving = false.obs;

  static const int scansPerFinger = 3;
  static const int minTimeBetweenScansMs = 800;

  Timer? _scanTimer;
  DateTime? _lastScanTime;
  String? _fingerprintBlockReason;
  final Map<String, bool> _apiFingerprintCache = {};

  Function(String)? onError;
  Function(String)? onSuccess;
  VoidCallback? onFingerprintNotRecognized;

  final String? siteId;
  String? _resolvedSiteId;
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
    unawaited(_ensureSiteIdResolved());
    _prefillEmployeeDetails();
    _loadEmployeePhoto();
    _clearScanState();
    _device.clearCachedCapture();
    
    // Only start device initialization if employee details are pre-filled
    // Otherwise, wait for user to identify employee first
    if ((employeeId != null && employeeId!.isNotEmpty) ||
        (employeeName != null && employeeName!.isNotEmpty)) {
      _initDevice();
    } else {
      // Don't start scanning until user is identified
      deviceInitialized.value = false;
      onSuccess?.call('Please identify an employee first by entering ID or clicking SCAN');
    }
  }

  @override
  void onClose() {
    try {
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
      isIdentifyingEmployee.dispose();
      leftThumbScans.dispose();
      rightThumbScans.dispose();
      employeePosition.dispose();
      employeeSbu.dispose();
      showEmployeeIdFloater.dispose();
      fingerprintEnrollmentAllowed.dispose();
    } catch (e) {
      debugPrint('[ENROLLMENT] Error in onClose: $e');
    }
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
    // Guide panel always shows lookup fields; keep showForm in sync for legacy checks.
    showForm.value = true;
    if ((employeeId != null && employeeId!.isNotEmpty) ||
        (employeeName != null && employeeName!.isNotEmpty)) {
      _clearScanState();
      if (employeeId != null && employeeId!.isNotEmpty) {
        unawaited(() async {
          try {
            final lookup = await lookupExistingEmployee(employeeId!);
            if (lookup != null) {
              _applyEmployeeFromLookup(lookup);
            } else {
              await _loadEmployeeProfile(employeeId!);
            }
          } catch (e) {
            debugPrint('[ENROLLMENT] Prefill profile error: $e');
          }
        }());
      }
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
    await _loadEmployeePhotoForId(empId);
  }

  Future<void> _loadEmployeePhotoForId(String empId) async {
    try {
      final site = await _activeSiteId();
      if (!await LocalDb.hasEmployeePhoto(
        employeeId: empId,
        siteId: site,
      )) {
        selfieImageBytes.value = null;
        return;
      }
      final photo = await LocalDb.getEmployeePhoto(
        employeeId: empId,
        siteId: site,
      );
      selfieImageBytes.value = photo;
    } catch (e, stack) {
      debugPrint('[ENROLLMENT] Photo load failed (non-fatal): $e\n$stack');
      selfieImageBytes.value = null;
    }
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
      if (isIdentifyingEmployee.value || fingerprintEnrollmentAllowed.value) {
        _startScanLoop();
      }
    } catch (e) {
      debugPrint('Device initialization error: $e');
      onError?.call('Device initialization error: $e');
    }
  }

  void _startScanLoop() {
    if (isScanning.value) return;
    if (!isIdentifyingEmployee.value && !fingerprintEnrollmentAllowed.value) {
      return;
    }
    isScanning.value = true;
    debugPrint('Starting enrollment scan loop...');

    _scanTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!isScanning.value || !_device.isConnected) return;
      if (!isIdentifyingEmployee.value && !fingerprintEnrollmentAllowed.value) {
        _stopScanLoop();
        return;
      }

      // If in identification mode, try to identify employee
      if (isIdentifyingEmployee.value) {
        try {
          final template = await _device.captureFingerprint();
          if (template != null && template.isNotEmpty) {
            await _identifyEmployeeByFingerprint(template);
          }
        } catch (e) {
          // Silent fail
        }
        return;
      }

      // Normal enrollment scan mode
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
    try {
      _scanTimer?.cancel();
      _scanTimer = null;
      isScanning.value = false;
    } catch (e) {
      debugPrint('[ENROLLMENT] Error stopping scan loop: $e');
    }
  }

  Future<void> _onFingerprintCaptured(Uint8List template) async {
    if (!fingerprintEnrollmentAllowed.value) {
      if (_fingerprintBlockReason != null) {
        onError?.call(_fingerprintBlockReason!);
      }
      return;
    }
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
    if (!fingerprintEnrollmentAllowed.value) {
      if (_fingerprintBlockReason != null) {
        onError?.call(_fingerprintBlockReason!);
      }
      return;
    }
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

  /// Saves both thumbs to local DB only. Returns context for HRIS upload after navigation.
  Future<EnrollmentSaveContext?> saveEnrollmentLocal() async {
    if (isSaving.value) return null;

    if (idController.text.isEmpty || usernameController.text.isEmpty) {
      onError?.call('Please enter ID and username');
      return null;
    }

    final canEnroll = await _ensureFingerprintEnrollmentAllowed(
      idController.text.trim(),
    );
    if (!canEnroll) {
      return null;
    }

    if (leftThumbScans.value < scansPerFinger ||
        rightThumbScans.value < scansPerFinger) {
      onError?.call('Please scan each thumb 3 times (3 left, 3 right)');
      return null;
    }

    isSaving.value = true;
    try {
      final site = await _activeSiteId();
      final empId = idController.text.trim();
      final empName = usernameController.text.trim();

      // Always replace local fingerprint templates for this employee/site.
      // Scanning uses local templates first; API sync is secondary.
      await LocalDb.deleteEmployeeFingerprints(
        employeeId: empId,
        siteId: site,
      );

      final leftTemplate = await _resolveEnrollmentTemplate(leftThumbScansList);
      final rightTemplate =
          await _resolveEnrollmentTemplate(rightThumbScansList);
      if (leftTemplate == null || rightTemplate == null) {
        throw Exception('Unable to prepare fingerprint templates');
      }

      final leftB64 = base64Encode(leftTemplate);
      final rightB64 = base64Encode(rightTemplate);

      await LocalDb.upsertEmployee(
        fid: _stableFingerprintId(empId, 'left'),
        employeeId: empId,
        employeeName: empName,
        template: leftTemplate,
        siteId: site,
      );
      await LocalDb.upsertEmployee(
        fid: _stableFingerprintId(empId, 'right'),
        employeeId: empId,
        employeeName: empName,
        template: rightTemplate,
        siteId: site,
      );

      if (selfieImageBytes.value != null) {
        await LocalDb.upsertEmployeePhoto(
          employeeId: empId,
          siteId: site,
          photo: selfieImageBytes.value!,
        );
      }

      await LocalDb.queueFingerprintUpdate(
        employeeId: empId,
        siteId: site,
      );
      hrisLog(
        '[ENROLLMENT] Local save OK employee=$empId thumbs stored (queued for HRIS)',
      );

      if (Get.isRegistered<ScannerRegistryService>()) {
        await Get.find<ScannerRegistryService>().reloadSiteFromLocalDb(site);
      }

      _clearEnrollmentData();

      return EnrollmentSaveContext(
        employeeId: empId,
        employeeName: empName,
        siteId: site,
        leftFingerThumb: leftB64,
        rightFingerThumb: rightB64,
      );
    } catch (e) {
      debugPrint('Save error: $e');
      onError?.call('Save failed: $e');
      return null;
    } finally {
      isSaving.value = false;
    }
  }

  /// POST thumbDetails to HRIS when Online mode (runs after returning to Home).
  Future<void> uploadEnrollmentToHris(EnrollmentSaveContext ctx) async {
    if (!Get.isRegistered<PendingSyncService>()) {
      Get.put(PendingSyncService());
    }
    final sync = Get.find<PendingSyncService>();

    if (!await sync.shouldPushToHrisApi()) {
      hrisLog(
        '[ENROLLMENT] HRIS thumb upload deferred (Offline mode — queued locally)',
      );
      return;
    }

    try {
      await sync.uploadFingerprint(
        employeeId: ctx.employeeId,
        siteId: ctx.siteId,
        leftFingerThumb: ctx.leftFingerThumb,
        rightFingerThumb: ctx.rightFingerThumb,
      );
      await sync.markFingerprintQueueSynced(
        employeeId: ctx.employeeId,
        siteId: ctx.siteId,
      );
      hrisLog('[ENROLLMENT] HRIS thumbDetails upload OK employee=${ctx.employeeId}');
    } catch (e) {
      hrisLog('[ENROLLMENT] HRIS thumbDetails failed (queued retry): $e');
      unawaited(sync.syncAllPending(siteId: ctx.siteId));
    }
  }

  Future<bool> saveEnrollment() async {
    final ctx = await saveEnrollmentLocal();
    if (ctx == null) return false;
    onSuccess?.call(
      isEditMode
          ? 'Enrollment updated successfully!'
          : 'Enrollment saved successfully!',
    );
    unawaited(uploadEnrollmentToHris(ctx));
    return true;
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
    fingerprintEnrollmentAllowed.value = true;
    _fingerprintBlockReason = null;
  }

  void _clearScanState() {
    leftThumbScans.value = 0;
    rightThumbScans.value = 0;
    leftThumbScansList.clear();
    rightThumbScansList.clear();
    lastFingerprintImage.value = null;
    _lastScanTime = null;
  }

  bool _isBlankFingerprintValue(dynamic value) {
    if (value == null) return true;
    final text = value.toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null';
  }

  bool _setFingerprintEnrollmentBlocked(String reason) {
    fingerprintEnrollmentAllowed.value = false;
    _fingerprintBlockReason = reason;
    onError?.call(reason);
    _stopScanLoop();
    return false;
  }

  Future<bool> _employeeHasLocalFingerprint({
    required String employeeId,
    required String siteId,
  }) async {
    final rows = await LocalDb.getEmployeesBySite(
      siteId,
      includeFingerTemplates: false,
    );
    for (final row in rows) {
      final empId = row['employee_id']?.toString().trim() ?? '';
      if (empId.isEmpty || empId != employeeId.trim()) continue;
      final fid = row['fid'] as int?;
      if (fid == null) continue;
      final bytes = await LocalDb.getFingerTemplateByFid(
        fid: fid,
        siteId: siteId,
      );
      if (bytes != null && bytes.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<bool?> _employeeHasApiFingerprint({
    required String employeeId,
    required String siteId,
  }) async {
    final key = employeeId.trim();
    if (_apiFingerprintCache.containsKey(key)) {
      return _apiFingerprintCache[key];
    }

    try {
      final rows = await LocalDb.fetchEmployeesBySiteFromApi(siteId);
      for (final row in rows) {
        final empId = LocalDb.employeeIdFromApiRow(row) ??
            row['employee_id']?.toString();
        if (empId == null || empId.trim() != key) continue;

        final hasTemplate = [
          row['LEFTFINGERTHUMB'],
          row['leftFingerThumb'],
          row['left_thumb'],
          row['RIGHTFINGERTHUMB'],
          row['rightFingerThumb'],
          row['right_thumb'],
          row['finger_template'],
          row['template'],
          row['fingerprint'],
        ].any((value) => !_isBlankFingerprintValue(value));

        _apiFingerprintCache[key] = hasTemplate;
        return hasTemplate;
      }
      _apiFingerprintCache[key] = false;
      return false;
    } catch (e) {
      debugPrint('[ENROLLMENT] API fingerprint check failed: $e');
      return null;
    }
  }

  Future<bool> _ensureFingerprintEnrollmentAllowed(String employeeId) async {
    fingerprintEnrollmentAllowed.value = true;
    _fingerprintBlockReason = null;

    final site = await _activeSiteId();
    if (await _employeeHasLocalFingerprint(employeeId: employeeId, siteId: site)) {
      return _setFingerprintEnrollmentBlocked(
        'Employee already has enrolled fingerprints.',
      );
    }

    final apiHas = await _employeeHasApiFingerprint(
      employeeId: employeeId,
      siteId: site,
    );
    if (apiHas == null) {
      return _setFingerprintEnrollmentBlocked(
        'Unable to verify fingerprint status. Please sync online and try again.',
      );
    }
    if (apiHas) {
      return _setFingerprintEnrollmentBlocked(
        'Employee already has enrolled fingerprints.',
      );
    }
    return true;
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

  Future<String> _activeSiteId() async {
    final resolved = await _resolveSiteId();
    if (resolved == null || resolved.isEmpty) {
      throw StateError('No site selected');
    }
    return resolved;
  }

  Future<String?> _resolveSiteId() async {
    if (_resolvedSiteId != null && _resolvedSiteId!.isNotEmpty) {
      return _resolvedSiteId;
    }
    final incoming = siteId?.trim();
    if (incoming != null && incoming.isNotEmpty) {
      _resolvedSiteId = incoming;
      return incoming;
    }
    final selected = await LocalDb.getSelectedSiteId();
    if (selected != null && selected.trim().isNotEmpty) {
      _resolvedSiteId = selected.trim();
      return _resolvedSiteId;
    }
    return null;
  }

  Future<void> _ensureSiteIdResolved() async {
    await _resolveSiteId();
  }

  void _applyEmployeeFromLookup(Map<String, dynamic> employee) {
    idController.text = employee['id']?.toString() ?? '';
    usernameController.text = employee['name']?.toString() ?? '';
    employeePosition.value = employee['position']?.toString().trim() ?? '';
    employeeSbu.value = employee['sbu']?.toString().trim() ?? '';
  }

  Future<void> _loadEmployeeProfile(String employeeId) async {
    final site = await _activeSiteId();
    final profile = await LocalDb.resolveEmployeeProfile(
      employeeId: employeeId,
      siteId: site,
    );
    if (profile != null) {
      final name = profile['employee_name']?.toString().trim() ?? '';
      if (name.isNotEmpty && usernameController.text.trim().isEmpty) {
        usernameController.text = name;
      }
      employeePosition.value = profile['position']?.toString().trim() ?? '';
      employeeSbu.value = profile['sbu']?.toString().trim() ?? '';
    }
  }

  void _clearEmployeeProfile() {
    employeePosition.value = '';
    employeeSbu.value = '';
  }

  String _recordedDetailsLine() {
    final position = employeePosition.value.trim();
    final sbu = employeeSbu.value.trim();
    if (position.isNotEmpty && sbu.isNotEmpty) {
      return '$position | $sbu';
    }
    if (position.isNotEmpty) return position;
    if (sbu.isNotEmpty) return sbu;
    return '';
  }

  void revealEmployeeIdFloater() {
    showEmployeeIdFloater.value = true;
  }

  void hideEmployeeIdFloater() {
    showEmployeeIdFloater.value = false;
  }

  /// Look up employee by ID from local DB, then from API if needed.
  Future<Map<String, dynamic>?> lookupExistingEmployee(String employeeId) async {
    if (employeeId.trim().isEmpty) {
      return null;
    }

    final resolvedSite = await _resolveSiteId();
    if (resolvedSite == null || resolvedSite.isEmpty) {
      onError?.call('No site selected. Please select a site on the home page first.');
      return null;
    }

    try {
      return await LocalDb.findEmployeeInSite(
        siteId: resolvedSite,
        employeeId: employeeId.trim(),
      );
    } catch (e) {
      debugPrint('[ENROLLMENT] Error looking up employee: $e');
      return null;
    }
  }

  /// Load employee details into the form when employee ID is found
  Future<bool> loadEmployeeDetails(String employeeId) async {
    if (employeeId.isEmpty) {
      onError?.call('Please enter an employee ID');
      return false;
    }

    try {
      final employee = await lookupExistingEmployee(employeeId);
      if (employee == null) {
        onError?.call('Employee ID not found. Please use an existing employee ID.');
        return false;
      }

      _applyEmployeeFromLookup(employee);

      if (employeePosition.value.isEmpty || employeeSbu.value.isEmpty) {
        try {
          await _loadEmployeeProfile(employee['id']?.toString() ?? employeeId);
        } catch (e) {
          debugPrint('[ENROLLMENT] Profile refresh error (non-fatal): $e');
        }
      }

      try {
        await _loadEmployeePhotoForId(employee['id']?.toString() ?? employeeId);
      } catch (e) {
        debugPrint('[ENROLLMENT] Photo load error (non-fatal): $e');
        selfieImageBytes.value = null;
      }

      showForm.value = true;
      isIdentifyingEmployee.value = false;
      _clearScanState();

      if (!deviceInitialized.value) {
        try {
          await _initDevice();
        } catch (e) {
          debugPrint('[ENROLLMENT] Device init error (non-fatal): $e');
        }
      }

      final details = _recordedDetailsLine();
      final detailsSuffix =
          details.isNotEmpty ? ' ($details)' : '';
      onSuccess?.call(
        'Employee found: ${employee['name']}$detailsSuffix. Please scan new fingerprints.',
      );
      return true;
    } catch (e) {
      debugPrint('[ENROLLMENT] loadEmployeeDetails error: $e');
      if (e is StateError && e.message.contains('No site selected')) {
        onError?.call(
          'No site selected. Please select a site on the home page first.',
        );
      } else {
        onError?.call('Error loading employee: $e');
      }
      return false;
    }
  }

  DateTime? _lastFingerprintNotRecognizedAt;

  void _notifyFingerprintNotRecognized() {
    final now = DateTime.now();
    if (_lastFingerprintNotRecognizedAt != null) {
      final diff = now.difference(_lastFingerprintNotRecognizedAt!).inMilliseconds;
      if (diff < 3000) return;
    }
    _lastFingerprintNotRecognizedAt = now;
    onFingerprintNotRecognized?.call();
    onError?.call('Fingerprint not recognized. Please try again or enter employee ID.');
  }

  /// Identify employee by scanning their fingerprint
  Future<void> _identifyEmployeeByFingerprint(Uint8List template) async {
    final now = DateTime.now();
    if (_lastScanTime != null) {
      final diff = now.difference(_lastScanTime!).inMilliseconds;
      if (diff < minTimeBetweenScansMs) {
        // Ignore duplicate captures fired too quickly
        return;
      }
    }
    _lastScanTime = now;

    try {
      final site = await _activeSiteId();
      final employees = await LocalDb.getEmployeesBySite(
        site,
        includeFingerTemplates: false,
      );

      if (employees.isEmpty) {
        _notifyFingerprintNotRecognized();
        return;
      }

      // Group employees by employee_id (each employee has 2 records: left and right thumb)
      final employeeGroups = <String, List<Map<String, dynamic>>>{};
      for (final emp in employees) {
        final empId = emp['employee_id']?.toString() ?? '';
        if (empId.isNotEmpty) {
          employeeGroups.putIfAbsent(empId, () => []);
          employeeGroups[empId]!.add(emp);
        }
      }

      // Match fingerprint against all employee templates (one BLOB per query)
      for (final entry in employeeGroups.entries) {
        final empId = entry.key;
        final empRecords = entry.value;
        final empName = empRecords.first['employee_name']?.toString() ?? 'Unknown';

        for (final record in empRecords) {
          final fid = record['fid'] as int?;
          if (fid == null) continue;
          final fingerTemplate =
              await LocalDb.getFingerTemplateByFid(fid: fid, siteId: site);
          if (fingerTemplate == null || fingerTemplate.isEmpty) {
            continue;
          }

          final score = await _device.matchTemplatesAsync(
            template,
            fingerTemplate,
          );

          if (score != null && score > 0) {
            final lookup = await lookupExistingEmployee(empId);
            if (lookup != null) {
              _applyEmployeeFromLookup(lookup);
            } else {
              idController.text = empId;
              usernameController.text = empName;
            }

            if (employeePosition.value.isEmpty || employeeSbu.value.isEmpty) {
              try {
                await _loadEmployeeProfile(empId);
              } catch (e) {
                debugPrint('[ENROLLMENT] Profile load after scan: $e');
              }
            }

            try {
              await _loadEmployeePhotoForId(empId);
            } catch (e) {
              selfieImageBytes.value = null;
            }

            showForm.value = true;
            isIdentifyingEmployee.value = false;
            _clearScanState();

            final details = _recordedDetailsLine();
            final detailsSuffix =
                details.isNotEmpty ? ' ($details)' : '';
            onSuccess?.call(
              'Employee identified: $empName$detailsSuffix. Please scan new fingerprints.',
            );
            return;
          }
        }
      }

      _notifyFingerprintNotRecognized();
    } catch (e) {
      debugPrint('Identification error: $e');
      onError?.call('Error identifying employee: $e');
    }
  }

  /// Start identification mode (scan fingerprint to find employee)
  Future<void> startIdentificationMode() async {
    _clearScanState();
    isIdentifyingEmployee.value = true;
    idController.clear();
    usernameController.clear();
    selfieImageBytes.value = null;
    _clearEmployeeProfile();

    // Initialize device if not already initialized
    if (!deviceInitialized.value) {
      await _initDevice();
    }
    
    onSuccess?.call('Scan fingerprint to identify employee');
  }

  /// Cancel identification mode and enter employee ID manually
  void cancelIdentificationMode() {
    isIdentifyingEmployee.value = false;
    showForm.value = true;
    // Clear scan state to prepare for new fingerprint enrollment
    _clearScanState();
    onSuccess?.call('Enter employee ID manually');
  }
}
