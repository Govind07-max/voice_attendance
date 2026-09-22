class StudentModel {
  final String id;
  final String teacherId;
  final String prn;
  final String studentName;
  final String email;
  final DateTime createdAt;

  StudentModel({
    required this.id,
    required this.teacherId,
    required this.prn,
    required this.studentName,
    this.email = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory StudentModel.fromJson(Map<String, dynamic> json) {
    return StudentModel(
      id: json['id'] as String,
      teacherId: json['teacher_id'] as String,
      prn: json['prn'] as String,
      studentName: json['student_name'] as String,
      email: json['email'] as String? ?? '',
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'teacher_id': teacherId,
      'prn': prn,
      'student_name': studentName,
      'email': email,
    };
  }
}
