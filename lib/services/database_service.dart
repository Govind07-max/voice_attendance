import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/attendance_alert.dart';
import '../models/attendance_edit.dart';
import '../models/attendance_mark.dart';
import '../models/attendance_record.dart';
import '../models/attendance_session.dart';
import '../models/class_model.dart';
import '../models/class_subject.dart';
import '../models/enrollment.dart';
import '../models/profile.dart';
import '../models/student.dart';
import '../models/student_history.dart';
import '../models/subject.dart';

abstract class DatabaseService {
  Future<List<ClassModel>> getClasses(String teacherId);
  Future<ClassModel> createClass(ClassModel classModel);
  Future<void> deleteClass(String classId);

  Future<List<SubjectModel>> getSubjects(String teacherId);
  Future<SubjectModel> createSubject(SubjectModel subjectModel);
  Future<void> deleteSubject(String subjectId);

  Future<List<ClassSubjectModel>> getClassSubjects(String teacherId);
  Future<ClassSubjectModel> createClassSubject(ClassSubjectModel cs);
  Future<void> updateClassSubject(ClassSubjectModel cs);
  Future<void> deleteClassSubject(String classSubjectId);

  Future<List<StudentModel>> getStudents(String teacherId);
  Future<void> bulkImportStudentsAndEnroll({
    required String teacherId,
    required String classSubjectId,
    required List<StudentModel> students,
  });
  Future<List<EnrollmentModel>> getEnrollments(String classSubjectId);
  Future<void> deleteEnrollment(String enrollmentId);

  /// Removes a student from one class + subject without deleting the student
  /// identity or their historical attendance records.
  Future<void> removeStudentFromClass({
    required String classSubjectId,
    required String studentId,
  });

  Future<AttendanceSessionModel> startAttendanceSession({
    required String classSubjectId,
    required DateTime date,
    int periodNumber = 1,
  });
  Future<List<AttendanceSessionModel>> getSessionsForDate({
    required String classSubjectId,
    required DateTime date,
  });
  Future<void> markStudentAttendance({
    required String sessionId,
    required String studentId,
    required String status, // 'present', 'absent'
    required String source, // 'voice', 'manual', 'default'
  });
  Future<void> completeSession(String sessionId);
  Future<List<AttendanceSessionModel>> getCompletedSessions(
      String classSubjectId);
  Future<List<AttendanceSessionModel>> getActiveSessions(String classSubjectId);
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSessions(
      List<String> sessionIds);
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSession(
      String sessionId);

  /// Sends many marks in ONE request (a 60-student lecture is one round trip).
  Future<void> markAttendanceBatch(List<AttendanceMark> marks);

  /// Every lecture of every class + subject the teacher owns, in one query.
  Future<List<AttendanceSessionModel>> getCompletedSessionsForTeacher(
      List<String> classSubjectIds);

  /// Every roster entry across the teacher's class + subjects, in one query.
  Future<List<EnrollmentModel>> getEnrollmentsForTeacher(
      List<String> classSubjectIds);

  /// Lectures already recorded on a date (for the dashboard "Today" card).
  Future<List<AttendanceSessionModel>> getSessionsForTeacherOnDate(
      List<String> classSubjectIds, DateTime date);

  Future<List<AttendanceAlertModel>> getAlerts(String classSubjectId);

  /// Email history across all of the teacher's class + subjects.
  Future<List<AttendanceAlertModel>> getAlertsForTeacher(
      List<String> classSubjectIds);

  // ---- Meeting slots (teacher availability) ----
  Future<List<TeacherAvailability>> getTeacherAvailability(String teacherId);
  Future<TeacherAvailability> addTeacherAvailability({
    required String teacherId,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
  });
  Future<void> deleteTeacherAvailability(String availabilityId);

  // ---- Per-student history ----
  Future<StudentHistory> getStudentHistory(StudentModel student);

  // ---- Edit audit trail ----
  Future<void> logAttendanceEdit({
    required String teacherId,
    required String sessionId,
    required String studentId,
    required String? oldStatus,
    required String newStatus,
    required String? oldSource,
    required String newSource,
  });
  Future<List<AttendanceEditModel>> getAttendanceEditsForSession(
      String sessionId);
}

class SupabaseDatabaseService implements DatabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<List<ClassModel>> getClasses(String teacherId) async {
    final response = await _client
        .from(AppConstants.tableClasses)
        .select()
        .eq('teacher_id', teacherId)
        .order('created_at', ascending: false);

