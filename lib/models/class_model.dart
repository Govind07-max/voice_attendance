class ClassModel {
  final String id;
  final String teacherId;
  final String className;
  final String academicYear;
  final String semester;
  final String section;
  final bool active;
  final DateTime createdAt;

  ClassModel({
    required this.id,
    required this.teacherId,
    required this.className,
    required this.academicYear,
    required this.semester,
    this.section = '',
    this.active = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ClassModel.fromJson(Map<String, dynamic> json) {
    return ClassModel(
      id: json['id'] as String,
      teacherId: json['teacher_id'] as String,
      className: json['class_name'] as String,
      academicYear: json['academic_year'] as String,
      semester: json['semester'] as String,
      section: json['section'] as String? ?? '',
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'teacher_id': teacherId,
      'class_name': className,
      'academic_year': academicYear,
      'semester': semester,
      'section': section,
      'active': active,
    };
  }
}
