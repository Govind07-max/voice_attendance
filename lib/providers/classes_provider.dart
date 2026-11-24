import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/class_model.dart';
import '../models/class_subject.dart';
import '../models/enrollment.dart';
import '../models/student.dart';
import '../models/subject.dart';
import 'database_provider.dart';

/// All class + subject pairs the teacher teaches (the attendance context).
final classSubjectsProvider = FutureProvider.autoDispose<List<ClassSubjectModel>>(
  (ref) async {
    final teacherId = ref.watch(teacherIdProvider);
    if (teacherId == null) return [];
    final db = ref.watch(databaseServiceProvider);
    return db.getClassSubjects(teacherId);
  },
);

/// Plain class list (for the Classes tab).
final classesProvider = FutureProvider.autoDispose<List<ClassModel>>((ref) async {
  final teacherId = ref.watch(teacherIdProvider);
  if (teacherId == null) return [];
  final db = ref.watch(databaseServiceProvider);
  return db.getClasses(teacherId);
});

final subjectsProvider = FutureProvider.autoDispose<List<SubjectModel>>((ref) async {
  final teacherId = ref.watch(teacherIdProvider);
  if (teacherId == null) return [];
  final db = ref.watch(databaseServiceProvider);
  return db.getSubjects(teacherId);
});

/// Roster (students) enrolled in one class + subject.
final rosterProvider = FutureProvider.autoDispose
    .family<List<StudentModel>, String>((ref, classSubjectId) async {
  final db = ref.watch(databaseServiceProvider);
  final enrollments = await db.getEnrollments(classSubjectId);
  return enrollments
      .map((EnrollmentModel e) => e.student)
      .whereType<StudentModel>()
      .toList();
});

/// Counts of classes / subjects for the dashboard.
final teacherCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final teacherId = ref.watch(teacherIdProvider);
  if (teacherId == null) return {};
  final db = ref.watch(databaseServiceProvider);
  final classes = await db.getClasses(teacherId);
  final classSubjects = await db.getClassSubjects(teacherId);
  final students = await db.getStudents(teacherId);
  return {
    'classes': classes.length,
    'classSubjects': classSubjects.length,
    'students': students.length,
  };
});
