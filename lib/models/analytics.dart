import 'class_subject.dart';
import 'student.dart';

/// One slice of the attendance-health pie chart.
class AnalyticsBucket {
  final String label;
  final int count;
  final double percentage;

  const AnalyticsBucket({
    required this.label,
    required this.count,
    required this.percentage,
  });
}

/// Aggregated attendance for one class + subject.
class ClassAttendancePoint {
  final ClassSubjectModel classSubject;
  final double averagePercentage;
  final int studentCount;
  final int sessionCount;
  final int studentsBelowThreshold;

  const ClassAttendancePoint({
    required this.classSubject,
    required this.averagePercentage,
    required this.studentCount,
    required this.sessionCount,
    required this.studentsBelowThreshold,
  });

  String get className => classSubject.classDetails?.className ?? 'Class';

  String get subjectName =>
      classSubject.subjectDetails?.subjectName ?? 'Subject';

  String get shortLabel => '$className\n$subjectName';
}

/// One lecture-day point on the attendance trend line.
class AttendanceTrendPoint {
  final DateTime date;
  final int presentCount;
  final int eligibleCount;

  const AttendanceTrendPoint({
    required this.date,
    required this.presentCount,
    required this.eligibleCount,
  });

  double get percentage =>
      eligibleCount == 0 ? 0.0 : (presentCount / eligibleCount) * 100.0;
}

/// A student's performance inside one class + subject.
class StudentPerformance {
  final StudentModel student;
  final ClassSubjectModel classSubject;
  final double percentage;
  final int attended;
  final int conducted;

  const StudentPerformance({
    required this.student,
    required this.classSubject,
    required this.percentage,
    required this.attended,
    required this.conducted,
  });

  String get className => classSubject.classDetails?.className ?? 'Class';

  String get subjectName =>
      classSubject.subjectDetails?.subjectName ?? 'Subject';
}

/// Everything the teacher analytics view needs, computed in one pass.
class TeacherAnalyticsSnapshot {
  final int totalStudents;
  final int totalLectures;
  final int totalPresent;
  final int totalAbsent;
  final int totalEligible;
  final double overallPercentage;
  final int studentsBelowThreshold;
  final List<AnalyticsBucket> healthBands;
  final List<ClassAttendancePoint> classComparison;
  final List<AttendanceTrendPoint> trend;
  final List<StudentPerformance> topStudents;
  final List<StudentPerformance> needsAttention;

  const TeacherAnalyticsSnapshot({
    required this.totalStudents,
    required this.totalLectures,
    required this.totalPresent,
    required this.totalAbsent,
    required this.totalEligible,
    required this.overallPercentage,
    required this.studentsBelowThreshold,
    required this.healthBands,
    required this.classComparison,
    required this.trend,
    required this.topStudents,
    required this.needsAttention,
  });

  const TeacherAnalyticsSnapshot.empty()
      : totalStudents = 0,
        totalLectures = 0,
        totalPresent = 0,
        totalAbsent = 0,
        totalEligible = 0,
        overallPercentage = 0,
        studentsBelowThreshold = 0,
        healthBands = const [],
        classComparison = const [],
        trend = const [],
        topStudents = const [],
        needsAttention = const [];

  bool get hasLectures => totalLectures > 0;
  bool get hasAttendance => totalEligible > 0;
}
