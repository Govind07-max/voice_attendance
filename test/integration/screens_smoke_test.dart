import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voice_attendance/app/configuration_screen.dart';
import 'package:voice_attendance/models/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/features/alerts/alerts_screen.dart';
import 'package:voice_attendance/features/attendance/attendance_screen.dart';
import 'package:voice_attendance/features/attendance/review_attendance_screen.dart';
import 'package:voice_attendance/features/attendance/widgets/duplicate_match_dialog.dart';
import 'package:voice_attendance/features/auth/login_screen.dart';
import 'package:voice_attendance/features/classes/class_subject_setup_screen.dart';
import 'package:voice_attendance/features/classes/classes_screen.dart';
import 'package:voice_attendance/features/dashboard/dashboard_screen.dart';
import 'package:voice_attendance/features/profile/profile_screen.dart';
import 'package:voice_attendance/features/reports/reports_screen.dart';
import 'package:voice_attendance/features/students/student_history_screen.dart';
import 'package:voice_attendance/features/students/student_import_screen.dart';
import 'package:voice_attendance/models/analytics.dart' as analytics;
import 'package:voice_attendance/models/attendance_alert.dart';
import 'package:voice_attendance/models/attendance_edit.dart';
import 'package:voice_attendance/models/attendance_mark.dart';
import 'package:voice_attendance/models/attendance_record.dart';
import 'package:voice_attendance/models/attendance_session.dart';
import 'package:voice_attendance/models/class_model.dart';
import 'package:voice_attendance/models/class_subject.dart';
import 'package:voice_attendance/models/enrollment.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/models/student_history.dart';
import 'package:voice_attendance/models/subject.dart';
import 'package:voice_attendance/providers/attendance_stats_provider.dart';
import 'package:voice_attendance/providers/analytics_provider.dart';
import 'package:voice_attendance/providers/auth_provider.dart';
import 'package:voice_attendance/providers/classes_provider.dart';
import 'package:voice_attendance/providers/database_provider.dart';
import 'package:voice_attendance/services/auth_service.dart';
import 'package:voice_attendance/services/database_service.dart';

/// In-memory database so every screen can be rendered without a network.
class FakeDb implements DatabaseService {
  ClassSubjectModel? lastUpdatedClassSubject;
  final Set<String> removedStudentIds = {};
  final List<StudentModel> importedStudents = [];

  final List<StudentModel> students = [
    StudentModel(
        id: 's1', teacherId: 't1', prn: '501', studentName: 'Vedant Joshi'),
    StudentModel(
        id: 's2', teacherId: 't1', prn: '502', studentName: 'Riya Kamble'),
    StudentModel(
        id: 's3', teacherId: 't1', prn: '503', studentName: 'Sumit Bhosale'),
  ];

  @override
  Future<List<EnrollmentModel>> getEnrollments(String id) async => students
      .where((student) => !removedStudentIds.contains(student.id))
      .map((s) => EnrollmentModel(
            id: 'e${s.id}',
            classSubjectId: id,
            studentId: s.id,
            enrolledFrom: DateTime(2026, 1, 1),
            student: s,
          ))
      .toList();

  @override
  Future<List<StudentModel>> getStudents(String t) async => students;

  @override
  Future<List<ClassModel>> getClasses(String t) async => [];

  @override
  Future<List<ClassSubjectModel>> getClassSubjects(String t) async => [];

  @override
  Future<List<SubjectModel>> getSubjects(String t) async => [];

  @override
  Future<List<AttendanceSessionModel>> getCompletedSessions(String id) async =>
      [
        AttendanceSessionModel(
            id: 'sess1',
            classSubjectId: id,
            lectureDate: DateTime(2026, 10, 19)),
      ];

  @override
  Future<List<AttendanceSessionModel>> getActiveSessions(String id) async => [];

  @override
  Future<List<AttendanceSessionModel>> getSessionsForDate({
    required String classSubjectId,
    required DateTime date,
  }) async =>
      [];

