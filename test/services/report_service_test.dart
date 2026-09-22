import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/models/attendance_record.dart';
import 'package:voice_attendance/models/attendance_session.dart';
import 'package:voice_attendance/models/class_model.dart';
import 'package:voice_attendance/models/class_subject.dart';
import 'package:voice_attendance/models/enrollment.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/models/subject.dart';
import 'package:voice_attendance/services/report_service.dart';

void main() {
  late DefaultReportGenerator reportGenerator;
  late ClassSubjectModel classSubject;
  late StudentModel student1;
  late StudentModel studentLate;

  setUp(() {
    reportGenerator = DefaultReportGenerator();

    final classModel = ClassModel(
      id: 'c1',
      teacherId: 't1',
      className: 'BE Computer A',
      academicYear: '2026-2027',
      semester: 'VIII',
    );
    final subjectModel = SubjectModel(
      id: 's1',
      teacherId: 't1',
      subjectCode: 'CS801',
      subjectName: 'Ubiquitous Computing',
    );

    classSubject = ClassSubjectModel(
      id: 'cs1',
      teacherId: 't1',
      classId: 'c1',
      subjectId: 's1',
      classDetails: classModel,
      subjectDetails: subjectModel,
    );

    student1 = StudentModel(id: 'st1', teacherId: 't1', prn: '101', studentName: 'Rahul Patil');
    studentLate = StudentModel(id: 'st2', teacherId: 't1', prn: '102', studentName: 'Sneha Sharma');
  });

  test('Calculates attendance percentage correctly and respects enrollment date', () {
    final enrollments = [
      EnrollmentModel(
        id: 'e1',
        classSubjectId: 'cs1',
        studentId: 'st1',
        enrolledFrom: DateTime(2026, 9, 1),
        student: student1,
      ),
      EnrollmentModel(
        id: 'e2',
        classSubjectId: 'cs1',
        studentId: 'st2',
        enrolledFrom: DateTime(2026, 9, 15), // Enrolled late on Sept 15
        student: studentLate,
      ),
    ];

    final sessions = [
      AttendanceSessionModel(id: 'sess1', classSubjectId: 'cs1', lectureDate: DateTime(2026, 9, 5)),
      AttendanceSessionModel(id: 'sess2', classSubjectId: 'cs1', lectureDate: DateTime(2026, 9, 10)),
      AttendanceSessionModel(id: 'sess3', classSubjectId: 'cs1', lectureDate: DateTime(2026, 9, 20)),
      AttendanceSessionModel(id: 'sess4', classSubjectId: 'cs1', lectureDate: DateTime(2026, 9, 22)),
    ];

    final records = [
      // Student 1 (Present in 3 out of 4 sessions = 75%)
      AttendanceRecordModel(id: 'r1', sessionId: 'sess1', studentId: 'st1', status: 'present'),
      AttendanceRecordModel(id: 'r2', sessionId: 'sess2', studentId: 'st1', status: 'present'),
      AttendanceRecordModel(id: 'r3', sessionId: 'sess3', studentId: 'st1', status: 'absent'),
      AttendanceRecordModel(id: 'r4', sessionId: 'sess4', studentId: 'st1', status: 'present'),

      // Student Late (Sessions 1 and 2 before Sept 15 enrollment -> excluded. Present in 1 of 2 eligible = 50%)
      AttendanceRecordModel(id: 'r5', sessionId: 'sess3', studentId: 'st2', status: 'absent'),
      AttendanceRecordModel(id: 'r6', sessionId: 'sess4', studentId: 'st2', status: 'present'),
    ];

    final report = reportGenerator.generateReport(
      classSubject: classSubject,
      sessions: sessions,
      enrollments: enrollments,
      allRecords: records,
    );

    expect(report.studentRows.length, 2);

    final row1 = report.studentRows.firstWhere((r) => r.student.prn == '101');
    expect(row1.eligibleConductedCount, 4);
    expect(row1.attendedCount, 3);
    expect(row1.percentage, 75.0);
    expect(row1.isBelowThreshold(75.0), false);

    final rowLate = report.studentRows.firstWhere((r) => r.student.prn == '102');
    expect(rowLate.eligibleConductedCount, 2); // Only 2 sessions post-enrollment
    expect(rowLate.attendedCount, 1);
    expect(rowLate.percentage, 50.0);
    expect(rowLate.isBelowThreshold(75.0), true);
  });
}
