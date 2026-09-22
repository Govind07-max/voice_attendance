import 'class_model.dart';
import 'subject.dart';

class ClassSubjectModel {
  final String id;
  final String teacherId;
  final String classId;
  final String subjectId;
  final String googleFormUrl;
  final double thresholdPercent;
  final bool alertEnabled;
  final String alertFrequency;
  final String alertTime;
  final int weeklyDay;
  final int intervalDays;
  final int reminderDays;
  final bool active;
  final DateTime createdAt;

  // Joined relational objects
  final ClassModel? classDetails;
  final SubjectModel? subjectDetails;

  ClassSubjectModel({
    required this.id,
    required this.teacherId,
    required this.classId,
    required this.subjectId,
    this.googleFormUrl = '',
    this.thresholdPercent = 75.0,
    this.alertEnabled = true,
    this.alertFrequency = 'weekly',
    this.alertTime = '09:00:00',
    this.weeklyDay = 1,
    this.intervalDays = 7,
    this.reminderDays = 7,
    this.active = true,
    DateTime? createdAt,
    this.classDetails,
    this.subjectDetails,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ClassSubjectModel.fromJson(Map<String, dynamic> json) {
    return ClassSubjectModel(
      id: json['id'] as String,
      teacherId: json['teacher_id'] as String,
      classId: json['class_id'] as String,
      subjectId: json['subject_id'] as String,
      googleFormUrl: json['google_form_url'] as String? ?? '',
      thresholdPercent: (json['threshold_percent'] as num?)?.toDouble() ?? 75.0,
      alertEnabled: json['alert_enabled'] as bool? ?? true,
      alertFrequency: json['alert_frequency'] as String? ?? 'weekly',
      alertTime: json['alert_time'] as String? ?? '09:00:00',
      weeklyDay: json['weekly_day'] as int? ?? 1,
      intervalDays: json['interval_days'] as int? ?? 7,
      reminderDays: json['reminder_days'] as int? ?? 7,
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      classDetails: json['classes'] != null ? ClassModel.fromJson(json['classes']) : null,
      subjectDetails: json['subjects'] != null ? SubjectModel.fromJson(json['subjects']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'teacher_id': teacherId,
      'class_id': classId,
      'subject_id': subjectId,
      'google_form_url': googleFormUrl,
      'threshold_percent': thresholdPercent,
      'alert_enabled': alertEnabled,
      'alert_frequency': alertFrequency,
      'alert_time': alertTime,
      'weekly_day': weeklyDay,
      'interval_days': intervalDays,
      'reminder_days': reminderDays,
      'active': active,
    };
  }
}
