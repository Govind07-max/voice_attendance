import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/features/attendance/attendance_screen.dart';
import 'package:voice_attendance/models/attendance_alert.dart';
import 'package:voice_attendance/models/attendance_edit.dart';
import 'package:voice_attendance/models/attendance_mark.dart';
import 'package:voice_attendance/models/attendance_record.dart';
import 'package:voice_attendance/models/attendance_session.dart';
import 'package:voice_attendance/models/class_model.dart';
import 'package:voice_attendance/models/class_subject.dart';
import 'package:voice_attendance/models/enrollment.dart';
import 'package:voice_attendance/models/profile.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/models/student_history.dart';
import 'package:voice_attendance/models/subject.dart';
import 'package:voice_attendance/providers/attendance_controller.dart';
import 'package:voice_attendance/providers/classes_provider.dart';
import 'package:voice_attendance/providers/database_provider.dart';
import 'package:voice_attendance/services/attendance_writer.dart';
import 'package:voice_attendance/services/database_service.dart';

const speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
const permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');

/// In-memory stand-in for Postgres so the screen can be driven without network.
class FakeDatabaseService implements DatabaseService {
  final List<StudentModel> students = [
    StudentModel(
        id: 's1',
        teacherId: 't1',
        prn: '72145001',
        studentName: 'Vedant Joshi'),
    StudentModel(
        id: 's2', teacherId: 't1', prn: '72145002', studentName: 'Riya Kamble'),
    StudentModel(
        id: 's3',
        teacherId: 't1',
        prn: '72145003',
        studentName: 'Sumit Bhosale'),
  ];

  AttendanceSessionModel? session;
  final Map<String, String> records = {};
  final Map<String, String> sources = {};
  int startCalls = 0;
  int markCalls = 0;

  @override
  Future<AttendanceSessionModel> startAttendanceSession({
    required String classSubjectId,
    required DateTime date,
    int periodNumber = 1,
  }) async {
    startCalls++;
    session = AttendanceSessionModel(
      id: 'session-1',
      classSubjectId: classSubjectId,
      lectureDate: date,
      status: 'active',
    );
    for (final s in students) {
      records[s.id] = 'absent';
      sources[s.id] = 'default';
    }
    return session!;
  }

  @override
  Future<void> markStudentAttendance({
    required String sessionId,
    required String studentId,
    required String status,
    required String source,
  }) async {
    markCalls++;
    records[studentId] = status;
    sources[studentId] = source;
  }

  @override
  Future<void> completeSession(String sessionId) async {
    final current = session;
    if (current == null || current.id != sessionId) return;
    session = AttendanceSessionModel(
      id: current.id,
      classSubjectId: current.classSubjectId,
      lectureDate: current.lectureDate,
      periodNumber: current.periodNumber,
      startedAt: current.startedAt,
      endedAt: DateTime.now(),
      status: 'completed',
    );
  }

  @override
  Future<List<EnrollmentModel>> getEnrollments(String classSubjectId) async {
    return students
        .map((s) => EnrollmentModel(
              id: 'e${s.id}',
              classSubjectId: classSubjectId,
              studentId: s.id,
              enrolledFrom: DateTime(2026, 1, 1),
              student: s,
            ))
        .toList();
  }

  @override
  Future<List<AttendanceSessionModel>> getActiveSessions(String id) async {
    if (session == null || session!.status != 'active') return [];
    return [session!];
  }

  @override
  Future<List<AttendanceSessionModel>> getSessionsForDate({
    required String classSubjectId,
    required DateTime date,
  }) async =>
      session == null ? [] : [session!];

  @override
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSession(
      String sessionId) async {
    return records.entries
        .map((e) => AttendanceRecordModel(
              id: 'r${e.key}',
              sessionId: sessionId,
              studentId: e.key,
              status: e.value,
              source: sources[e.key] ?? 'default',
            ))
        .toList();
  }

  @override
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSessions(
          List<String> sessionIds) async =>
      [];

  @override
  Future<List<AttendanceSessionModel>> getCompletedSessions(String id) async =>
      [];

  @override
  Future<List<StudentModel>> getStudents(String teacherId) async => students;

  @override
  Future<void> bulkImportStudentsAndEnroll({
    required String teacherId,
    required String classSubjectId,
    required List<StudentModel> students,
  }) async {}

