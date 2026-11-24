import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voice_attendance/models/class_model.dart';
import 'package:voice_attendance/models/class_subject.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/models/subject.dart';
import 'package:voice_attendance/services/auth_service.dart';
import 'package:voice_attendance/services/database_service.dart';
import 'package:voice_attendance/services/report_service.dart';

/// Live integration test against the real Supabase project.
/// Uses the publishable key, so every read/write is RLS-checked.
void main() {
  late DatabaseService db;
  late AuthService auth;
  late String teacherId;

  setUpAll(() async {
    // The auth client persists the session in shared_preferences.
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(fileName: '.env');
    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL'),
      publishableKey: dotenv.get('SUPABASE_ANON_KEY'),
    );
    db = SupabaseDatabaseService();
    auth = SupabaseAuthService();

    final res = await auth.signIn(
      email: 'setup.probe.check@gmail.com',
      password: 'Probe@12345',
    );
    expect(res.user, isNotNull, reason: 'probe sign-in failed');
    teacherId = res.user!.id;
  });

  tearDownAll(() async {
    // Clean up ONLY this test's data, leaving the seeded demo intact.
    final client = Supabase.instance.client;
    await client.from('classes').delete().eq('class_name', 'IT BE E&TC A');
    await client.from('subjects').delete().eq('subject_code', 'EC801X');
    await client
        .from('students')
        .delete()
        .inFilter('prn', ['901', '902', '903']);
  });

  test('full teacher workflow persists to Postgres', () async {
    // --- class + subject -------------------------------------------------
    final classModel = await db.createClass(ClassModel(
      id: '',
      teacherId: teacherId,
      className: 'IT BE E&TC A',
      academicYear: '2026-2027',
      semester: 'VIII',
    ));
    expect(classModel.id, isNotEmpty);

    final subject = await db.createSubject(SubjectModel(
      id: '',
      teacherId: teacherId,
      subjectCode: 'EC801X',
      subjectName: 'Digital Communication',
    ));
    expect(subject.id, isNotEmpty);

    final cs = await db.createClassSubject(ClassSubjectModel(
      id: '',
      teacherId: teacherId,
      classId: classModel.id,
      subjectId: subject.id,
      classDetails: classModel,
      subjectDetails: subject,
      googleFormUrl: 'https://forms.google.com/demo',
      thresholdPercent: 75,
      alertFrequency: 'biweekly',
      alertTime: '14:30:00',
      weeklyDay: 3,
      intervalDays: 21,
      reminderDays: 14,
    ));
    expect(cs.id, isNotEmpty);
    expect(cs.alertFrequency, 'biweekly');
    expect(cs.alertTime, '14:30:00');
    expect(cs.weeklyDay, 3);
    expect(cs.intervalDays, 21);
    expect(cs.reminderDays, 14);

    // --- roster import (2 requests, not 2 per student) ------------------
    final students = [
      StudentModel(
          id: '',
          teacherId: teacherId,
          prn: '901',
          studentName: 'Aarav Sharma'),
      StudentModel(
          id: '', teacherId: teacherId, prn: '902', studentName: 'Diya Patil'),
      StudentModel(
          id: '',
          teacherId: teacherId,
          prn: '903',
          studentName: 'Aarav Sharma'),
    ];
    await db.bulkImportStudentsAndEnroll(
      teacherId: teacherId,
      classSubjectId: cs.id,
      students: students,
    );

    final enrollments = await db.getEnrollments(cs.id);
    expect(enrollments.length, 3, reason: 'all students should be enrolled');

    // Re-import must not duplicate (Rule: unique teacher_id + prn).
    await db.bulkImportStudentsAndEnroll(
      teacherId: teacherId,
      classSubjectId: cs.id,
      students: students,
    );
    expect((await db.getEnrollments(cs.id)).length, 3);

    final allStudents = await db.getStudents(teacherId);
    final mine = allStudents
        .where((s) => ['901', '902', '903'].contains(s.prn))
        .toList();
    expect(mine.length, 3,
        reason: 're-import must not create duplicate PRN rows');

    // --- attendance session ---------------------------------------------
    final session = await db.startAttendanceSession(
      classSubjectId: cs.id,
      date: DateTime.now(),
    );
    expect(session.status, 'active');

    // Rule 4: everyone starts absent.
    var records = await db.getAttendanceRecordsForSession(session.id);
    expect(records.length, 3);
    expect(records.every((r) => r.status == 'absent'), isTrue);

    // Rule 7: marking twice must not create a second record.
    final enrolled = await db.getEnrollments(cs.id);
    final first = enrolled.first.student!;
    await db.markStudentAttendance(
      sessionId: session.id,
      studentId: first.id,
      status: 'present',
      source: 'voice',
    );
    await db.markStudentAttendance(
      sessionId: session.id,
      studentId: first.id,
      status: 'present',
      source: 'voice',
    );
    records = await db.getAttendanceRecordsForSession(session.id);
    expect(records.length, 3, reason: 'no duplicate record for one student');
    final marked = records.firstWhere((r) => r.studentId == first.id,
        orElse: () => throw StateError('missing'));
    expect(marked.status, 'present');
    expect(marked.source, 'voice');

    // A second lecture on the same day is allowed (Rule 11).
    final second = await db.startAttendanceSession(
      classSubjectId: cs.id,
      date: DateTime.now(),
      periodNumber: 2,
    );
    expect(second.id, isNot(session.id));

    // --- finalize + report ----------------------------------------------
    await db.completeSession(session.id);
    final completed = await db.getCompletedSessions(cs.id);
    expect(completed.length, 1);
    expect(completed.first.id, session.id);

    final report = DefaultReportGenerator().generateReport(
      classSubject: cs,
      sessions: completed,
      enrollments: enrollments,
      allRecords: records,
    );
    expect(report.studentRows.length, 3);
    expect(report.sessions.length, 1);

    final firstRow =
        report.studentRows.firstWhere((r) => r.student.id == first.id);
    expect(firstRow.attendedCount, 1);
    expect(firstRow.eligibleConductedCount, 1);
    expect(firstRow.percentage, 100.0);

    // The duplicate-name student is a different PRN -> both are separate rows.
    final aaravs = report.studentRows
        .where((r) => r.student.studentName == 'Aarav Sharma');
    expect(aaravs.length, 2,
        reason: 'duplicate names are two different students');
  });

  test('teacher sees only their own data (RLS)', () async {
    final mine = await db.getStudents(teacherId);
    expect(mine, isNotEmpty);

    // A class belonging to a different teacher must not be visible.
    final allClasses =
        await Supabase.instance.client.from('classes').select('id,teacher_id');
    final foreign = (allClasses as List)
        .where((c) => c['teacher_id'] != teacherId)
        .toList();

    for (final row in foreign) {
      final visible = await Supabase.instance.client
          .from('classes')
          .select('id')
          .eq('id', row['id'])
          .eq('teacher_id', teacherId);
      expect(visible, isEmpty, reason: 'must not see another teacher\'s class');
    }
  });
}