  @override
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSessions(
          List<String> ids) async =>
      [
        AttendanceRecordModel(
            id: 'r1',
            sessionId: 'sess1',
            studentId: 's1',
            status: 'present',
            source: 'voice'),
        AttendanceRecordModel(
            id: 'r2',
            sessionId: 'sess1',
            studentId: 's2',
            status: 'absent',
            source: 'default'),
      ];

  @override
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSession(
          String id) async =>
      [];

  @override
  Future<List<AttendanceAlertModel>> getAlerts(String id) async => [];

  @override
  Future<AttendanceSessionModel> startAttendanceSession({
    required String classSubjectId,
    required DateTime date,
    int periodNumber = 1,
  }) async =>
      AttendanceSessionModel(
          id: 'sess-live',
          classSubjectId: classSubjectId,
          lectureDate: date,
          status: 'active');

  @override
  Future<void> markStudentAttendance({
    required String sessionId,
    required String studentId,
    required String status,
    required String source,
  }) async {}

  @override
  Future<void> completeSession(String id) async {}

  @override
  Future<void> bulkImportStudentsAndEnroll({
    required String teacherId,
    required String classSubjectId,
    required List<StudentModel> students,
  }) async {
    importedStudents.addAll(students);
    // Mirror the production upsert: re-importing a removed PRN reactivates it.
    final importedPrns = students.map((student) => student.prn).toSet();
    removedStudentIds.removeWhere((id) {
      final existing = studentsForId(id);
      return existing != null && importedPrns.contains(existing.prn);
    });
  }

  StudentModel? studentsForId(String id) {
    for (final student in students) {
      if (student.id == id) return student;
    }
    return null;
  }

  @override
  Future<ClassSubjectModel> createClassSubject(ClassSubjectModel cs) async =>
      cs;

  @override
  Future<void> updateClassSubject(ClassSubjectModel cs) async {
    lastUpdatedClassSubject = cs;
  }

  @override
  Future<void> deleteClassSubject(String id) async {}

  @override
  Future<void> deleteEnrollment(String id) async {}

  @override
  Future<void> removeStudentFromClass({
    required String classSubjectId,
    required String studentId,
  }) async {
    removedStudentIds.add(studentId);
  }

  @override
  Future<ClassModel> createClass(ClassModel c) async => c;

  @override
  Future<SubjectModel> createSubject(SubjectModel s) async => s;

  @override
  Future<void> deleteClass(String classId) async {}

  @override
  Future<void> deleteSubject(String subjectId) async {}

  @override
  Future<void> markAttendanceBatch(List<AttendanceMark> marks) async {}

  @override
  Future<List<AttendanceSessionModel>> getCompletedSessionsForTeacher(
          List<String> classSubjectIds) async =>
      [
        AttendanceSessionModel(
          id: 'sess1',
          classSubjectId:
              classSubjectIds.isEmpty ? 'cs1' : classSubjectIds.first,
          lectureDate: DateTime(2026, 10, 19),
          status: 'completed',
        ),
      ];

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
      [
        TeacherAvailability(
          id: 'slot-1',
          teacherId: teacherId,
          dayOfWeek: 1,
          startTime: '10:00:00',
          endTime: '11:00:00',
        ),
      ];