    return (response as List).map((json) => ClassModel.fromJson(json)).toList();
  }

  @override
  Future<ClassModel> createClass(ClassModel classModel) async {
    final json = classModel.toJson()..remove('id');
    final response = await _client
        .from(AppConstants.tableClasses)
        .insert(json)
        .select()
        .single();
    return ClassModel.fromJson(response);
  }

  @override
  Future<void> deleteClass(String classId) async {
    await _client.from(AppConstants.tableClasses).delete().eq('id', classId);
  }

  @override
  Future<List<SubjectModel>> getSubjects(String teacherId) async {
    final response = await _client
        .from(AppConstants.tableSubjects)
        .select()
        .eq('teacher_id', teacherId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => SubjectModel.fromJson(json))
        .toList();
  }

  @override
  Future<SubjectModel> createSubject(SubjectModel subjectModel) async {
    final json = subjectModel.toJson()..remove('id');
    final response = await _client
        .from(AppConstants.tableSubjects)
        .insert(json)
        .select()
        .single();
    return SubjectModel.fromJson(response);
  }

  @override
  Future<void> deleteSubject(String subjectId) async {
    await _client.from(AppConstants.tableSubjects).delete().eq('id', subjectId);
  }

  @override
  Future<List<ClassSubjectModel>> getClassSubjects(String teacherId) async {
    final response = await _client
        .from(AppConstants.tableClassSubjects)
        .select('*, classes(*), subjects(*)')
        .eq('teacher_id', teacherId)
        .eq('active', true)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => ClassSubjectModel.fromJson(json))
        .toList();
  }

  @override
  Future<ClassSubjectModel> createClassSubject(ClassSubjectModel cs) async {
    final json = cs.toJson()..remove('id');
    final response = await _client
        .from(AppConstants.tableClassSubjects)
        .insert(json)
        .select('*, classes(*), subjects(*)')
        .single();
    return ClassSubjectModel.fromJson(response);
  }

  @override
  Future<void> updateClassSubject(ClassSubjectModel cs) async {
    await _client
        .from(AppConstants.tableClassSubjects)
        .update(cs.toJson())
        .eq('id', cs.id);
  }

  @override
  Future<void> deleteClassSubject(String classSubjectId) async {
    await _client
        .from(AppConstants.tableClassSubjects)
        .delete()
        .eq('id', classSubjectId);
  }

  @override
  Future<List<StudentModel>> getStudents(String teacherId) async {
    final response = await _client
        .from(AppConstants.tableStudents)
        .select()
        .eq('teacher_id', teacherId)
        .order('prn', ascending: true);

    return (response as List)
        .map((json) => StudentModel.fromJson(json))
        .toList();
  }

  /// Imports the roster in 2 requests instead of 2-per-student:
  ///   1. multi-row upsert into students   (on conflict teacher_id + prn)
  ///   2. multi-row upsert into enrollments (on conflict class_subject_id + student_id)
  @override
  Future<void> bulkImportStudentsAndEnroll({
    required String teacherId,
    required String classSubjectId,
    required List<StudentModel> students,
  }) async {
    if (students.isEmpty) return;

    final studentRows = students
        .map((s) => {
              'teacher_id': teacherId,
              'prn': s.prn,
              'student_name': s.studentName,
              'email': s.email,
            })
        .toList();

    final upserted = await _client
        .from(AppConstants.tableStudents)
        .upsert(studentRows, onConflict: 'teacher_id,prn')
        .select('id,prn');

    final idByPrn = <String, String>{};
    for (final row in (upserted as List)) {
      idByPrn[row['prn'] as String] = row['id'] as String;
    }

    final enrollRows = <Map<String, dynamic>>[];
    for (final s in students) {
      final studentId = idByPrn[s.prn];
      if (studentId == null) continue;
      enrollRows.add({
        'class_subject_id': classSubjectId,
        'student_id': studentId,
        'enrolled_from': DateTime.now().toIso8601String().split('T')[0],
        'enrolled_to': null,
        'active': true,
      });
    }

    if (enrollRows.isNotEmpty) {
      await _client
          .from(AppConstants.tableEnrollments)
          .upsert(enrollRows, onConflict: 'class_subject_id,student_id');
    }
  }

  @override
  Future<List<EnrollmentModel>> getEnrollments(String classSubjectId) async {
    final response = await _client
        .from(AppConstants.tableEnrollments)
        .select('*, students(*)')
        .eq('class_subject_id', classSubjectId)
        .eq('active', true)
        .order('created_at', ascending: true);

    return (response as List)
        .map((json) => EnrollmentModel.fromJson(json))
        .toList();
  }

  @override
  Future<void> deleteEnrollment(String enrollmentId) async {
    await _client
        .from(AppConstants.tableEnrollments)
        .delete()
        .eq('id', enrollmentId);
  }

  @override
  Future<void> removeStudentFromClass({
    required String classSubjectId,
    required String studentId,
  }) async {
    await _client
        .from(AppConstants.tableEnrollments)
        .update({
          'active': false,
          'enrolled_to': DateTime.now().toIso8601String().split('T')[0],
        })
        .eq('class_subject_id', classSubjectId)
        .eq('student_id', studentId);
  }

  @override
  Future<List<EnrollmentModel>> getEnrollmentsForTeacher(
      List<String> classSubjectIds) async {
    if (classSubjectIds.isEmpty) return [];

    final response = await _client
        .from(AppConstants.tableEnrollments)
        .select('*, students(*)')
        .inFilter('class_subject_id', classSubjectIds)
        .eq('active', true);

    return (response as List)
        .map((json) => EnrollmentModel.fromJson(json))
        .toList();
  }

  @override
  Future<AttendanceSessionModel> startAttendanceSession({
    required String classSubjectId,
    required DateTime date,
    int periodNumber = 1,
  }) async {
    final sessionJson = {
      'class_subject_id': classSubjectId,
      'lecture_date': date.toIso8601String().split('T')[0],
      'period_number': periodNumber,
      'status': 'active',
      'started_at': DateTime.now().toIso8601String(),
    };

    final sessionResponse = await _client
        .from(AppConstants.tableAttendanceSessions)
        .insert(sessionJson)
        .select()
        .single();

    final session = AttendanceSessionModel.fromJson(sessionResponse);

    // Rule 4: at the start of a lecture every enrolled student is absent.
    final enrollments = await getEnrollments(classSubjectId);
    if (enrollments.isNotEmpty) {
      final recordsToInsert = enrollments
          .map((e) => {
                'session_id': session.id,
                'student_id': e.studentId,
                'status': 'absent',
                'source': 'default',
                'marked_at': DateTime.now().toIso8601String(),
              })
          .toList();

      try {
        await _client
            .from(AppConstants.tableAttendanceRecords)
            .insert(recordsToInsert);
      } catch (e) {
        // Do not leave an active session with no roster records behind: the
        // unique date/period constraint would block the teacher's retry.
        try {
          await _client
              .from(AppConstants.tableAttendanceSessions)
              .delete()
              .eq('id', session.id);
        } catch (_) {
          // Best effort cleanup; the original error is the actionable one.
        }
        rethrow;
      }
    }

    return session;
  }

  @override
  Future<List<AttendanceSessionModel>> getSessionsForDate({
    required String classSubjectId,
    required DateTime date,
  }) async {
    final day = date.toIso8601String().split('T')[0];
    final response = await _client
        .from(AppConstants.tableAttendanceSessions)
        .select()
        .eq('class_subject_id', classSubjectId)
        .eq('lecture_date', day)
        .order('period_number', ascending: true);

    return (response as List)
        .map((json) => AttendanceSessionModel.fromJson(json))
        .toList();
  }

  @override
  Future<void> markStudentAttendance({
    required String sessionId,
    required String studentId,
    required String status,
    required String source,
  }) async {
    final recordJson = {
      'session_id': sessionId,
      'student_id': studentId,
      'status': status,
      'source': source,
      'marked_at': DateTime.now().toIso8601String(),
    };

    // Rule 7: one record per student per session (upsert on the unique key).
    await _client
        .from(AppConstants.tableAttendanceRecords)
        .upsert(recordJson, onConflict: 'session_id,student_id');
  }

  @override
  Future<void> markAttendanceBatch(List<AttendanceMark> marks) async {
    if (marks.isEmpty) return;

    final rows = marks.map((m) => m.toJson()).toList();
    // One round trip for the whole lecture (Rule 7 still holds: the unique
    // key makes this an upsert, never a duplicate row).
    await _client
        .from(AppConstants.tableAttendanceRecords)
        .upsert(rows, onConflict: 'session_id,student_id');
  }

  @override
  Future<void> completeSession(String sessionId) async {
    await _client.from(AppConstants.tableAttendanceSessions).update({
      'status': 'completed',
      'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }

  @override
  Future<List<AttendanceSessionModel>> getCompletedSessions(
      String classSubjectId) async {
    final response = await _client
        .from(AppConstants.tableAttendanceSessions)
        .select()
        .eq('class_subject_id', classSubjectId)
        .eq('status', 'completed')
        .order('lecture_date', ascending: true);

    return (response as List)
        .map((json) => AttendanceSessionModel.fromJson(json))
        .toList();
  }

  @override
  Future<List<AttendanceSessionModel>> getCompletedSessionsForTeacher(
      List<String> classSubjectIds) async {
    if (classSubjectIds.isEmpty) return [];

    final response = await _client
        .from(AppConstants.tableAttendanceSessions)
        .select()
        .inFilter('class_subject_id', classSubjectIds)
        .eq('status', 'completed')
        .order('lecture_date', ascending: true);

    return (response as List)
        .map((json) => AttendanceSessionModel.fromJson(json))
        .toList();
  }

  @override
  Future<List<AttendanceSessionModel>> getSessionsForTeacherOnDate(
      List<String> classSubjectIds, DateTime date) async {
    if (classSubjectIds.isEmpty) return [];

    final day = date.toIso8601String().split('T')[0];
    final response = await _client
        .from(AppConstants.tableAttendanceSessions)
        .select()
        .inFilter('class_subject_id', classSubjectIds)
        .eq('lecture_date', day)
        .order('period_number', ascending: true);

    return (response as List)
        .map((json) => AttendanceSessionModel.fromJson(json))
        .toList();
  }

  @override
  Future<List<AttendanceSessionModel>> getActiveSessions(
      String classSubjectId) async {
    final response = await _client
        .from(AppConstants.tableAttendanceSessions)
        .select()
        .eq('class_subject_id', classSubjectId)
        .eq('status', 'active')
        .order('lecture_date', ascending: false);

    return (response as List)
        .map((json) => AttendanceSessionModel.fromJson(json))
        .toList();
  }

  @override
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSessions(
      List<String> sessionIds) async {
    if (sessionIds.isEmpty) return [];

    final response = await _client
        .from(AppConstants.tableAttendanceRecords)
        .select('*, students(*)')
        .inFilter('session_id', sessionIds);

    return (response as List)
        .map((json) => AttendanceRecordModel.fromJson(json))
        .toList();
  }

  @override
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSession(
      String sessionId) async {
    final response = await _client
        .from(AppConstants.tableAttendanceRecords)
        .select('*, students(*)')
        .eq('session_id', sessionId);

    return (response as List)
        .map((json) => AttendanceRecordModel.fromJson(json))
        .toList();
  }

  @override
  Future<List<AttendanceAlertModel>> getAlerts(String classSubjectId) async {
    final response = await _client
        .from(AppConstants.tableAttendanceAlerts)
        .select('*, students(*)')
        .eq('class_subject_id', classSubjectId)
        .order('sent_at', ascending: false);

    return (response as List)
        .map((json) => AttendanceAlertModel.fromJson(json))
        .toList();
  }

  @override
  Future<List<AttendanceAlertModel>> getAlertsForTeacher(
      List<String> classSubjectIds) async {
    if (classSubjectIds.isEmpty) return [];

    final response = await _client
        .from(AppConstants.tableAttendanceAlerts)
        .select('*, students(*)')
        .inFilter('class_subject_id', classSubjectIds)
        .order('sent_at', ascending: false)
        .limit(200);

    return (response as List)
        .map((json) => AttendanceAlertModel.fromJson(json))
        .toList();
  }

  // ------------------------------------------------------------------
  // Meeting slots
  // ------------------------------------------------------------------
  @override
  Future<List<TeacherAvailability>> getTeacherAvailability(
      String teacherId) async {
    final response = await _client
        .from(AppConstants.tableTeacherAvailability)
        .select()
        .eq('teacher_id', teacherId)
        .eq('active', true)
        .order('day_of_week', ascending: true)
        .order('start_time', ascending: true);

    return (response as List)
        .map((json) => TeacherAvailability.fromJson(json))
        .toList();
  }

  @override
  Future<TeacherAvailability> addTeacherAvailability({
    required String teacherId,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
  }) async {
    final response = await _client
        .from(AppConstants.tableTeacherAvailability)
        .insert({
          'teacher_id': teacherId,
          'day_of_week': dayOfWeek,
          'start_time': startTime,
          'end_time': endTime,
          'active': true,
        })
        .select()
        .single();

    return TeacherAvailability.fromJson(response);
  }

  @override
  Future<void> deleteTeacherAvailability(String availabilityId) async {
    await _client
        .from(AppConstants.tableTeacherAvailability)
        .delete()
        .eq('id', availabilityId);
  }

  // ------------------------------------------------------------------
  // Per-student history
  // ------------------------------------------------------------------
  @override
  Future<StudentHistory> getStudentHistory(StudentModel student) async {
    // 1. Which class + subjects has this student ever enrolled in? (with names)
    // Active is intentionally not filtered here: removing a student from a
    // class keeps their past attendance visible in their history.
    final enrollmentRows = await _client
        .from(AppConstants.tableEnrollments)
        .select('*, class_subjects!inner(*, classes(*), subjects(*))')
        .eq('student_id', student.id);

    final classSubjects = <String, ClassSubjectModel>{};
    for (final row in (enrollmentRows as List)) {
      final raw = row['class_subjects'];
      if (raw is Map) {
        final cs = ClassSubjectModel.fromJson(Map<String, dynamic>.from(raw));
        classSubjects[cs.id] = cs;
      }
    }
    if (classSubjects.isEmpty) return StudentHistory.empty(student);

    // 2. Every attendance record for this student.
    final recordRows = await _client
        .from(AppConstants.tableAttendanceRecords)
        .select()
        .eq('student_id', student.id);
    final records = (recordRows as List)
        .map((json) => AttendanceRecordModel.fromJson(json))
        .toList();
    if (records.isEmpty) return StudentHistory.empty(student);

    // 3. The lectures those records belong to (finalized ones only, matching
    //    the percentage rules used by the reports).
    final sessionIds = records.map((r) => r.sessionId).toSet().toList();
    final sessionRows = await _client
        .from(AppConstants.tableAttendanceSessions)
        .select()
        .inFilter('id', sessionIds)
        .eq('status', 'completed');
    final sessions = (sessionRows as List)
        .map((json) => AttendanceSessionModel.fromJson(json))
        .where((s) => classSubjects.containsKey(s.classSubjectId))
        .toList();

    final recordBySession = {for (final r in records) r.sessionId: r};

    final entries = <StudentHistoryEntry>[];
    for (final session in sessions) {
      final record = recordBySession[session.id];
      if (record == null) continue;
      entries.add(StudentHistoryEntry(
        session: session,
        status: record.status,
        source: record.source,
        classSubject: classSubjects[session.classSubjectId]!,
      ));
    }
    entries.sort((a, b) {
      final byDate = b.session.lectureDate.compareTo(a.session.lectureDate);
      if (byDate != 0) return byDate;
      return b.session.periodNumber.compareTo(a.session.periodNumber);
    });

    final summaries = <StudentSubjectSummary>[];
    for (final cs in classSubjects.values) {
      final csEntries =
          entries.where((e) => e.classSubject.id == cs.id).toList();
      final attended = csEntries.where((e) => e.isPresent).length;
      final conducted = csEntries.length;
      summaries.add(StudentSubjectSummary(
        classSubject: cs,
        attended: attended,
        conducted: conducted,
        percentage: conducted == 0 ? 100.0 : (attended / conducted) * 100.0,
      ));
    }
    summaries.sort((a, b) => (a.classSubject.subjectDetails?.subjectName ?? '')
        .compareTo(b.classSubject.subjectDetails?.subjectName ?? ''));

    return StudentHistory(
      student: student,
      entries: entries,
      summaries: summaries,
    );
  }

  // ------------------------------------------------------------------
  // Edit audit trail
  // ------------------------------------------------------------------
  @override
  Future<void> logAttendanceEdit({
    required String teacherId,
    required String sessionId,
    required String studentId,
    required String? oldStatus,
    required String newStatus,
    required String? oldSource,
    required String newSource,
  }) async {
    await _client.from(AppConstants.tableAttendanceEdits).insert({
      'teacher_id': teacherId,
      'session_id': sessionId,
      'student_id': studentId,
      'old_status': oldStatus,
      'new_status': newStatus,
      'old_source': oldSource,
      'new_source': newSource,
    });
  }

  @override
  Future<List<AttendanceEditModel>> getAttendanceEditsForSession(
      String sessionId) async {
    final response = await _client
        .from(AppConstants.tableAttendanceEdits)
        .select('*, students(*)')
        .eq('session_id', sessionId)
        .order('edited_at', ascending: false)
        .limit(100);

    return (response as List)
        .map((json) => AttendanceEditModel.fromJson(json))
        .toList();
  }
}
