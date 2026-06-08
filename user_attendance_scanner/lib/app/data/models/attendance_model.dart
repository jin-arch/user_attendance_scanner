enum AttendanceType {
  timeInMorning('TIME IN MORNING'),
  timeOutMorning('TIME OUT MORNING'), 
  timeInAfternoon('TIME IN AFTERNOON'),
  timeOutAfternoon('TIME OUT AFTERNOON');

  const AttendanceType(this.displayName);
  
  final String displayName;

  static AttendanceType? fromString(String value) {
    switch (value.toUpperCase()) {
      case 'TIME IN MORNING':
        return AttendanceType.timeInMorning;
      case 'TIME OUT MORNING':
        return AttendanceType.timeOutMorning;
      case 'TIME IN AFTERNOON':
        return AttendanceType.timeInAfternoon;
      case 'TIME OUT AFTERNOON':
        return AttendanceType.timeOutAfternoon;
      default:
        return null;
    }
  }
}

class Attendance {
  final String employeeId;
  final String employeeName;
  final String siteId;
  final DateTime timestamp;
  final AttendanceType type;
  final bool synced;
  final String? notes;

  const Attendance({
    required this.employeeId,
    required this.employeeName,
    required this.siteId,
    required this.timestamp,
    required this.type,
    this.synced = false,
    this.notes,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      employeeId: json['employee_id']?.toString() ?? '',
      employeeName: json['employee_name']?.toString() ?? '',
      siteId: json['site_id']?.toString() ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      type: AttendanceType.fromString(json['attendance_type']) ?? AttendanceType.timeInMorning,
      synced: json['synced'] == 1 || json['synced'] == true,
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'employee_id': employeeId,
      'employee_name': employeeName,
      'site_id': siteId,
      'timestamp': timestamp.toIso8601String(),
      'attendance_type': type.displayName,
      'synced': synced ? 1 : 0,
      'notes': notes,
    };
  }

  Attendance copyWith({
    String? employeeId,
    String? employeeName,
    String? siteId,
    DateTime? timestamp,
    AttendanceType? type,
    bool? synced,
    String? notes,
  }) {
    return Attendance(
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      siteId: siteId ?? this.siteId,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      synced: synced ?? this.synced,
      notes: notes ?? this.notes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Attendance && 
      runtimeType == other.runtimeType && 
      employeeId == other.employeeId && 
      timestamp == other.timestamp &&
      type == other.type;

  @override
  int get hashCode => Object.hash(employeeId, timestamp, type);

  @override
  String toString() => 'Attendance(employeeId: $employeeId, type: ${type.displayName}, timestamp: $timestamp)';
}
