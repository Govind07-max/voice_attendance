import 'student.dart';

/// One manual edit of a student's attendance, kept for the audit trail.
class AttendanceEditModel {
  final String id;
  final String sessionId;
  final String studentId;
  final String? oldStatus;
  final String newStatus;
  final String? oldSource;
  final String newSource;
  final DateTime editedAt;
  final StudentModel? student;

  const AttendanceEditModel({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.oldStatus,
    required this.newStatus,
    this.oldSource,
    required this.newSource,
    required this.editedAt,
    this.student,
  });

  factory AttendanceEditModel.fromJson(Map<String, dynamic> json) {
    return AttendanceEditModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      studentId: json['student_id'] as String,
      oldStatus: json['old_status'] as String?,
      newStatus: json['new_status'] as String? ?? '',
      oldSource: json['old_source'] as String?,
      newSource: json['new_source'] as String? ?? 'manual',
      editedAt: json['edited_at'] != null
          ? DateTime.parse(json['edited_at'] as String)
          : DateTime.now(),
      student: json['students'] != null
          ? StudentModel.fromJson(json['students'] as Map<String, dynamic>)
          : null,
    );
  }
}
