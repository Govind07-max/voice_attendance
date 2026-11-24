import '../models/analytics.dart';
import 'report_service.dart';

/// Turns finalized attendance reports into chart-ready analytics.
///
/// The service is pure so the calculations can be unit-tested without
/// Supabase or Flutter widgets.
class AnalyticsService {
  const AnalyticsService();

  TeacherAnalyticsSnapshot build({required List<AttendanceReport> reports}) {
    if (reports.isEmpty) return const TeacherAnalyticsSnapshot.empty();

    final studentIds = <String>{};
    final belowThresholdStudentIds = <String>{};
    final rows = <({StudentReportRow row, AttendanceReport report})>[];

    var totalLectures = 0;
    var totalPresent = 0;
    var totalEligible = 0;

    for (final report in reports) {
      totalLectures += report.sessions.length;
      for (final row in report.studentRows) {
        studentIds.add(row.student.id);
        if (row.eligibleConductedCount <= 0) continue;

        rows.add((row: row, report: report));
        totalPresent += row.attendedCount;
        totalEligible += row.eligibleConductedCount;

        if (row.isBelowThreshold(report.classSubject.thresholdPercent)) {
          belowThresholdStudentIds.add(row.student.id);
        }
      }
    }

    final classComparison = <ClassAttendancePoint>[];
    for (final report in reports) {
      if (report.sessions.isEmpty) continue;

      final eligibleRows = report.studentRows
          .where((row) => row.eligibleConductedCount > 0)
          .toList();
      if (eligibleRows.isEmpty) {
        classComparison.add(ClassAttendancePoint(
          classSubject: report.classSubject,
          averagePercentage: 0,
          studentCount: report.studentRows.length,
          sessionCount: report.sessions.length,
          studentsBelowThreshold: 0,
        ));
        continue;
      }

      final average = eligibleRows.fold<double>(
            0,
            (sum, row) => sum + row.percentage,
          ) /
          eligibleRows.length;
      final below = eligibleRows
          .where((row) =>
              row.isBelowThreshold(report.classSubject.thresholdPercent))
          .map((row) => row.student.id)
          .toSet()
          .length;

      classComparison.add(ClassAttendancePoint(
        classSubject: report.classSubject,
        averagePercentage: _round1(average),
        studentCount: report.studentRows.length,
        sessionCount: report.sessions.length,
        studentsBelowThreshold: below,
      ));
    }
    classComparison.sort(
      (a, b) => a.averagePercentage.compareTo(b.averagePercentage),
    );

    final trend = _buildTrend(reports);

    final performances = rows
        .map((entry) => StudentPerformance(
              student: entry.row.student,
              classSubject: entry.report.classSubject,
              percentage: entry.row.percentage,
              attended: entry.row.attendedCount,
              conducted: entry.row.eligibleConductedCount,
            ))
        .toList();

    final topStudents = [...performances]..sort((a, b) {
        final byPercentage = b.percentage.compareTo(a.percentage);
        if (byPercentage != 0) return byPercentage;
        return a.student.studentName.compareTo(b.student.studentName);
      });

    final needsAttention = performances
        .where((p) => p.percentage < p.classSubject.thresholdPercent)
        .toList()
      ..sort((a, b) {
        final byPercentage = a.percentage.compareTo(b.percentage);
        if (byPercentage != 0) return byPercentage;
        return a.student.studentName.compareTo(b.student.studentName);
      });

    final healthBands = _buildHealthBands(rows);

    return TeacherAnalyticsSnapshot(
      totalStudents: studentIds.length,
      totalLectures: totalLectures,
      totalPresent: totalPresent,
      totalAbsent: totalEligible - totalPresent,
      totalEligible: totalEligible,
      overallPercentage: totalEligible == 0
          ? 0
          : _round1((totalPresent / totalEligible) * 100),
      studentsBelowThreshold: belowThresholdStudentIds.length,
      healthBands: healthBands,
      classComparison: classComparison,
      trend: trend,
      topStudents: topStudents.take(5).toList(),
      needsAttention: needsAttention.take(5).toList(),
    );
  }

  List<AttendanceTrendPoint> _buildTrend(List<AttendanceReport> reports) {
    final byDate = <DateTime, ({int present, int eligible})>{};

    for (final report in reports) {
      for (final row in report.studentRows) {
        for (final session in report.sessions) {
          final status = row.sessionStatusMap[session.id];
          if (status != 'P' && status != 'A') continue;

          final day = DateTime(
            session.lectureDate.year,
            session.lectureDate.month,
            session.lectureDate.day,
          );
          final previous = byDate[day] ?? (present: 0, eligible: 0);
          byDate[day] = (
            present: previous.present + (status == 'P' ? 1 : 0),
            eligible: previous.eligible + 1,
          );
        }
      }
    }

    final dates = byDate.keys.toList()..sort();
    return dates
        .map((date) => AttendanceTrendPoint(
              date: date,
              presentCount: byDate[date]!.present,
              eligibleCount: byDate[date]!.eligible,
            ))
        .toList();
  }

  List<AnalyticsBucket> _buildHealthBands(
    List<({StudentReportRow row, AttendanceReport report})> rows,
  ) {
    var onTrack = 0;
    var nearRisk = 0;
    var critical = 0;

    for (final entry in rows) {
      final row = entry.row;
      final threshold = entry.report.classSubject.thresholdPercent;
      if (row.percentage >= threshold) {
        onTrack++;
      } else if (row.percentage >= threshold - 10) {
        nearRisk++;
      } else {
        critical++;
      }
    }

    final total = onTrack + nearRisk + critical;
    double pct(int count) => total == 0 ? 0 : _round1((count / total) * 100);

    return [
      AnalyticsBucket(
          label: 'On track', count: onTrack, percentage: pct(onTrack)),
      AnalyticsBucket(
          label: 'Near risk', count: nearRisk, percentage: pct(nearRisk)),
      AnalyticsBucket(
          label: 'Critical', count: critical, percentage: pct(critical)),
    ];
  }

  double _round1(double value) => double.parse(value.toStringAsFixed(1));
}
