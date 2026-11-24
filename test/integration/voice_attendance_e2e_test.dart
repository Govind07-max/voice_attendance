import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voice_attendance/models/class_model.dart';
import 'package:voice_attendance/models/attendance_mark.dart';
import 'package:voice_attendance/models/class_subject.dart';
import 'package:voice_attendance/models/subject.dart';
import 'package:voice_attendance/services/auth_service.dart';
import 'package:voice_attendance/services/database_service.dart';
import 'package:voice_attendance/services/excel_service.dart';
import 'package:voice_attendance/services/voice_command_service.dart';
import 'package:voice_attendance/core/errors.dart';
import 'package:voice_attendance/services/report_service.dart';

/// A formatted sheet like a real college roster export:
/// title rows, a blank row, "Sr. No." + "Admission ID" + "Student Name" +
/// "Email ID" + "Semester" headers and a trailing "Total" row.
Uint8List buildFormattedRoster() {
  final excel = Excel.createExcel();
  final sheet = excel['Student List'];
  sheet.appendRow(
      [TextCellValue('Department of Electronics & Telecommunication')]);
  sheet.appendRow([TextCellValue('Academic Year 2026-27')]);
  sheet.appendRow([TextCellValue('')]);
  sheet.appendRow([
    TextCellValue('Sr. No.'),
    TextCellValue('Admission ID'),
    TextCellValue('Student Name'),
    TextCellValue('Email ID'),
    TextCellValue('Semester'),
  ]);
  sheet.appendRow([
    IntCellValue(1),
    TextCellValue('501'),
    TextCellValue('Vedant Joshi'),
    TextCellValue('vedant@univ.edu'),
    TextCellValue('VI'),
  ]);
  sheet.appendRow([
    IntCellValue(2),
    TextCellValue('502'),
    TextCellValue('Riya Kamble'),
    TextCellValue('riya@univ.edu'),
    TextCellValue('VI'),
  ]);
  sheet.appendRow([
    IntCellValue(3),
    TextCellValue('503'),
    TextCellValue('Sumit Bhosale'),
    TextCellValue('sumit@univ.edu'),
    TextCellValue('VI'),
  ]);
  sheet.appendRow([
    TextCellValue('Total'),
    TextCellValue('3'),
    TextCellValue(''),
    TextCellValue(''),
    TextCellValue(''),
  ]);
  return Uint8List.fromList(excel.save()!);
}