  @override
  Future<ClassSubjectModel> createClassSubject(ClassSubjectModel cs) async =>
      cs;

  @override
  Future<void> deleteClassSubject(String classSubjectId) async {}

  @override
  Future<void> deleteEnrollment(String enrollmentId) async {}

  @override
  Future<void> removeStudentFromClass({
    required String classSubjectId,
    required String studentId,
  }) async {}

  @override
  Future<ClassModel> createClass(ClassModel classModel) async => classModel;

  @override
  Future<List<ClassModel>> getClasses(String teacherId) async => [];

  @override
  Future<List<ClassSubjectModel>> getClassSubjects(String teacherId) async =>
      [];

  @override
  Future<List<SubjectModel>> getSubjects(String teacherId) async => [];

  @override
  Future<SubjectModel> createSubject(SubjectModel s) async => s;

  @override
  Future<void> updateClassSubject(ClassSubjectModel cs) async {}

  @override
  Future<List<AttendanceAlertModel>> getAlerts(String classSubjectId) async =>
      [];

  @override
  Future<void> markAttendanceBatch(List<AttendanceMark> marks) async {
    markCalls++;
    for (final mark in marks) {
      records[mark.studentId] = mark.status;
      sources[mark.studentId] = mark.source;
    }
  }

  @override
  Future<void> deleteClass(String classId) async {}

  @override
  Future<void> deleteSubject(String subjectId) async {}

  @override
  Future<List<AttendanceSessionModel>> getCompletedSessionsForTeacher(
          List<String> classSubjectIds) async =>
      [];

  @override
  Future<List<EnrollmentModel>> getEnrollmentsForTeacher(
          List<String> classSubjectIds) async =>
      [];

  @override
  Future<List<AttendanceSessionModel>> getSessionsForTeacherOnDate(
          List<String> classSubjectIds, DateTime date) async =>
      [];

  @override
  Future<List<AttendanceAlertModel>> getAlertsForTeacher(
          List<String> classSubjectIds) async =>
      [];

  @override
  Future<List<TeacherAvailability>> getTeacherAvailability(
          String teacherId) async =>
      [];

  @override
  Future<TeacherAvailability> addTeacherAvailability({
    required String teacherId,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
  }) async =>
      TeacherAvailability(
        id: 'slot-1',
        teacherId: teacherId,
        dayOfWeek: dayOfWeek,
        startTime: startTime,
        endTime: endTime,
      );

  @override
  Future<void> deleteTeacherAvailability(String availabilityId) async {}

  @override
  Future<StudentHistory> getStudentHistory(StudentModel student) async =>
      StudentHistory.empty(student);

  @override
  Future<void> logAttendanceEdit({
    required String teacherId,
    required String sessionId,
    required String studentId,
    required String? oldStatus,
    required String newStatus,
    required String? oldSource,
    required String newSource,
  }) async {}

  @override
  Future<List<AttendanceEditModel>> getAttendanceEditsForSession(
          String sessionId) async =>
      [];
}

/// Avoids touching SharedPreferences inside widget tests.
class _MemoryMarkStore implements MarkStore {
  List<AttendanceMark> marks = [];

  @override
  Future<List<AttendanceMark>> read() async => List.of(marks);

  @override
  Future<void> write(List<AttendanceMark> marks) async {
    this.marks = List.of(marks);
  }
}

