import 'student.dart';

class AttendanceRecordModel {
  final String id;
  final String sessionId;
  final String studentId;
  final String status; // 'present', 'absent'
  final String source; // 'voice', 'manual', 'default'
  final DateTime markedAt;
  final StudentModel? student;

  AttendanceRecordModel({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.status,
    this.source = 'default',
    DateTime? markedAt,
    this.student,
  }) : markedAt = markedAt ?? DateTime.now();

  factory AttendanceRecordModel.fromJson(Map<String, dynamic> json) {
    return AttendanceRecordModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      studentId: json['student_id'] as String,
      status: json['status'] as String,
      source: json['source'] as String? ?? 'default',
      markedAt: json['marked_at'] != null 
          ? DateTime.parse(json['marked_at']) 
          : DateTime.now(),
      student: json['students'] != null ? StudentModel.fromJson(json['students']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'student_id': studentId,
      'status': status,
      'source': source,
      'marked_at': markedAt.toIso8601String(),
    };
  }
}
