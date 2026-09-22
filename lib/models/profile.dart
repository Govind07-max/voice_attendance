class TeacherProfile {
  final String id;
  final String fullName;
  final String facultyId;
  final String email;
  final String department;
  final String phone;
  final String timezone;
  final double defaultThreshold;
  final DateTime createdAt;

  TeacherProfile({
    required this.id,
    required this.fullName,
    this.facultyId = '',
    required this.email,
    this.department = '',
    this.phone = '',
    this.timezone = 'UTC',
    this.defaultThreshold = 75.0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TeacherProfile.fromJson(Map<String, dynamic> json) {
    return TeacherProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      facultyId: json['faculty_id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      department: json['department'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      timezone: json['timezone'] as String? ?? 'UTC',
      defaultThreshold: (json['default_threshold'] as num?)?.toDouble() ?? 75.0,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'faculty_id': facultyId,
      'email': email,
      'department': department,
      'phone': phone,
      'timezone': timezone,
      'default_threshold': defaultThreshold,
    };
  }
}

class TeacherAvailability {
  final String id;
  final String teacherId;
  final int dayOfWeek; // 1-7
  final String startTime; // HH:mm:ss
  final String endTime;   // HH:mm:ss
  final bool active;

  TeacherAvailability({
    required this.id,
    required this.teacherId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.active = true,
  });

  factory TeacherAvailability.fromJson(Map<String, dynamic> json) {
    return TeacherAvailability(
      id: json['id'] as String,
      teacherId: json['teacher_id'] as String,
      dayOfWeek: json['day_of_week'] as int,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'teacher_id': teacherId,
      'day_of_week': dayOfWeek,
      'start_time': startTime,
      'end_time': endTime,
      'active': active,
    };
  }
}
