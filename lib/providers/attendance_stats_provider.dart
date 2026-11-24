import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance_alert.dart';
import '../models/attendance_session.dart';
import '../models/class_subject.dart';
import '../models/student.dart';
import '../models/student_history.dart';
import '../services/report_service.dart';
import 'classes_provider.dart';
import 'database_provider.dart';
import 'teacher_attendance_data_provider.dart';

/// One student's real attendance for one class + subject.
class StudentAttendanceStat {
  final StudentModel student;
  final ClassSubjectModel classSubject;
  final int attended;
  final int conducted;
  final double percentage;

  const StudentAttendanceStat({
    required this.student,
    required this.classSubject,
    required this.attended,
    required this.conducted,
    required this.percentage,
  });

  bool isBelowThreshold(double threshold) => percentage < threshold;
}

/// Real per-class-subject attendance, computed from Postgres.
class ClassSubjectStats {
  final ClassSubjectModel classSubject;
  final int sessions;
  final int students;
  final double averagePercentage;

  const ClassSubjectStats({
    required this.classSubject,
    required this.sessions,
    required this.students,
    required this.averagePercentage,
  });
}

/// One row for the dashboard "Today" card.
///
/// [session] is null when the lecture has not been started for that class +
/// subject yet — the teacher can jump straight into it.
class TodayLecture {
  final ClassSubjectModel classSubject;
  final AttendanceSessionModel? session;

  const TodayLecture({required this.classSubject, this.session});

  bool get isStarted => session != null;
  bool get isActive => session?.status == 'active';
  bool get isCompleted => session?.status == 'completed';
}

/// Attendance summary per class + subject (for the dashboard).
final classSubjectStatsProvider =
    FutureProvider.autoDispose<List<ClassSubjectStats>>((ref) async {
  final data = await ref.watch(teacherAttendanceDataProvider.future);
  if (data.isEmpty) return [];

  final generator = DefaultReportGenerator();

  final result = <ClassSubjectStats>[];
  for (final entry in data) {
    if (entry.sessions.isEmpty) continue;

    final report = generator.generateReport(
      classSubject: entry.classSubject,
      sessions: entry.sessions.toList(),
      enrollments: entry.enrollments,
      allRecords: entry.records,
    );

    final rows = report.studentRows;
    final avg = rows.isEmpty
        ? 0.0
        : rows.fold<double>(0, (sum, r) => sum + r.percentage) / rows.length;

    result.add(ClassSubjectStats(
      classSubject: entry.classSubject,
      sessions: entry.sessions.length,
      students: rows.length,
      averagePercentage: double.parse(avg.toStringAsFixed(1)),
    ));
  }

  return result;
});

/// Every student below the threshold of their class + subject.
final lowAttendanceProvider =
    FutureProvider.autoDispose<List<StudentAttendanceStat>>((ref) async {
  final data = await ref.watch(teacherAttendanceDataProvider.future);
  if (data.isEmpty) return [];

  final generator = DefaultReportGenerator();

  final result = <StudentAttendanceStat>[];
  for (final entry in data) {
    if (entry.sessions.isEmpty) continue;

    final report = generator.generateReport(
      classSubject: entry.classSubject,
      sessions: entry.sessions.toList(),
      enrollments: entry.enrollments,
      allRecords: entry.records,
    );

    for (final row in report.studentRows) {
      if (row.isBelowThreshold(entry.classSubject.thresholdPercent)) {
        result.add(StudentAttendanceStat(
          student: row.student,
          classSubject: entry.classSubject,
          attended: row.attendedCount,
          conducted: row.eligibleConductedCount,
          percentage: row.percentage,
        ));
      }
    }
  }

  result.sort((a, b) => a.percentage.compareTo(b.percentage));
  return result;
});

/// Today's lectures across every class + subject, plus the ones not yet taken.
final todayLecturesProvider =
    FutureProvider.autoDispose<List<TodayLecture>>((ref) async {
  final classSubjects =
      ref.watch(classSubjectsProvider).valueOrNull ?? const [];
  if (classSubjects.isEmpty) return [];

  final db = ref.read(databaseServiceProvider);
  final sessions = await db.getSessionsForTeacherOnDate(
    classSubjects.map((cs) => cs.id).toList(),
    DateTime.now(),
  );

  final byCs = <String, List<AttendanceSessionModel>>{};
  for (final s in sessions) {
    byCs.putIfAbsent(s.classSubjectId, () => []).add(s);
  }

  final result = <TodayLecture>[];
  for (final cs in classSubjects) {
    final list = byCs[cs.id] ?? const <AttendanceSessionModel>[];
    if (list.isEmpty) {
      result.add(TodayLecture(classSubject: cs));
    } else {
      for (final s in list) {
        result.add(TodayLecture(classSubject: cs, session: s));
      }
    }
  }
  return result;
});

/// Email alert history written by the Apps Script (sent / failed / pending).
final alertHistoryProvider =
    FutureProvider.autoDispose<List<AlertHistoryItem>>((ref) async {
  final classSubjects =
      ref.watch(classSubjectsProvider).valueOrNull ?? const [];
  if (classSubjects.isEmpty) return [];

  final db = ref.read(databaseServiceProvider);
  final alerts =
      await db.getAlertsForTeacher(classSubjects.map((cs) => cs.id).toList());
  final byId = {for (final cs in classSubjects) cs.id: cs};

  return alerts
      .where((a) => byId.containsKey(a.classSubjectId))
      .map((a) => AlertHistoryItem(
            alert: a,
            classSubject: byId[a.classSubjectId]!,
          ))
      .toList();
});

/// One student's full attendance history across every class + subject.
final studentHistoryProvider = FutureProvider.autoDispose
    .family<StudentHistory, StudentModel>((ref, student) async {
  final db = ref.read(databaseServiceProvider);
  return db.getStudentHistory(student);
});