/// End-to-end backend flow against the live project:
/// create class -> import a FORMATTED excel -> start session ->
/// match a spoken name -> store it -> finalize -> cumulative report.
void main() {
  late DatabaseService db;
  late String teacherId;

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
  });

  tearDownAll(() async {
    final client = Supabase.instance.client;
    await client
        .from('classes')
        .delete()
        .inFilter('class_name', ['SE E&TC A', 'SE E&TC B']);
    await client
        .from('subjects')
        .delete()
        .inFilter('subject_code', ['EC999', 'EC998']);
    await client
        .from('students')
        .delete()
        .inFilter('prn', ['501', '502', '503']);
  });

  test('create class -> import formatted excel -> voice attendance -> stored',
      () async {
    // 1. Create a new class + subject (the "Add Class" flow).
    final classModel = await db.createClass(ClassModel(
      id: '',
      teacherId: teacherId,
      className: 'SE E&TC A',
      academicYear: '2026-2027',
      semester: 'VI',
    ));
    final subject = await db.createSubject(SubjectModel(
      id: '',
      teacherId: teacherId,
      subjectCode: 'EC999',
      subjectName: 'VLSI Design',
    ));
    final cs = await db.createClassSubject(ClassSubjectModel(
      id: '',
      teacherId: teacherId,
      classId: classModel.id,
      subjectId: subject.id,
      classDetails: classModel,
      subjectDetails: subject,
    ));
    expect(cs.id, isNotEmpty);

    // 2. Import a FORMATTED excel roster.
    final bytes = buildFormattedRoster();
    final preview = DefaultExcelService().parseStudentExcel(bytes, teacherId);
    expect(preview.errorMessages, isEmpty,
        reason: 'formatted roster should import cleanly');
    expect(preview.validStudents.length, 3);
    expect(preview.validStudents.map((s) => s.prn).toList(),
        ['501', '502', '503']);
    expect(preview.validStudents.first.studentName, 'Vedant Joshi');
    expect(preview.validStudents.first.email, 'vedant@univ.edu');

    await db.bulkImportStudentsAndEnroll(
      teacherId: teacherId,
      classSubjectId: cs.id,
      students: preview.validStudents,
    );

    final enrolled = await db.getEnrollments(cs.id);
    expect(enrolled.length, 3);
    expect(enrolled.map((e) => e.student!.studentName).toList(),
        containsAll(['Vedant Joshi', 'Riya Kamble', 'Sumit Bhosale']));

    // 3. Start a session (Rule 4 -> everyone absent).
    final session = await db.startAttendanceSession(
        classSubjectId: cs.id, date: DateTime.now());
    var records = await db.getAttendanceRecordsForSession(session.id);
    expect(records.length, 3);
    expect(records.every((r) => r.status == 'absent'), isTrue);

    // 4. The spoken instruction the recogniser would return, parsed and
    //    matched exactly like the attendance screen does it.
    const spoken = 'Vedant Joshi present';
    final command = VoiceCommandParser().parse(spoken);
    expect(command.status, VoiceStatus.present);
    expect(command.nameText, 'Vedant Joshi');

    final result = VoiceCommandParser()
        .resolve(command, enrolled.map((e) => e.student!).toList());
    expect(result.type.name, 'single');
    expect(result.matchedStudent!.studentName, 'Vedant Joshi');

    await db.markStudentAttendance(
      sessionId: session.id,
      studentId: result.matchedStudent!.id,
      status: 'present',
      source: 'voice',
    );

    // 4b. A spoken "absent" marks the student absent.
    final absentCommand = VoiceCommandParser().parse('Riya Kamble absent');
    expect(absentCommand.status, VoiceStatus.absent);
    final absentResult = VoiceCommandParser()
        .resolve(absentCommand, enrolled.map((e) => e.student!).toList());
    expect(absentResult.matchedStudent!.studentName, 'Riya Kamble');
    await db.markStudentAttendance(
      sessionId: session.id,
      studentId: absentResult.matchedStudent!.id,
      status: 'absent',
      source: 'voice',
    );

    // 4c. A PRN spoken by its last 3 digits finds the student.
    final prnCommand = VoiceCommandParser().parse('502 present');
    expect(prnCommand.digits, '502');
    final prnResult = VoiceCommandParser()
        .resolve(prnCommand, enrolled.map((e) => e.student!).toList());
    expect(prnResult.type.name, 'single');
    expect(prnResult.matchedStudent!.studentName, 'Riya Kamble');

    // 4d. The offline queue sends several marks in ONE upsert: this must update
    //     Riya (already absent) and add Sumit, with no duplicate rows.
    final third = enrolled
        .map((e) => e.student!)
        .firstWhere((s) => s.studentName == 'Sumit Bhosale');
    await db.markAttendanceBatch([
      AttendanceMark(
        sessionId: session.id,
        studentId: prnResult.matchedStudent!.id,
        status: 'present',
        source: 'voice',
        markedAt: DateTime.now(),
      ),
      AttendanceMark(
        sessionId: session.id,
        studentId: third.id,
        status: 'present',
        source: 'voice',
        markedAt: DateTime.now(),
      ),
    ]);

    // 5. Verify it landed in the database.
    records = await db.getAttendanceRecordsForSession(session.id);
    expect(records.length, 3, reason: 'no duplicate record (Rule 7)');
    final marked =
        records.firstWhere((r) => r.studentId == result.matchedStudent!.id);
    expect(marked.status, 'present');
    expect(marked.source, 'voice');

    final markedAbsent = records
        .firstWhere((r) => r.studentId == absentResult.matchedStudent!.id);
    expect(markedAbsent.status, 'present',
        reason: 'the batched upsert overrides the earlier absent mark');
    expect(markedAbsent.source, 'voice');

    final batched = records.firstWhere((r) => r.studentId == third.id);
    expect(batched.status, 'present',
        reason: 'the second mark in the same batch landed too');
    expect(batched.source, 'voice');

    // 6. Finalize and check the cumulative report picks it up.
    await db.completeSession(session.id);
    final completed = await db.getCompletedSessions(cs.id);
    expect(completed.length, 1);

    final report = DefaultReportGenerator().generateReport(
      classSubject: cs,
      sessions: completed,
      enrollments: enrolled,
      allRecords: records,
    );
    final row = report.studentRows
        .firstWhere((r) => r.student.studentName == 'Vedant Joshi');
    expect(row.attendedCount, 1);
    expect(row.percentage, 100.0);

    final absentRow = report.studentRows
        .firstWhere((r) => r.student.studentName == 'Riya Kamble');
    expect(absentRow.attendedCount, 1,
        reason: 'the batched mark made Riya present');
    expect(absentRow.percentage, 100.0);
  });

  test('two lectures on the same day use different periods', () async {
    final classModel = await db.createClass(ClassModel(
      id: '',
      teacherId: teacherId,
      className: 'SE E&TC B',
      academicYear: '2026-2027',
      semester: 'VI',
    ));
    final subject = await db.createSubject(SubjectModel(
      id: '',
      teacherId: teacherId,
      subjectCode: 'EC998',
      subjectName: 'Embedded Systems',
    ));
    final cs = await db.createClassSubject(ClassSubjectModel(
      id: '',
      teacherId: teacherId,
      classId: classModel.id,
      subjectId: subject.id,
      classDetails: classModel,
      subjectDetails: subject,
    ));

    final date = DateTime.now();
    final first = await db.startAttendanceSession(
        classSubjectId: cs.id, date: date, periodNumber: 1);
    expect(first.id, isNotEmpty);

    // The same period on the same day is rejected by the unique constraint.
    var duplicateBlocked = false;
    try {
      await db.startAttendanceSession(
          classSubjectId: cs.id, date: date, periodNumber: 1);
    } catch (e) {
      duplicateBlocked = true;
      expect(AppErrors.humanize(e), contains('already exists'));
    }
    expect(duplicateBlocked, isTrue,
        reason: 'a duplicate period must be rejected');

    // A different period works.
    final second = await db.startAttendanceSession(
        classSubjectId: cs.id, date: date, periodNumber: 2);
    expect(second.id, isNot(first.id));
  });
}
