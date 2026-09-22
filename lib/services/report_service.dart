import '../models/attendance_record.dart';
import '../models/attendance_session.dart';
import '../models/class_subject.dart';
import '../models/enrollment.dart';
import '../models/student.dart';

class StudentReportRow {
  final StudentModel student;
  final EnrollmentModel enrollment;
  final Map<String, String> sessionStatusMap; // sessionId -> 'P', 'A', '-' (not eligible)
  final int attendedCount;
  final int eligibleConductedCount;
  final double percentage;

  StudentReportRow({
    required this.student,
    required this.enrollment,
    required this.sessionStatusMap,
    required this.attendedCount,
    required this.eligibleConductedCount,
    required this.percentage,
  });

  bool isBelowThreshold(double thresholdPercent) {
    return percentage < thresholdPercent;
  }
}

class AttendanceReport {
  final ClassSubjectModel classSubject;
  final List<AttendanceSessionModel> sessions;
  final List<StudentReportRow> studentRows;

  AttendanceReport({
    required this.classSubject,
    required this.sessions,
    required this.studentRows,
  });
}

abstract class ReportGenerator {
  AttendanceReport generateReport({
    required ClassSubjectModel classSubject,
    required List<AttendanceSessionModel> sessions,
    required List<EnrollmentModel> enrollments,
    required List<AttendanceRecordModel> allRecords,
  });
}

class DefaultReportGenerator implements ReportGenerator {
  @override
  AttendanceReport generateReport({
    required ClassSubjectModel classSubject,
    required List<AttendanceSessionModel> sessions,
    required List<EnrollmentModel> enrollments,
    required List<AttendanceRecordModel> allRecords,
  }) {
    // Sort sessions chronologically
    sessions.sort((a, b) {
      int dateCmp = a.lectureDate.compareTo(b.lectureDate);
      if (dateCmp != 0) return dateCmp;
      return a.periodNumber.compareTo(b.periodNumber);
    });

    // Map records for quick lookup: "sessionId_studentId" -> status
    Map<String, String> recordMap = {};
    for (var record in allRecords) {
      recordMap['${record.sessionId}_${record.studentId}'] = record.status;
    }

    List<StudentReportRow> rows = [];

    for (var enrollment in enrollments) {
      if (enrollment.student == null) continue;
      StudentModel student = enrollment.student!;

      Map<String, String> sessionStatusMap = {};
      int attendedCount = 0;
      int eligibleConductedCount = 0;

      for (var session in sessions) {
        // Section 16 rule: lectures before enrollment date are not eligible
        DateTime sessionDateOnly = DateTime(
          session.lectureDate.year,
          session.lectureDate.month,
          session.lectureDate.day,
        );
        DateTime enrolledDateOnly = DateTime(
          enrollment.enrolledFrom.year,
          enrollment.enrolledFrom.month,
          enrollment.enrolledFrom.day,
        );

        if (sessionDateOnly.isBefore(enrolledDateOnly)) {
          sessionStatusMap[session.id] = '-'; // Not eligible
          continue;
        }

        eligibleConductedCount++;
        String? status = recordMap['${session.id}_${student.id}'];
        
        if (status == 'present') {
          sessionStatusMap[session.id] = 'P';
          attendedCount++;
        } else {
          sessionStatusMap[session.id] = 'A';
        }
      }

      double percentage = eligibleConductedCount > 0
          ? (attendedCount / eligibleConductedCount) * 100.0
          : 100.0;

      rows.add(StudentReportRow(
        student: student,
        enrollment: enrollment,
        sessionStatusMap: sessionStatusMap,
        attendedCount: attendedCount,
        eligibleConductedCount: eligibleConductedCount,
        percentage: double.parse(percentage.toStringAsFixed(2)),
      ));
    }

    // Sort student rows by PRN
    rows.sort((a, b) => a.student.prn.compareTo(b.student.prn));

    return AttendanceReport(
      classSubject: classSubject,
      sessions: sessions,
      studentRows: rows,
    );
  }
}
