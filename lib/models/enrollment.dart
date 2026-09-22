import 'student.dart';

class EnrollmentModel {
  final String id;
  final String classSubjectId;
  final String studentId;
  final DateTime enrolledFrom;
  final DateTime? enrolledTo;
  final bool active;
  final StudentModel? student;

  EnrollmentModel({
    required this.id,
    required this.classSubjectId,
    required this.studentId,
    required this.enrolledFrom,
    this.enrolledTo,
    this.active = true,
    this.student,
  });

  factory EnrollmentModel.fromJson(Map<String, dynamic> json) {
    return EnrollmentModel(
      id: json['id'] as String,
      classSubjectId: json['class_subject_id'] as String,
      studentId: json['student_id'] as String,
      enrolledFrom: DateTime.parse(json['enrolled_from']),
      enrolledTo: json['enrolled_to'] != null 
          ? DateTime.parse(json['enrolled_to']) 
          : null,
      active: json['active'] as bool? ?? true,
      student: json['students'] != null ? StudentModel.fromJson(json['students']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'class_subject_id': classSubjectId,
      'student_id': studentId,
      'enrolled_from': enrolledFrom.toIso8601String().split('T')[0],
      'enrolled_to': enrolledTo?.toIso8601String().split('T')[0],
      'active': active,
    };
  }
}
