import 'student.dart';

class AttendanceAlertModel {
  final String id;
  final String classSubjectId;
  final String studentId;
  final double attendancePercent;
  final int attendedCount;
  final int conductedCount;
  final String alertType; // 'initial', 'reminder'
  final DateTime sentAt;
  final String status;   // 'sent', 'failed', 'pending'
  final String? errorMessage;
  final StudentModel? student;

  AttendanceAlertModel({
    required this.id,
    required this.classSubjectId,
    required this.studentId,
    required this.attendancePercent,
    required this.attendedCount,
    required this.conductedCount,
    this.alertType = 'initial',
    DateTime? sentAt,
    this.status = 'sent',
    this.errorMessage,
    this.student,
  }) : sentAt = sentAt ?? DateTime.now();

  factory AttendanceAlertModel.fromJson(Map<String, dynamic> json) {
    return AttendanceAlertModel(
      id: json['id'] as String,
      classSubjectId: json['class_subject_id'] as String,
      studentId: json['student_id'] as String,
      attendancePercent: (json['attendance_percent'] as num).toDouble(),
      attendedCount: json['attended_count'] as int,
      conductedCount: json['conducted_count'] as int,
      alertType: json['alert_type'] as String? ?? 'initial',
      sentAt: json['sent_at'] != null 
          ? DateTime.parse(json['sent_at']) 
          : DateTime.now(),
      status: json['status'] as String? ?? 'sent',
      errorMessage: json['error_message'] as String?,
      student: json['students'] != null ? StudentModel.fromJson(json['students']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'class_subject_id': classSubjectId,
      'student_id': studentId,
      'attendance_percent': attendancePercent,
      'attended_count': attendedCount,
      'conducted_count': conductedCount,
      'alert_type': alertType,
      'sent_at': sentAt.toIso8601String(),
      'status': status,
      'error_message': errorMessage,
    };
  }
}
