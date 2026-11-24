import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_attendance/models/attendance_record.dart';
import 'package:voice_attendance/models/attendance_session.dart';
import 'package:voice_attendance/models/class_model.dart';
import 'package:voice_attendance/models/class_subject.dart';
import 'package:voice_attendance/models/enrollment.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/models/subject.dart';
import 'package:voice_attendance/providers/analytics_provider.dart';
import 'package:voice_attendance/providers/classes_provider.dart';
import 'package:voice_attendance/providers/database_provider.dart';
import 'package:voice_attendance/services/database_service.dart';

void main() {
  group('analyticsProvider', () {
    late ProviderContainer container;

    setUp(() {
      final aarav = _student('s1', 'Aarav');
      final bina = _student('s2', 'Bina');
      final chitra = _student('s3', 'Chitra');
      final cs1 = _classSubject('cs1', threshold: 75);
      final cs2 = _classSubject('cs2', threshold: 75);

      final sessions = [
        _session('sess1', 'cs1', DateTime(2026, 11, 10)),
        _session('sess2', 'cs1', DateTime(2026, 11, 11)),
        _session('sess3', 'cs2', DateTime(2026, 11, 12)),
      ];
      final enrollments = [
        _enrollment('e1', 'cs1', aarav),
        _enrollment('e2', 'cs1', bina),
        _enrollment('e3', 'cs2', chitra),
      ];
      final records = [
        _record('r1', 'sess1', 's1', 'present'),
        _record('r2', 'sess1', 's2', 'present'),
        _record('r3', 'sess2', 's1', 'present'),
        _record('r4', 'sess2', 's2', 'absent'),
        _record('r5', 'sess3', 's3', 'present'),
      ];

      container = ProviderContainer(
        overrides: [
          classSubjectsProvider.overrideWith((ref) => [cs1, cs2]),
          databaseServiceProvider.overrideWithValue(
            FakeAnalyticsDb(
              sessions: sessions,
              enrollments: enrollments,
              records: records,
            ),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('builds teacher-wide analytics from the shared data loader', () async {
      final snapshot = await container
          .read(analyticsProvider(analyticsAllClassesScope).future);

      expect(snapshot.totalStudents, 3);
      expect(snapshot.totalLectures, 3);
      expect(snapshot.totalPresent, 4);
      expect(snapshot.totalAbsent, 1);
      expect(snapshot.overallPercentage, 80);
      expect(snapshot.studentsBelowThreshold, 1);
      expect(snapshot.classComparison.length, 2);
      expect(snapshot.trend.length, 3);
    });

    test('filters analytics to one class + subject', () async {
      final snapshot = await container.read(analyticsProvider('cs1').future);

      expect(snapshot.totalStudents, 2);
      expect(snapshot.totalLectures, 2);
      expect(snapshot.totalPresent, 3);
      expect(snapshot.totalEligible, 4);
      expect(snapshot.overallPercentage, 75);
      expect(snapshot.classComparison.length, 1);
      expect(snapshot.classComparison.single.classSubject.id, 'cs1');
      expect(snapshot.needsAttention.single.student.id, 's2');
    });

    test('returns an empty snapshot for a scope with no data', () async {
      final snapshot =
          await container.read(analyticsProvider('missing').future);

      expect(snapshot.totalStudents, 0);
      expect(snapshot.totalLectures, 0);
      expect(snapshot.hasAttendance, isFalse);
      expect(snapshot.classComparison, isEmpty);
    });
  });
}

class FakeAnalyticsDb implements DatabaseService {
  final List<AttendanceSessionModel> sessions;
  final List<EnrollmentModel> enrollments;
  final List<AttendanceRecordModel> records;

  FakeAnalyticsDb({
    required this.sessions,
    required this.enrollments,
    required this.records,
  });

  @override
  Future<List<AttendanceSessionModel>> getCompletedSessionsForTeacher(
    List<String> classSubjectIds,
  ) async =>
      sessions
          .where((session) => classSubjectIds.contains(session.classSubjectId))
          .toList();

  @override
  Future<List<EnrollmentModel>> getEnrollmentsForTeacher(
    List<String> classSubjectIds,
  ) async =>
      enrollments
          .where((enrollment) =>
              classSubjectIds.contains(enrollment.classSubjectId))
          .toList();

  @override
  Future<List<AttendanceRecordModel>> getAttendanceRecordsForSessions(
    List<String> sessionIds,
  ) async =>
      records.where((record) => sessionIds.contains(record.sessionId)).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

StudentModel _student(String id, String name) => StudentModel(
      id: id,
      teacherId: 't1',
      prn: id,
      studentName: name,
      email: '$id@example.edu',
    );

ClassSubjectModel _classSubject(String id, {required double threshold}) =>
    ClassSubjectModel(
      id: id,
      teacherId: 't1',
      classId: 'class-$id',
      subjectId: 'subject-$id',
      thresholdPercent: threshold,
      classDetails: ClassModel(
        id: 'class-$id',
        teacherId: 't1',
        className: 'BE E&TC $id',
        academicYear: '2026-27',
        semester: 'VIII',
      ),
      subjectDetails: SubjectModel(
        id: 'subject-$id',
        teacherId: 't1',
        subjectCode: 'EC801',
        subjectName: 'Digital Communication',
      ),
    );

AttendanceSessionModel _session(
  String id,
  String classSubjectId,
  DateTime date,
) =>
    AttendanceSessionModel(
      id: id,
      classSubjectId: classSubjectId,
      lectureDate: date,
      status: 'completed',
    );

EnrollmentModel _enrollment(
  String id,
  String classSubjectId,
  StudentModel student,
) =>
    EnrollmentModel(
      id: id,
      classSubjectId: classSubjectId,
      studentId: student.id,
      enrolledFrom: DateTime(2026, 11, 1),
      student: student,
    );

AttendanceRecordModel _record(
  String id,
  String sessionId,
  String studentId,
  String status,
) =>
    AttendanceRecordModel(
      id: id,
      sessionId: sessionId,
      studentId: studentId,
      status: status,
      source: 'voice',
    );
