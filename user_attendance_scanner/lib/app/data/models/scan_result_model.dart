import 'dart:typed_data';
import 'employee_model.dart';

enum ScanResultType {
  success,
  employeeNotFound,
  fingerprintNotRecognized,
  deviceError,
  networkError
}

class ScanResult {
  final ScanResultType type;
  final Employee? employee;
  final Uint8List? template;
  final DateTime timestamp;
  final String? errorMessage;
  final double? matchConfidence;

  const ScanResult({
    required this.type,
    this.employee,
    this.template,
    required this.timestamp,
    this.errorMessage,
    this.matchConfidence,
  });

  factory ScanResult.success({
    required Employee employee,
    required Uint8List template,
    double? matchConfidence,
  }) {
    return ScanResult(
      type: ScanResultType.success,
      employee: employee,
      template: template,
      timestamp: DateTime.now(),
      matchConfidence: matchConfidence,
    );
  }

  factory ScanResult.employeeNotFound({
    required Uint8List template,
    String? errorMessage,
  }) {
    return ScanResult(
      type: ScanResultType.employeeNotFound,
      template: template,
      timestamp: DateTime.now(),
      errorMessage: errorMessage ?? 'Employee not found',
    );
  }

  factory ScanResult.fingerprintNotRecognized({
    String? errorMessage,
  }) {
    return ScanResult(
      type: ScanResultType.fingerprintNotRecognized,
      timestamp: DateTime.now(),
      errorMessage: errorMessage ?? 'Fingerprint not recognized',
    );
  }

  factory ScanResult.deviceError({
    required String errorMessage,
  }) {
    return ScanResult(
      type: ScanResultType.deviceError,
      timestamp: DateTime.now(),
      errorMessage: errorMessage,
    );
  }

  factory ScanResult.networkError({
    required String errorMessage,
  }) {
    return ScanResult(
      type: ScanResultType.networkError,
      timestamp: DateTime.now(),
      errorMessage: errorMessage,
    );
  }

  bool get isSuccess => type == ScanResultType.success && employee != null;
  bool get isError => !isSuccess;

  @override
  String toString() {
    switch (type) {
      case ScanResultType.success:
        return 'ScanResult.success(employee: ${employee?.name})';
      case ScanResultType.employeeNotFound:
        return 'ScanResult.employeeNotFound';
      case ScanResultType.fingerprintNotRecognized:
        return 'ScanResult.fingerprintNotRecognized';
      case ScanResultType.deviceError:
        return 'ScanResult.deviceError($errorMessage)';
      case ScanResultType.networkError:
        return 'ScanResult.networkError($errorMessage)';
    }
  }
}
