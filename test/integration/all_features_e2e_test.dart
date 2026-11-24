import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voice_attendance/core/errors.dart';
import 'package:voice_attendance/models/attendance_mark.dart';
import 'package:voice_attendance/models/class_model.dart';
import 'package:voice_attendance/models/class_subject.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/models/subject.dart';
import 'package:voice_attendance/services/auth_service.dart';
import 'package:voice_attendance/services/database_service.dart';

/// Exercises every feature that touches Postgres, as a signed-in teacher.
void main() {
  late SupabaseDatabaseService db;
  late String teacherId;
  late String suffix;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(fileName: '.env');
    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL'),
      publishableKey: dotenv.get('SUPABASE_ANON_KEY'),
    );
    db = SupabaseDatabaseService();

    final res = await SupabaseAuthService().signIn(
      email: 'setup.probe.check@gmail.com',
      password: 'Probe@12345',
    );
    expect(res.user, isNotNull);
    teacherId = res.user!.id;
    suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(6);
  });

  tearDownAll(() async {
    final client = Supabase.instance.client;
    // Everything cascades from classes / subjects.
    await client.from('classes').delete().like('class_name', '%$suffix%');
    await client.from('subjects').delete().like('subject_code', '%$suffix%');
    await client.from('students').delete().like('prn', '$suffix%');
    await client
        .from('teacher_availability')
        .delete()
        .eq('teacher_id', teacherId)
        .eq('day_of_week', 6);
  });

  test('dashboard + reports + history + alerts read the real data', () async {
    final classModel = await db.createClass(ClassModel(
      id: '',
      teacherId: teacherId,
      className: 'E2E Class $suffix',
      academicYear: '2026-2027',
      semester: 'VI',
    ));
    final subject = await db.createSubject(SubjectModel(
      id: '',
      teacherId: teacherId,
      subjectCode: 'E2E$suffix',
      subjectName: 'E2E Subject $suffix',
    ));
    final cs = await db.createClassSubject(ClassSubjectModel(
      id: '',
      teacherId: teacherId,
      classId: classModel.id,
      subjectId: subject.id,
      classDetails: classModel,
      subjectDetails: subject,
    ));

    // Roster of two, imported the way the app imports it.
    final students = [
      StudentModel(
          id: '',
          teacherId: teacherId,
          prn: '${suffix}01',
          studentName: 'E2E Aarav'),
      StudentModel(
          id: '',
          teacherId: teacherId,
          prn: '${suffix}02',
          studentName: 'E2E Diya',
          email: 'diya.$suffix@univ.edu'),
    ];
    await db.bulkImportStudentsAndEnroll(
      teacherId: teacherId,
      classSubjectId: cs.id,
      students: students,
    );
    final enrolled = await db.getEnrollments(cs.id);
    expect(enrolled.length, 2);
    final present = enrolled[0].student!;
    final absent = enrolled[1].student!;

    // A lecture where one is present and one stays absent.
    final session = await db.startAttendanceSession(
      classSubjectId: cs.id,
      date: DateTime.now(),
      periodNumber: 3,
    );
    await db.markAttendanceBatch([
      AttendanceMark(
        sessionId: session.id,
        studentId: present.id,
        status: 'present',
        source: 'voice',
        markedAt: DateTime.now(),
      ),
    ]);
    await db.completeSession(session.id);

    // 1. Dashboard queries (3 requests in the provider, 1 per call here).
    final completed = await db.getCompletedSessionsForTeacher([cs.id]);
    expect(completed.length, 1);
    expect(completed.single.periodNumber, 3);

    final roster = await db.getEnrollmentsForTeacher([cs.id]);
    expect(roster.length, 2);

    final today = await db.getSessionsForTeacherOnDate([cs.id], DateTime.now());
    expect(today.length, 1);
    expect(today.single.status, 'completed');

    // 2. Per-student history.
    final presentHistory = await db.getStudentHistory(present);
    expect(presentHistory.summaries.length, 1);
    expect(presentHistory.summaries.single.attended, 1);
    expect(presentHistory.summaries.single.conducted, 1);
    expect(presentHistory.summaries.single.percentage, 100.0);
    expect(presentHistory.entries.length, 1);
    expect(presentHistory.entries.single.status, 'present');
    expect(presentHistory.entries.single.session.periodNumber, 3);

    final absentHistory = await db.getStudentHistory(absent);
    expect(absentHistory.summaries.single.attended, 0);
    expect(absentHistory.summaries.single.percentage, 0.0);
    expect(absentHistory.entries.single.status, 'absent');

    // Removing a student from this class must not erase their past lectures.
    await db.removeStudentFromClass(
      classSubjectId: cs.id,
      studentId: absent.id,
    );
    final rosterAfterRemoval = await db.getEnrollments(cs.id);
    expect(
        rosterAfterRemoval.map((e) => e.studentId), isNot(contains(absent.id)));
    expect(rosterAfterRemoval.map((e) => e.studentId), contains(present.id));
    final historyAfterRemoval = await db.getStudentHistory(absent);
    expect(historyAfterRemoval.entries.length, 1);
    expect(historyAfterRemoval.entries.single.status, 'absent');
    expect(historyAfterRemoval.summaries.single.conducted, 1);

    // 3. Alert history (written by the Apps Script in production).
    final client = Supabase.instance.client;
    await client.from('attendance_alerts').insert({
      'class_subject_id': cs.id,
      'student_id': absent.id,
      'attendance_percent': 0,
      'attended_count': 0,
      'conducted_count': 1,
      'alert_type': 'initial',
      'status': 'sent',
    });
    final alerts = await db.getAlertsForTeacher([cs.id]);
    expect(alerts.length, 1);
    expect(alerts.single.student?.studentName, 'E2E Diya');
    expect(alerts.single.status, 'sent');
    expect(alerts.single.alertType, 'initial');

    // 4. Delete the class: every child row must disappear with it.
    await db.deleteClass(classModel.id);
    final remaining = await db.getClassSubjects(teacherId);
    expect(remaining.where((c) => c.id == cs.id), isEmpty);
    expect(await db.getCompletedSessionsForTeacher([cs.id]), isEmpty);
    expect(await db.getAlertsForTeacher([cs.id]), isEmpty);

    await db.deleteSubject(subject.id);
  });

  test('manual edit audit trail is written and readable', () async {
    final classModel = await db.createClass(ClassModel(
      id: '',
      teacherId: teacherId,
      className: 'E2E Audit $suffix',
      academicYear: '2026-2027',
      semester: 'VI',
    ));
    final subject = await db.createSubject(SubjectModel(
      id: '',
      teacherId: teacherId,
      subjectCode: 'E2EA$suffix',
      subjectName: 'E2E Audit Subject',
    ));
    final cs = await db.createClassSubject(ClassSubjectModel(
      id: '',
      teacherId: teacherId,
      classId: classModel.id,
      subjectId: subject.id,
      classDetails: classModel,
      subjectDetails: subject,
    ));
    await db.bulkImportStudentsAndEnroll(
      teacherId: teacherId,
      classSubjectId: cs.id,
      students: [
        StudentModel(
            id: '',
            teacherId: teacherId,
            prn: '${suffix}11',
            studentName: 'E2E Kabir'),
      ],
    );
    final student = (await db.getEnrollments(cs.id)).single.student!;
    final session = await db.startAttendanceSession(
        classSubjectId: cs.id, date: DateTime.now());

    await db.logAttendanceEdit(
      teacherId: teacherId,
      sessionId: session.id,
      studentId: student.id,
      oldStatus: 'absent',
      newStatus: 'present',
      oldSource: 'default',
      newSource: 'manual',
    );

    final edits = await db.getAttendanceEditsForSession(session.id);
    expect(edits.length, 1);
    expect(edits.single.student?.studentName, 'E2E Kabir');
    expect(edits.single.oldStatus, 'absent');
    expect(edits.single.newStatus, 'present');
    expect(edits.single.newSource, 'manual');
  });

  test('meeting slots and roster removal', () async {
    // Slots: add -> read -> delete.
    final slot = await db.addTeacherAvailability(
      teacherId: teacherId,
      dayOfWeek: 6,
      startTime: '15:00:00',
      endTime: '16:30:00',
    );
    expect(slot.id, isNotEmpty);
    var slots = await db.getTeacherAvailability(teacherId);
    expect(slots.map((s) => s.id), contains(slot.id));
    expect(slots.firstWhere((s) => s.id == slot.id).startTime, '15:00:00');

    await db.deleteTeacherAvailability(slot.id);
    slots = await db.getTeacherAvailability(teacherId);
    expect(slots.map((s) => s.id), isNot(contains(slot.id)));

    // Enrollment removal (the "remove student" action).
    final classModel = await db.createClass(ClassModel(
      id: '',
      teacherId: teacherId,
      className: 'E2E Roster $suffix',
      academicYear: '2026-2027',
      semester: 'VI',
    ));
    final subject = await db.createSubject(SubjectModel(
      id: '',
      teacherId: teacherId,
      subjectCode: 'E2ER$suffix',
      subjectName: 'E2E Roster Subject',
    ));
    final cs = await db.createClassSubject(ClassSubjectModel(
      id: '',
      teacherId: teacherId,
      classId: classModel.id,
      subjectId: subject.id,
      classDetails: classModel,
      subjectDetails: subject,
    ));
    await db.bulkImportStudentsAndEnroll(
      teacherId: teacherId,
      classSubjectId: cs.id,
      students: [
        StudentModel(
            id: '',
            teacherId: teacherId,
            prn: '${suffix}21',
            studentName: 'E2E Ira'),
        StudentModel(
            id: '',
            teacherId: teacherId,
            prn: '${suffix}22',
            studentName: 'E2E Neel'),
      ],
    );
    var roster = await db.getEnrollments(cs.id);
    expect(roster.length, 2);

    final ira = roster.firstWhere((e) => e.student?.studentName == 'E2E Ira');
    await db.removeStudentFromClass(
      classSubjectId: cs.id,
      studentId: ira.studentId,
    );
    roster = await db.getEnrollments(cs.id);
    expect(roster.length, 1);
    expect(roster.single.student?.studentName, 'E2E Neel');

    // Re-adding the same PRN through the manual-add/import path must
    // reactivate the enrollment instead of creating a duplicate.
    await db.bulkImportStudentsAndEnroll(
      teacherId: teacherId,
      classSubjectId: cs.id,
      students: [
        StudentModel(
            id: '',
            teacherId: teacherId,
            prn: '${suffix}21',
            studentName: 'E2E Ira'),
      ],
    );
    roster = await db.getEnrollments(cs.id);
    expect(roster.length, 2);

    await db.deleteClassSubject(cs.id);
    expect(await db.getEnrollments(cs.id), isEmpty);
  });

  test('errors are translated, never raw SQL', () {
    final unique = AppErrors.humanize(Exception(
        'PostgrestException(message: duplicate key value violates unique '
        'constraint "unique_lecture", code: 23505)'));
    expect(unique, contains('period'));
    expect(unique, isNot(contains('23505')));

    final offline = AppErrors.humanize(
        Exception('SocketException: Failed host lookup: db.supabase.co'));
    expect(offline, contains('saved on this phone'));

    final auth = AppErrors.humanize(Exception(
        'AuthException(message: Invalid login credentials, code: invalid_credentials)'));
    expect(auth, 'Wrong email or password. Please try again.');

    final expired = AppErrors.humanize(
        Exception('PostgrestException(message: JWT expired, code: PGRST301)'));
    expect(expired, contains('sign in again'));
  });
}