/// Delivers a recognition result the way the Android platform does.
Future<void> speak(WidgetTester tester, String words,
    {bool isFinal = true}) async {
  final payload = jsonEncode({
    'alternates': [
      {'recognizedWords': words, 'confidence': 0.9, 'recognizedPhrases': null}
    ],
    'finalResult': isFinal,
    'resultType': isFinal ? 2 : 0,
  });
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    speechChannel.name,
    const StandardMethodCodec()
        .encodeMethodCall(MethodCall('textRecognition', payload)),
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDatabaseService fake;

  setUp(() {
    fake = FakeDatabaseService();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
      if (call.method == 'checkPermissionStatus') return 1;
      if (call.method == 'requestPermissions') {
        final perms = (call.arguments as List).cast<int>();
        return {for (final p in perms) p: 1};
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speechChannel, (call) async {
      switch (call.method) {
        case 'has_permission':
        case 'initialize':
        case 'listen':
          return true;
        case 'stop':
        case 'cancel':
          return null;
        case 'locales':
          return <dynamic>[];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speechChannel, null);
  });

  testWidgets(
      'attendance screen: pick class -> start -> speak -> marked present',
      (tester) async {
    // Use a phone-sized surface so the whole roster is laid out.
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cs = ClassSubjectModel(
      id: 'cs1',
      teacherId: 't1',
      classId: 'c1',
      subjectId: 's1',
      classDetails: ClassModel(
          id: 'c1',
          teacherId: 't1',
          className: 'SE E&TC A',
          academicYear: '2026-2027',
          semester: 'VI'),
      subjectDetails: SubjectModel(
          id: 's1',
          teacherId: 't1',
          subjectCode: 'EC999',
          subjectName: 'VLSI Design'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          classSubjectsProvider.overrideWith((ref) => [cs]),
          databaseServiceProvider.overrideWithValue(fake),
          // No batching delay in tests: the write lands on the next pump.
          attendanceWriterProvider.overrideWith(
            (ref) => AttendanceWriter(
              db: fake,
              store: _MemoryMarkStore(),
              debounce: Duration.zero,
            ),
          ),
        ],
        child: const MaterialApp(home: AttendanceScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    // 1. The class + subject is listed.
    expect(find.textContaining('VLSI Design'), findsOneWidget);

    // 2. Open it.
    await tester.tap(find.textContaining('VLSI Design'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // 3. The roster is shown, all absent, and the mic is hidden before Start.
    expect(find.text('Vedant Joshi'), findsOneWidget);
    expect(find.text('Riya Kamble'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Start'), findsOneWidget);
    expect(find.text('Tap Microphone to Speak'), findsNothing);

    // 4. Tap Start -> a session is created and everyone defaults to absent.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.startCalls, 1);
    expect(fake.records.length, 3);
    expect(fake.records.values.every((v) => v == 'absent'), isTrue);
    expect(find.text('Tap Microphone to Speak'), findsOneWidget);

    // 5. Tap the microphone -> the recogniser returns a phrase.
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // A PARTIAL result ("vedant") must never mark anybody.
    await speak(tester, 'vedant', isFinal: false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(fake.records['s1'], 'absent',
        reason: 'a partial fragment must not mark a student');

    // 6. "Vedant Joshi present" -> the student is marked present.
    await speak(tester, 'vedant josh present', isFinal: true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(fake.records['s1'], 'present');
    expect(fake.sources['s1'], 'voice');
    expect(fake.markCalls, greaterThan(0));
    expect(find.textContaining('Vedant Joshi PRESENT'), findsOneWidget);

    // 7. "Riya Kamble absent" -> marked absent, explicitly.
    await speak(tester, 'riya kamble absent', isFinal: true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(fake.records['s2'], 'absent');
    expect(fake.sources['s2'], 'voice');

    // 8. A name without the word "present" is NOT marked present.
    await speak(tester, 'sumit bhosale', isFinal: true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(fake.records['s3'], 'absent',
        reason: 'without "present" a student is only ever absent');

    // 9. The PRN's last 3 digits mark the right student.
    await speak(tester, '002 present', isFinal: true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(fake.records['s2'], 'present',
        reason: 'PRN 002 should be Riya Kamble');

    // 10. Tapping the chip toggles a student to absent (manual source).
    await tester.tap(find.widgetWithText(ChoiceChip, 'PRESENT').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(fake.records['s1'], 'absent');
    expect(fake.sources['s1'], 'manual');

    // Let the recogniser's listen window expire so no timer is pending.
    await tester.pump(const Duration(seconds: 13));
  });

  testWidgets(
      'interim-only results still mark students (web recogniser behaviour)',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cs = ClassSubjectModel(
      id: 'cs1',
      teacherId: 't1',
      classId: 'c1',
      subjectId: 's1',
      classDetails: ClassModel(
          id: 'c1',
          teacherId: 't1',
          className: 'SE E&TC A',
          academicYear: '2026-2027',
          semester: 'VI'),
      subjectDetails: SubjectModel(
          id: 's1',
          teacherId: 't1',
          subjectCode: 'EC999',
          subjectName: 'VLSI Design'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          classSubjectsProvider.overrideWith((ref) => [cs]),
          databaseServiceProvider.overrideWithValue(fake),
          attendanceWriterProvider.overrideWith(
            (ref) => AttendanceWriter(
              db: fake,
              store: _MemoryMarkStore(),
              debounce: Duration.zero,
            ),
          ),
        ],
        child: const MaterialApp(home: AttendanceScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.textContaining('VLSI Design'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The web recogniser never sends a final result. A settled interim
    // "name + present" must still mark the student.
    await speak(tester, 'vedant josh present', isFinal: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.records['s1'], 'present',
        reason: 'an interim complete instruction must mark present');
    expect(fake.sources['s1'], 'voice');

    // A bare fragment is still never treated as a complete instruction.
    await speak(tester, 'sumit', isFinal: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.records['s3'], 'absent');
    expect(fake.sources['s3'], 'default',
        reason: 'a bare interim name must not even set the source');

    // A cumulative interim transcript can hold more than one instruction.
    await speak(tester, 'vedant josh present riya kamble present',
        isFinal: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.records['s2'], 'present',
        reason: 'the new instruction in a cumulative transcript must apply');

    // PRN suffix works from an interim result too.
    await speak(tester, '003 present', isFinal: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.records['s3'], 'present',
        reason: 'PRN 003 should be Sumit Bhosale');

    // A final bare name still defaults to absent, as before.
    await speak(tester, 'sumit bhosale', isFinal: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.records['s3'], 'absent');
    expect(fake.sources['s3'], 'voice');

    // Let the recogniser's listen window expire so no timer is pending.
    await tester.pump(const Duration(seconds: 13));
  });

  testWidgets('finalized lecture is read-only and can start a new lecture',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cs = ClassSubjectModel(
      id: 'cs1',
      teacherId: 't1',
      classId: 'c1',
      subjectId: 's1',
      classDetails: ClassModel(
          id: 'c1',
          teacherId: 't1',
          className: 'SE E&TC A',
          academicYear: '2026-2027',
          semester: 'VI'),
      subjectDetails: SubjectModel(
          id: 's1',
          teacherId: 't1',
          subjectCode: 'EC999',
          subjectName: 'VLSI Design'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          classSubjectsProvider.overrideWith((ref) => [cs]),
          databaseServiceProvider.overrideWithValue(fake),
          attendanceWriterProvider.overrideWith(
            (ref) => AttendanceWriter(
              db: fake,
              store: _MemoryMarkStore(),
              debounce: Duration.zero,
            ),
          ),
        ],
        child: const MaterialApp(home: AttendanceScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.textContaining('VLSI Design'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Close the lecture through the controller: the review screen's finalize
    // button also writes/shares an Excel file, which is real disk I/O and is
    // covered by the service tests instead.
    final container = ProviderScope.containerOf(
        tester.element(find.textContaining('VLSI Design').first),
        listen: false);
    final controller =
        container.read(attendanceControllerProvider('cs1').notifier);
    expect(await controller.finalize(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Back on the lecture screen: it is closed, read-only, and offers a way
    // out instead of leaving the teacher stuck on a completed session.
    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('View Finalized Lecture'), findsOneWidget);
    expect(find.text('Review & Finalize Lecture'), findsNothing);
    expect(find.text('Tap Microphone to Speak'), findsNothing);

    // Tapping a student after finalization must not change anything.
    await tester.tap(find.widgetWithText(ChoiceChip, 'ABSENT').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(fake.records.values.every((v) => v == 'absent'), isTrue,
        reason: 'a finalized lecture must never accept new marks');

    // The closed lecture can still be reviewed, but not changed or finalized
    // a second time.
    await tester.tap(find.text('View Finalized Lecture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Finalized Attendance'), findsOneWidget);
    expect(find.text('FINALIZED'), findsOneWidget);
    expect(find.text('Finalize Lecture'), findsNothing);
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches.every((s) => s.onChanged == null), isTrue,
        reason: 'a finalized lecture is read-only');

    Navigator.of(tester.element(find.text('Finalized Attendance'))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // "New" resets the screen so the next period can be started.
    await tester.tap(find.text('New'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(ElevatedButton, 'Start'), findsOneWidget);
    expect(find.text('DONE'), findsNothing);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.startCalls, 2, reason: 'a new lecture starts a new session');
  });
}
