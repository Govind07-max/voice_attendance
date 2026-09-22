class AttendanceSessionModel {
  final String id;
  final String classSubjectId;
  final DateTime lectureDate;
  final int periodNumber;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status; // 'draft', 'active', 'completed', 'cancelled'

  AttendanceSessionModel({
    required this.id,
    required this.classSubjectId,
    required this.lectureDate,
    this.periodNumber = 1,
    DateTime? startedAt,
    this.endedAt,
    this.status = 'draft',
  }) : startedAt = startedAt ?? DateTime.now();

  factory AttendanceSessionModel.fromJson(Map<String, dynamic> json) {
    return AttendanceSessionModel(
      id: json['id'] as String,
      classSubjectId: json['class_subject_id'] as String,
      lectureDate: DateTime.parse(json['lecture_date']),
      periodNumber: json['period_number'] as int? ?? 1,
      startedAt: json['started_at'] != null 
          ? DateTime.parse(json['started_at']) 
          : DateTime.now(),
      endedAt: json['ended_at'] != null 
          ? DateTime.parse(json['ended_at']) 
          : null,
      status: json['status'] as String? ?? 'draft',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'class_subject_id': classSubjectId,
      'lecture_date': lectureDate.toIso8601String().split('T')[0],
      'period_number': periodNumber,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'status': status,
    };
  }
}
