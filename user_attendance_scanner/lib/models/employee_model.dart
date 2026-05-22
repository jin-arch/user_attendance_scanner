import 'dart:typed_data';
import 'dart:convert';

class Employee {
  final String id;
  final String name;
  final String siteId;
  final int? fid;
  final Uint8List? fingerTemplate;
  final DateTime? enrolledAt;

  const Employee({
    required this.id,
    required this.name,
    required this.siteId,
    this.fid,
    this.fingerTemplate,
    this.enrolledAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    final rawTemplate = json['finger_template'] ?? json['fingerprint'] ?? json['template'];

    Uint8List? parsedTemplate;
    if (rawTemplate is Uint8List) {
      parsedTemplate = rawTemplate;
    } else if (rawTemplate is List<int>) {
      parsedTemplate = Uint8List.fromList(rawTemplate);
    } else if (rawTemplate is String && rawTemplate.isNotEmpty) {
      parsedTemplate = base64Decode(rawTemplate);
    }

    return Employee(
      id: json['employee_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['employee_name']?.toString() ?? json['name']?.toString() ?? '',
      siteId: json['site_id']?.toString() ?? '',
      fid: json['fid'] is int
          ? json['fid'] as int
          : int.tryParse(json['fid']?.toString() ?? ''),
      fingerTemplate: parsedTemplate,
      enrolledAt: json['enrolled_at'] != null
          ? DateTime.tryParse(json['enrolled_at']?.toString() ?? '')
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'site_id': siteId,
      'fingerprint': fingerTemplate != null ? base64Encode(fingerTemplate!) : null,
      'enrolled_at': enrolledAt?.toIso8601String(),
    };
  }

  Employee copyWith({
    String? id,
    String? name,
    String? siteId,
    int? fid,
    Uint8List? fingerTemplate,
    DateTime? enrolledAt,
  }) {
    return Employee(
      id: id ?? this.id,
      name: name ?? this.name,
      siteId: siteId ?? this.siteId,
      fid: fid ?? this.fid,
      fingerTemplate: fingerTemplate ?? this.fingerTemplate,
      enrolledAt: enrolledAt ?? this.enrolledAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Employee && runtimeType == other.runtimeType && id == other.id && siteId == other.siteId;

  @override
  int get hashCode => Object.hash(id, siteId);

  @override
  String toString() => 'Employee(id: $id, name: $name, siteId: $siteId)';
}
