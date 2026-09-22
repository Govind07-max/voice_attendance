class SubjectModel {
  final String id;
  final String teacherId;
  final String subjectCode;
  final String subjectName;
  final DateTime createdAt;

  SubjectModel({
    required this.id,
    required this.teacherId,
    required this.subjectCode,
    required this.subjectName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory SubjectModel.fromJson(Map<String, dynamic> json) {
    return SubjectModel(
      id: json['id'] as String,
      teacherId: json['teacher_id'] as String,
      subjectCode: json['subject_code'] as String,
      subjectName: json['subject_name'] as String,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'teacher_id': teacherId,
      'subject_code': subjectCode,
      'subject_name': subjectName,
    };
  }
}
