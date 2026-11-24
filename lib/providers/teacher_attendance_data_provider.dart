import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance_record.dart';
import '../models/attendance_session.dart';
import '../models/class_subject.dart';
import '../models/enrollment.dart';
import 'classes_provider.dart';
import 'database_provider.dart';

/// Raw attendance data for one class + subject.
///
/// Keeping the three teacher-wide queries here means the dashboard, alerts,
/// and analytics all share the same Supabase round trips.
class ClassSubjectAttendanceData {
  final ClassSubjectModel classSubject;
  final List<AttendanceSessionModel> sessions;
  final List<EnrollmentModel> enrollments;
  final List<AttendanceRecordModel> records;

  const ClassSubjectAttendanceData({
    required this.classSubject,
    required this.sessions,
    required this.enrollments,
    required this.records,
  });
}

/// Everything needed to compute attendance statistics for a teacher.
final teacherAttendanceDataProvider =
    FutureProvider.autoDispose<List<ClassSubjectAttendanceData>>((ref) async {
  final classSubjects =
      ref.watch(classSubjectsProvider).valueOrNull ?? const [];
  if (classSubjects.isEmpty) return [];

  final db = ref.watch(databaseServiceProvider);
  final ids = classSubjects.map((cs) => cs.id).toList();

  // 1. every finalized lecture
  final sessions = await db.getCompletedSessionsForTeacher(ids);
  // 2. every roster entry
  final enrollments = await db.getEnrollmentsForTeacher(ids);
  // 3. every attendance record for those lectures
  final records = await db.getAttendanceRecordsForSessions(
    sessions.map((session) => session.id).toList(),
  );

  final sessionsByCs = <String, List<AttendanceSessionModel>>{};
  for (final session in sessions) {
    sessionsByCs.putIfAbsent(session.classSubjectId, () => []).add(session);
  }

  final enrollmentsByCs = <String, List<EnrollmentModel>>{};
  for (final enrollment in enrollments) {
    enrollmentsByCs
        .putIfAbsent(enrollment.classSubjectId, () => [])
        .add(enrollment);
  }

  final sessionIdToCs = {
    for (final session in sessions) session.id: session.classSubjectId,
  };
  final recordsByCs = <String, List<AttendanceRecordModel>>{};
  for (final record in records) {
    final classSubjectId = sessionIdToCs[record.sessionId];
    if (classSubjectId == null) continue;
    recordsByCs.putIfAbsent(classSubjectId, () => []).add(record);
  }

  return classSubjects
      .map((classSubject) => ClassSubjectAttendanceData(
            classSubject: classSubject,
            sessions: sessionsByCs[classSubject.id] ?? const [],
            enrollments: enrollmentsByCs[classSubject.id] ?? const [],
            records: recordsByCs[classSubject.id] ?? const [],
          ))
      .toList();
});
