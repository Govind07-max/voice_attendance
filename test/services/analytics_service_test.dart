import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/models/attendance_record.dart';
import 'package:voice_attendance/models/attendance_session.dart';
import 'package:voice_attendance/models/class_model.dart';
import 'package:voice_attendance/models/class_subject.dart';
import 'package:voice_attendance/models/enrollment.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/models/subject.dart';
import 'package:voice_attendance/services/analytics_service.dart';
import 'package:voice_attendance/services/report_service.dart';

const _service = AnalyticsService();

void main() {
  group('AnalyticsService', () {
    test('returns an empty snapshot when there are no reports', () {
      final snapshot = _service.build(reports: const []);

      expect(snapshot.totalStudents, 0);
      expect(snapshot.totalLectures, 0);
      expect(snapshot.hasLectures, isFalse);
      expect(snapshot.hasAttendance, isFalse);
    });

    test('computes KPIs, health bands, trends, and rankings', () {
      final aarav = _student('s1', 'Aarav');
      final bina = _student('s2', 'Bina');
      final chitra = _student('s3', 'Chitra');

      final cs1 = _classSubject('cs1', threshold: 75);
      final cs2 = _classSubject('cs2', threshold: 60);

      final s1 = _session('sess1', 'cs1', DateTime(2026, 11, 10));
      final s2 = _session('sess2', 'cs1', DateTime(2026, 11, 11));
      final s3 = _session('sess3', 'cs2', DateTime(2026, 11, 10));

      final enrollments1 = [
        _enrollment('e1', 'cs1', aarav),
        _enrollment('e2', 'cs1', bina),
      ];
      final enrollments2 = [_enrollment('e3', 'cs2', chitra)];

      final records = [
        _record('r1', 'sess1', 's1', 'present'),
        _record('r2', 'sess1', 's2', 'present'),
        _record('r3', 'sess2', 's1', 'present'),
        _record('r4', 'sess2', 's2', 'absent'),
        _record('r5', 'sess3', 's3', 'present'),
      ];

      final generator = DefaultReportGenerator();
      final reports = [
        generator.generateReport(
          classSubject: cs1,
          sessions: [s1, s2],
          enrollments: enrollments1,
          allRecords: records,
        ),
        generator.generateReport(
          classSubject: cs2,
          sessions: [s3],
          enrollments: enrollments2,
          allRecords: records,
        ),
      ];

      final snapshot = _service.build(reports: reports);

      expect(snapshot.totalStudents, 3);
      expect(snapshot.totalLectures, 3);
      expect(snapshot.totalPresent, 4);
      expect(snapshot.totalAbsent, 1);
      expect(snapshot.totalEligible, 5);
      expect(snapshot.overallPercentage, 80);
      expect(snapshot.studentsBelowThreshold, 1);
      expect(snapshot.hasAttendance, isTrue);

      final onTrack = snapshot.healthBands
          .firstWhere((bucket) => bucket.label == 'On track');
      final nearRisk = snapshot.healthBands
          .firstWhere((bucket) => bucket.label == 'Near risk');
      final critical = snapshot.healthBands
          .firstWhere((bucket) => bucket.label == 'Critical');
      expect(onTrack.count, 2);
      expect(nearRisk.count, 0);
      expect(critical.count, 1);
      expect(onTrack.percentage, 66.7);
      expect(critical.percentage, 33.3);

      expect(snapshot.classComparison.length, 2);
      expect(snapshot.classComparison.first.classSubject.id, 'cs1');
      expect(snapshot.classComparison.first.averagePercentage, 75);
      expect(snapshot.classComparison.first.studentsBelowThreshold, 1);
      expect(snapshot.classComparison.last.averagePercentage, 100);

      expect(snapshot.trend.length, 2);
      expect(snapshot.trend.first.percentage, 100);
      expect(snapshot.trend.last.percentage, 50);

      expect(snapshot.topStudents.length, 3);
      expect(snapshot.topStudents.first.percentage, 100);
      expect(snapshot.needsAttention.single.student.id, 's2');
      expect(snapshot.needsAttention.single.percentage, 50);
    });

    test('ignores students with no eligible lectures in percentages', () {
      final student = _student('s1', 'New Student');
      final cs = _classSubject('cs1');
      final session = _session('sess1', 'cs1', DateTime(2026, 11, 1));
      final enrollment = EnrollmentModel(
        id: 'e1',
        classSubjectId: 'cs1',
        studentId: student.id,
        enrolledFrom: DateTime(2026, 11, 2),
        student: student,
      );

      final report = DefaultReportGenerator().generateReport(
        classSubject: cs,
        sessions: [session],
        enrollments: [enrollment],
        allRecords: [],
      );

      final snapshot = _service.build(reports: [report]);

      expect(snapshot.totalStudents, 1);
      expect(snapshot.totalLectures, 1);
      expect(snapshot.totalEligible, 0);
      expect(snapshot.overallPercentage, 0);
      expect(snapshot.hasAttendance, isFalse);
      expect(snapshot.topStudents, isEmpty);
      expect(snapshot.needsAttention, isEmpty);
      expect(snapshot.healthBands.every((bucket) => bucket.count == 0), isTrue);
    });
  });
}

StudentModel _student(String id, String name) => StudentModel(
      id: id,
      teacherId: 't1',
      prn: id,
      studentName: name,
      email: '$id@example.edu',
    );

ClassSubjectModel _classSubject(String id, {double threshold = 75}) =>
    ClassSubjectModel(
      id: id,
      teacherId: 't1',
      classId: 'class-$id',
      subjectId: 'subject-$id',
      thresholdPercent: threshold,
      classDetails: ClassModel(
        id: 'class-$id',
        teacherId: 't1',
        className: 'BE E&TC A',
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
