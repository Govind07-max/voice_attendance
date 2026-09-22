import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/attendance_alert.dart';
import '../models/attendance_record.dart';
import '../models/attendance_session.dart';
import '../models/class_model.dart';
import '../models/class_subject.dart';
import '../models/enrollment.dart';
import '../models/student.dart';
import '../models/subject.dart';

abstract class DatabaseService {
  Future<List<ClassModel>> getClasses(String teacherId);
  Future<ClassModel> createClass(ClassModel classModel);

  Future<List<SubjectModel>> getSubjects(String teacherId);
  Future<SubjectModel> createSubject(SubjectModel subjectModel);

  Future<List<ClassSubjectModel>> getClassSubjects(String teacherId);
  Future<ClassSubjectModel> createClassSubject(ClassSubjectModel cs);
  Future<void> updateClassSubject(ClassSubjectModel cs);

  Future<List<StudentModel>> getStudents(String teacherId);
  Future<void> bulkImportStudentsAndEnroll({
    required String teacherId,
    required String classSubjectId,
    required List<StudentModel> students,
  });
  Future<List<EnrollmentModel>> getEnrollments(String classSubjectId);

  Future<AttendanceSessionModel> startAttendanceSession({
    required String classSubjectId,
    required DateTime date,
    int periodNumber = 1,
  });
  Future<void> markStudentAttendance({
    required String sessionId,
    required String studentId,
    required String status, // 'present', 'absent'
    required String source, // 'voice', 'manual', 'default'
  });
  Future<void> completeSession(String sessionId);
  Future<List<AttendanceSessionModel>> getCompletedSessions(String classSubjectId);
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSessions(List<String> sessionIds);
  Future<List<AttendanceAlertModel>> getAlerts(String classSubjectId);
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
  Future<List<SubjectModel>> getSubjects(String teacherId) async {
    final response = await _client
        .from(AppConstants.tableSubjects)
        .select()
        .eq('teacher_id', teacherId)
        .order('created_at', ascending: false);

    return (response as List).map((json) => SubjectModel.fromJson(json)).toList();
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
  Future<List<ClassSubjectModel>> getClassSubjects(String teacherId) async {
    final response = await _client
        .from(AppConstants.tableClassSubjects)
        .select('*, classes(*), subjects(*)')
        .eq('teacher_id', teacherId)
        .eq('active', true);

    return (response as List).map((json) => ClassSubjectModel.fromJson(json)).toList();
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
  Future<List<StudentModel>> getStudents(String teacherId) async {
    final response = await _client
        .from(AppConstants.tableStudents)
        .select()
        .eq('teacher_id', teacherId)
        .order('prn', ascending: true);

    return (response as List).map((json) => StudentModel.fromJson(json)).toList();
  }

  @override
  Future<void> bulkImportStudentsAndEnroll({
    required String teacherId,
    required String classSubjectId,
    required List<StudentModel> students,
  }) async {
    for (var student in students) {
      // Upsert student in master table
      final studentJson = {
        'teacher_id': teacherId,
        'prn': student.prn,
        'student_name': student.studentName,
        'email': student.email,
      };

      final studentResponse = await _client
          .from(AppConstants.tableStudents)
          .upsert(studentJson, onConflict: 'teacher_id,prn')
          .select()
          .single();

      String studentId = studentResponse['id'];

      // Create enrollment mapping
      final enrollmentJson = {
        'class_subject_id': classSubjectId,
        'student_id': studentId,
        'enrolled_from': DateTime.now().toIso8601String().split('T')[0],
      };

      await _client
          .from(AppConstants.tableEnrollments)
          .upsert(enrollmentJson, onConflict: 'class_subject_id,student_id');
    }
  }

  @override
  Future<List<EnrollmentModel>> getEnrollments(String classSubjectId) async {
    final response = await _client
        .from(AppConstants.tableEnrollments)
        .select('*, students(*)')
        .eq('class_subject_id', classSubjectId)
        .eq('active', true);

    return (response as List).map((json) => EnrollmentModel.fromJson(json)).toList();
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

    AttendanceSessionModel session = AttendanceSessionModel.fromJson(sessionResponse);

    // Rule 4: At the beginning of a lecture, all enrolled students default to Absent
    final enrollments = await getEnrollments(classSubjectId);
    if (enrollments.isNotEmpty) {
      List<Map<String, dynamic>> recordsToInsert = enrollments.map((e) => {
        'session_id': session.id,
        'student_id': e.studentId,
        'status': 'absent',
        'source': 'default',
        'marked_at': DateTime.now().toIso8601String(),
      }).toList();

      await _client
          .from(AppConstants.tableAttendanceRecords)
          .insert(recordsToInsert);
    }

    return session;
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

    // Rule 7: Prevent duplicate records by upserting on unique session_id, student_id
    await _client
        .from(AppConstants.tableAttendanceRecords)
        .upsert(recordJson, onConflict: 'session_id,student_id');
  }

  @override
  Future<void> completeSession(String sessionId) async {
    await _client
        .from(AppConstants.tableAttendanceSessions)
        .update({
          'status': 'completed',
          'ended_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  @override
  Future<List<AttendanceSessionModel>> getCompletedSessions(String classSubjectId) async {
    final response = await _client
        .from(AppConstants.tableAttendanceSessions)
        .select()
        .eq('class_subject_id', classSubjectId)
        .eq('status', 'completed')
        .order('lecture_date', ascending: true);

    return (response as List).map((json) => AttendanceSessionModel.fromJson(json)).toList();
  }

  @override
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSessions(List<String> sessionIds) async {
    if (sessionIds.isEmpty) return [];

    final response = await _client
        .from(AppConstants.tableAttendanceRecords)
        .select('*, students(*)')
        .inFilter('session_id', sessionIds);

    return (response as List).map((json) => AttendanceRecordModel.fromJson(json)).toList();
  }

  @override
  Future<List<AttendanceAlertModel>> getAlerts(String classSubjectId) async {
    final response = await _client
        .from(AppConstants.tableAttendanceAlerts)
        .select('*, students(*)')
        .eq('class_subject_id', classSubjectId)
        .order('sent_at', ascending: false);

    return (response as List).map((json) => AttendanceAlertModel.fromJson(json)).toList();
  }
}
