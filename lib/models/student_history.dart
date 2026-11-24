import 'attendance_session.dart';
import 'class_subject.dart';
import 'student.dart';

/// One lecture result for a student (for the per-student history screen).
class StudentHistoryEntry {
  final AttendanceSessionModel session;
  final String status; // 'present' | 'absent'
  final String source; // 'voice' | 'manual' | 'default'
  final ClassSubjectModel classSubject;

  const StudentHistoryEntry({
    required this.session,
    required this.status,
    required this.source,
    required this.classSubject,
  });

  bool get isPresent => status == 'present';
}

/// Per-subject totals for one student.
class StudentSubjectSummary {
  final ClassSubjectModel classSubject;
  final int attended;
  final int conducted;
  final double percentage;

  const StudentSubjectSummary({
    required this.classSubject,
    required this.attended,
    required this.conducted,
    required this.percentage,
  });

  bool isBelow(double threshold) => percentage < threshold;
}

/// Everything the student-history screen needs, in one object.
class StudentHistory {
  final StudentModel student;
  final List<StudentHistoryEntry> entries; // newest first
  final List<StudentSubjectSummary> summaries;

  const StudentHistory({
    required this.student,
    required this.entries,
    required this.summaries,
  });

  int get totalAttended =>
      summaries.fold(0, (sum, s) => sum + s.attended);

  int get totalConducted =>
      summaries.fold(0, (sum, s) => sum + s.conducted);

  double get overallPercentage =>
      totalConducted == 0 ? 100 : (totalAttended / totalConducted) * 100;

  static StudentHistory empty(StudentModel student) =>
      StudentHistory(student: student, entries: const [], summaries: const []);
}