  @override
  Future<TeacherAvailability> addTeacherAvailability({
    required String teacherId,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
  }) async =>
      TeacherAvailability(
        id: 'slot-2',
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

class FakeAuth implements AuthService {
  @override
  User? get currentUser => null;
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
  @override
  Future<void> signOut() async {}
  @override
  Future<AuthResponse> signIn(
          {required String email, required String password}) async =>
      throw UnimplementedError();
  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async =>
      throw UnimplementedError();
  @override
  Future<TeacherProfile?> fetchProfile() async => null;
  @override
  Future<TeacherProfile> ensureProfile(
          {required String fullName, required String email}) async =>
      throw UnimplementedError();
  @override
  Future<void> updateProfile(TeacherProfile profile) async {}
}

ClassSubjectModel sampleCs(
  String id, {
  bool alertEnabled = true,
  String alertTime = '09:00:00',
  double thresholdPercent = 75,
}) =>
    ClassSubjectModel(
      id: id,
      teacherId: 't1',
      classId: 'c1',
      subjectId: 's1',
      alertEnabled: alertEnabled,
      alertTime: alertTime,
      thresholdPercent: thresholdPercent,
      classDetails: ClassModel(
          id: 'c1',
          teacherId: 't1',
          className: 'BE E&TC A',
          academicYear: '2026-2027',
          semester: 'VIII'),
      subjectDetails: SubjectModel(
          id: 's1',
          teacherId: 't1',
          subjectCode: 'EC801',
          subjectName: 'Digital Communication'),
    );

analytics.TeacherAnalyticsSnapshot sampleAnalytics() {
  final cs = sampleCs('cs1');
  final students = FakeDb().students;
  return analytics.TeacherAnalyticsSnapshot(
    totalStudents: 12,
    totalLectures: 5,
    totalPresent: 41,
    totalAbsent: 9,
    totalEligible: 50,
    overallPercentage: 82,
    studentsBelowThreshold: 2,
    healthBands: const [
      analytics.AnalyticsBucket(label: 'On track', count: 8, percentage: 66.7),
      analytics.AnalyticsBucket(label: 'Near risk', count: 2, percentage: 16.7),
      analytics.AnalyticsBucket(label: 'Critical', count: 2, percentage: 16.7),
    ],
    classComparison: [
      analytics.ClassAttendancePoint(
        classSubject: cs,
        averagePercentage: 82,
        studentCount: 12,
        sessionCount: 5,
        studentsBelowThreshold: 2,
      ),
    ],
    trend: [
      analytics.AttendanceTrendPoint(
          date: DateTime(2026, 11, 10), presentCount: 8, eligibleCount: 10),
      analytics.AttendanceTrendPoint(
          date: DateTime(2026, 11, 17), presentCount: 9, eligibleCount: 10),
    ],
    topStudents: [
      analytics.StudentPerformance(
        student: students.first,
        classSubject: cs,
        percentage: 92,
        attended: 11,
        conducted: 12,
      ),
    ],
    needsAttention: [
      analytics.StudentPerformance(
        student: students[1],
        classSubject: cs,
        percentage: 50,
        attended: 5,
        conducted: 10,
      ),
    ],
  );
}

void main() {
  /// Small phone viewport so any layout overflow shows up.
  setUp(() {});

  Widget wrap(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(FakeAuth()),
        databaseServiceProvider.overrideWithValue(FakeDb()),
        classSubjectsProvider.overrideWith((ref) => [sampleCs('cs1')]),
        classesProvider.overrideWith((ref) => []),
        subjectsProvider.overrideWith((ref) => []),
        teacherCountsProvider.overrideWith(
            (ref) async => {'classes': 2, 'classSubjects': 2, 'students': 12}),
        rosterProvider.overrideWith((ref, arg) async => FakeDb().students),
        classSubjectStatsProvider.overrideWith((ref) async => [
              ClassSubjectStats(
                classSubject: sampleCs('cs1'),
                sessions: 3,
                students: 8,
                averagePercentage: 84.2,
              ),
            ]),
        lowAttendanceProvider.overrideWith((ref) async => [
              StudentAttendanceStat(
                student: FakeDb().students.first,
                classSubject: sampleCs('cs1'),
                attended: 1,
                conducted: 2,
                percentage: 50,
              ),
            ]),
        ...overrides,
      ],
      child: MaterialApp(home: child),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('dashboard renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const DashboardHomeScreen()));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Your Classes'), findsOneWidget);
  });

  testWidgets('classes screen renders and the add dialog opens',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const ClassesScreen()));
    await settle(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await settle(tester);
    expect(find.text('Add New Class & Subject'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports screen renders and the dropdown works', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const ReportsScreen()));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Class + Subject'), findsOneWidget);
  });

  testWidgets('alerts screen renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const AlertsScreen()));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile screen renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const ProfileScreen()));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('student import screen renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = (e) => errors.add(e);
    await tester
        .pumpWidget(wrap(StudentImportScreen(classSubject: sampleCs('cs1'))));
    await settle(tester);
    FlutterError.onError = old;
    for (final e in errors) {
      // ignore: avoid_print
      print('IMPORT ERROR: ${e.exceptionAsString()}');
    }
    expect(errors, isEmpty);
    expect(find.text('Upload Student Roster Spreadsheet'), findsOneWidget);
  });

  testWidgets('teacher can manually add a student to the roster',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = FakeDb();
    await tester.pumpWidget(wrap(
      StudentImportScreen(classSubject: sampleCs('cs1')),
      overrides: [
        teacherIdProvider.overrideWithValue('t1'),
        databaseServiceProvider.overrideWithValue(db),
        rosterProvider.overrideWith((ref, arg) async => db.students
            .where((student) => !db.removedStudentIds.contains(student.id))
            .toList()),
      ],
    ));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await settle(tester);
    expect(find.text('Add Student Manually'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '601');
    await tester.enterText(fields.at(1), 'New Student');
    await tester.enterText(fields.at(2), 'new@example.edu');
    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(db.importedStudents, hasLength(1));
    expect(db.importedStudents.single.prn, '601');
    expect(db.importedStudents.single.studentName, 'New Student');
    expect(db.importedStudents.single.email, 'new@example.edu');
  });

  testWidgets('teacher can remove a student from this class only',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = FakeDb();
    await tester.pumpWidget(wrap(
      StudentImportScreen(classSubject: sampleCs('cs1')),
      overrides: [
        teacherIdProvider.overrideWithValue('t1'),
        databaseServiceProvider.overrideWithValue(db),
        rosterProvider.overrideWith((ref, arg) async => db.students
            .where((student) => !db.removedStudentIds.contains(student.id))
            .toList()),
      ],
    ));
    await settle(tester);
    expect(find.text('Vedant Joshi'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await settle(tester);
    expect(find.text('Remove Student?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await settle(tester);

    expect(db.removedStudentIds, contains('s1'));
    expect(find.text('Vedant Joshi'), findsNothing);
  });

  testWidgets('manual add validates PRN, name and email', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = FakeDb();
    await tester.pumpWidget(wrap(
      StudentImportScreen(classSubject: sampleCs('cs1')),
      overrides: [
        teacherIdProvider.overrideWithValue('t1'),
        databaseServiceProvider.overrideWithValue(db),
        rosterProvider.overrideWith((ref, arg) async => db.students
            .where((student) => !db.removedStudentIds.contains(student.id))
            .toList()),
      ],
    ));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await settle(tester);
    final fields = find.byType(TextField);

    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('PRN and student name are required.'), findsOneWidget);
    expect(db.importedStudents, isEmpty);

    await tester.enterText(fields.at(0), '701');
    await tester.enterText(fields.at(1), 'Test Student');
    await tester.enterText(fields.at(2), 'not-an-email');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('Enter a valid email address, or leave it blank.'),
        findsOneWidget);
    expect(db.importedStudents, isEmpty);

    await tester.enterText(fields.at(2), 'govindsr051@gmail.com');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(db.importedStudents, hasLength(1));
    expect(db.importedStudents.single.email, 'govindsr051@gmail.com');
  });

  testWidgets('cancelling removal keeps the student enrolled', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = FakeDb();
    await tester.pumpWidget(wrap(
      StudentImportScreen(classSubject: sampleCs('cs1')),
      overrides: [
        teacherIdProvider.overrideWithValue('t1'),
        databaseServiceProvider.overrideWithValue(db),
        rosterProvider.overrideWith((ref, arg) async => db.students
            .where((student) => !db.removedStudentIds.contains(student.id))
            .toList()),
      ],
    ));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(db.removedStudentIds, isEmpty);
    expect(find.text('Vedant Joshi'), findsOneWidget);
  });

  testWidgets('re-adding a removed student reactivates the enrollment',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = FakeDb();
    await tester.pumpWidget(wrap(
      StudentImportScreen(classSubject: sampleCs('cs1')),
      overrides: [
        teacherIdProvider.overrideWithValue('t1'),
        databaseServiceProvider.overrideWithValue(db),
        rosterProvider.overrideWith((ref, arg) async => db.students
            .where((student) => !db.removedStudentIds.contains(student.id))
            .toList()),
      ],
    ));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await settle(tester);
    await tester.tap(find.text('Remove'));
    await settle(tester);
    expect(db.removedStudentIds, contains('s1'));
    expect(find.text('Vedant Joshi'), findsNothing);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await settle(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '501');
    await tester.enterText(fields.at(1), 'Vedant Joshi');
    await tester.enterText(fields.at(2), 'govindsr051@gmail.com');
    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(db.removedStudentIds, isNot(contains('s1')));
    expect(find.text('Vedant Joshi'), findsOneWidget);
  });

  testWidgets('class + subject setup screen renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
        wrap(ClassSubjectSetupScreen(classSubject: sampleCs('cs1'))));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Google Form URL'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Send Alerts At'), 300,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
    expect(find.text('Send Alerts At'), findsOneWidget);
    expect(find.text('Alert Schedule Frequency'), findsOneWidget);
    expect(find.text('Anti-Spam Reminder Interval'), findsOneWidget);
  });

  testWidgets('review attendance screen renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(ReviewAttendanceScreen(
        classSubjectId: 'cs1', classSubject: sampleCs('cs1'))));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attendance screen picker renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const AttendanceScreen()));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Digital Communication'), findsOneWidget);
  });

  testWidgets('the app shell (all tabs) renders without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const DashboardShell()));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every dock tab opens without an exception', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const DashboardShell()));
    await settle(tester);

    const tabs = <String, IconData>{
      'Classes': Icons.class_outlined,
      'Voice': Icons.mic_rounded,
      'Reports': Icons.bar_chart_rounded,
      'Alerts': Icons.warning_amber_rounded,
      'Home': Icons.home_rounded,
    };

    for (final entry in tabs.entries) {
      await tester.tap(find.byIcon(entry.value).last);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'tab "${entry.key}"');
    }
  });

  testWidgets('alerts email-history tab renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const AlertsScreen()));
    await settle(tester);

    await tester.tap(find.text('Email History'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('No alert emails yet'), findsOneWidget);
  });

  testWidgets('profile screen shows the meeting-slot settings', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const ProfileScreen()));
    await settle(tester);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Weekly Meeting Slots'), 300,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
    expect(find.text('Weekly Meeting Slots'), findsOneWidget);
    expect(find.textContaining('No slots yet'), findsOneWidget);
  });

  testWidgets('reports screen opens a report with both export buttons',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const ReportsScreen()));
    await settle(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle(tester);
    await tester.tap(find.textContaining('Digital Communication').last);
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Export Excel'), findsOneWidget);
    expect(find.text('Export PDF'), findsOneWidget);
  });

  testWidgets('reports analytics view renders charts and student lists',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(
      const ReportsScreen(),
      overrides: [
        analyticsProvider.overrideWith((ref, scope) async => sampleAnalytics()),
      ],
    ));
    await settle(tester);

    await tester.tap(find.text('Analytics'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Present vs absent'), findsOneWidget);
    expect(find.text('Attendance health'), findsOneWidget);
    expect(find.text('Class comparison'), findsOneWidget);
    expect(find.text('Attendance trend'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Top performers'), findsOneWidget);
    expect(find.text('82.0%'), findsWidgets);

    // The analytics scope filter must switch without leaving the Reports tab.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle(tester);
    await tester.tap(find.textContaining('Digital Communication').last);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('BE E&TC A'), findsWidgets);
    expect(find.text('Attendance trend'), findsOneWidget);
  });

  testWidgets('login screen renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const LoginScreen()));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Smart Attendance'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('backend configuration screen renders without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(
      const ConfigurationScreen(reason: 'SUPABASE_URL is missing or invalid.'),
    ));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Backend not configured'), findsOneWidget);
    expect(find.text('Fix it in 3 steps:'), findsOneWidget);
  });

  testWidgets('student history screen renders without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final student = FakeDb().students.first;
    final history = StudentHistory(
      student: student,
      summaries: [
        StudentSubjectSummary(
          classSubject: sampleCs('cs1'),
          attended: 7,
          conducted: 10,
          percentage: 70,
        ),
      ],
      entries: [
        StudentHistoryEntry(
          session: AttendanceSessionModel(
            id: 'sess1',
            classSubjectId: 'cs1',
            lectureDate: DateTime(2026, 10, 19),
            status: 'completed',
          ),
          status: 'present',
          source: 'voice',
          classSubject: sampleCs('cs1'),
        ),
      ],
    );

    await tester.pumpWidget(wrap(
      StudentHistoryScreen(student: student),
      overrides: [
        studentHistoryProvider.overrideWith((ref, arg) async => history),
      ],
    ));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Student Attendance'), findsOneWidget);
    expect(find.text('Subject-wise Attendance'), findsOneWidget);
    expect(find.text('70.0%'), findsWidgets);
  });

  testWidgets('duplicate student match dialog renders and lists candidates',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => DuplicateMatchDialog(
                  spokenName: 'Aarav Sharma',
                  candidateStudents: FakeDb().students.take(2).toList(),
                  onSelected: (_) {},
                ),
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    ));
    await settle(tester);

    await tester.tap(find.text('Open Dialog'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Multiple Students Found'), findsOneWidget);
    expect(find.text('Vedant Joshi'), findsOneWidget);
    expect(find.text('Riya Kamble'), findsOneWidget);
  });

  testWidgets('class setup saves the new alert schedule settings',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = FakeDb();
    final cs = sampleCs('cs1', alertTime: '14:45:00');

    await tester.pumpWidget(wrap(
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ClassSubjectSetupScreen(classSubject: cs),
                ),
              ),
              child: const Text('Open Setup'),
            ),
          ),
        ),
      ),
      overrides: [databaseServiceProvider.overrideWithValue(db)],
    ));
    await settle(tester);

    await tester.tap(find.text('Open Setup'));
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Alert Schedule Frequency'), 300,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);

    await tester.tap(find.text('Weekly'));
    await settle(tester);
    await tester.tap(find.text('Bi-Weekly').last);
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Repeat Interval'), 300,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(find.text('Every 14 days').last);
    await settle(tester);
    await tester.tap(find.text('Every 21 days').last);
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Save Settings'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save Settings'));
    await settle(tester);

    expect(db.lastUpdatedClassSubject, isNotNull);
    expect(db.lastUpdatedClassSubject!.alertFrequency, 'biweekly');
    expect(db.lastUpdatedClassSubject!.intervalDays, 21);
    expect(db.lastUpdatedClassSubject!.alertTime, '14:45:00');
  });

  testWidgets('at-risk cards warn about disabled alerts and missing email',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final missingEmail = StudentModel(
      id: 'missing-email',
      teacherId: 't1',
      prn: '601',
      studentName: 'No Email Student',
    );
    final validEmail = StudentModel(
      id: 'valid-email',
      teacherId: 't1',
      prn: '602',
      studentName: 'Valid Email Student',
      email: 'valid@example.edu',
    );

    await tester.pumpWidget(wrap(
      const AlertsScreen(),
      overrides: [
        lowAttendanceProvider.overrideWith((ref) async => [
              StudentAttendanceStat(
                student: missingEmail,
                classSubject: sampleCs('cs1'),
                attended: 1,
                conducted: 2,
                percentage: 50,
              ),
              StudentAttendanceStat(
                student: validEmail,
                classSubject: sampleCs('cs2', alertEnabled: false),
                attended: 1,
                conducted: 2,
                percentage: 50,
              ),
            ]),
      ],
    ));
    await settle(tester);

    expect(find.textContaining('No email on file'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Email alerts are disabled for this class + subject.'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Email alerts are disabled for this class + subject.'),
        findsOneWidget);
  });

  testWidgets(
      'email history shows failed delivery, error and configured threshold',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cs = sampleCs('cs1', thresholdPercent: 80);
    final alert = AttendanceAlertModel(
      id: 'a1',
      classSubjectId: 'cs1',
      studentId: 's1',
      attendancePercent: 72,
      attendedCount: 7,
      conductedCount: 10,
      alertType: 'initial',
      sentAt: DateTime(2026, 11, 18),
      status: 'failed',
      errorMessage: 'Mail quota exceeded',
      student: FakeDb().students.first,
    );

    await tester.pumpWidget(wrap(
      const AlertsScreen(),
      overrides: [
        alertHistoryProvider.overrideWith((ref) async => [
              AlertHistoryItem(alert: alert, classSubject: cs),
            ]),
      ],
    ));
    await settle(tester);

    await tester.tap(find.text('Email History'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('72.0%'), findsOneWidget);
    expect(find.text('7/10 lectures • below 80%'), findsOneWidget);
    expect(find.textContaining('Attempted'), findsOneWidget);
    expect(find.text('Mail quota exceeded'), findsOneWidget);
  });

  // The phone may have "larger text" enabled — that is the most common
  // reason for the overflow the teacher saw.
  group('with a large system font scale', () {
    Widget scaled(Widget child) => MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: child,
        );

    for (final entry in <String, Widget>{
      'dashboard': const DashboardHomeScreen(),
      'classes': const ClassesScreen(),
      'attendance': const AttendanceScreen(),
      'reports': const ReportsScreen(),
      'alerts': const AlertsScreen(),
      'profile': const ProfileScreen(),
    }.entries) {
      testWidgets('${entry.key} survives a 1.4x font scale', (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final errors = <FlutterErrorDetails>[];
        final old = FlutterError.onError;
        FlutterError.onError = (e) => errors.add(e);
        await tester.pumpWidget(wrap(scaled(entry.value)));
        await settle(tester);
        FlutterError.onError = old;
        for (final e in errors) {
          // ignore: avoid_print
          print(
              'SCALE ERROR [${entry.key}]: ${e.exceptionAsString()} | ${e.context}');
        }
        expect(errors, isEmpty,
            reason: '${entry.key} overflowed at a 1.4x font scale');
      });
    }

    testWidgets('class setup survives a 1.4x font scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = (e) => errors.add(e);
      await tester.pumpWidget(
          wrap(scaled(ClassSubjectSetupScreen(classSubject: sampleCs('cs1')))));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Save Settings'), 300,
          scrollable: find.byType(Scrollable).first);
      await settle(tester);
      FlutterError.onError = old;
      for (final e in errors) {
        // ignore: avoid_print
        print(
            'SCALE ERROR [class setup]: ${e.exceptionAsString()} | ${e.context}');
      }
      expect(errors, isEmpty,
          reason: 'class setup overflowed at a 1.4x font scale');
    });

    testWidgets('reports analytics survives a 1.4x font scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = (e) => errors.add(e);
      await tester.pumpWidget(wrap(
        scaled(const ReportsScreen()),
        overrides: [
          analyticsProvider
              .overrideWith((ref, scope) async => sampleAnalytics()),
        ],
      ));
      await settle(tester);
      await tester.tap(find.text('Analytics'));
      await settle(tester);
      FlutterError.onError = old;
      for (final e in errors) {
        // ignore: avoid_print
        print(
            'SCALE ERROR [analytics]: ${e.exceptionAsString()} | ${e.context}');
      }
      expect(errors, isEmpty,
          reason: 'analytics overflowed at a 1.4x font scale');
    });
  });
}
