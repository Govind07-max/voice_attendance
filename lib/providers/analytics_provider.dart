import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analytics.dart';
import '../services/analytics_service.dart';
import '../services/report_service.dart';
import 'teacher_attendance_data_provider.dart';

/// Special family key that means "all class + subjects".
const analyticsAllClassesScope = '__all_classes__';

/// Chart-ready analytics for one teacher.
///
/// [scope] is [analyticsAllClassesScope] for the teacher-wide view, or a
/// class_subject id for a single class drill-down.
final analyticsProvider = FutureProvider.autoDispose
    .family<TeacherAnalyticsSnapshot, String>((ref, scope) async {
  final data = await ref.watch(teacherAttendanceDataProvider.future);
  final generator = DefaultReportGenerator();
  final reports = <AttendanceReport>[];

  for (final entry in data) {
    if (scope != analyticsAllClassesScope && entry.classSubject.id != scope) {
      continue;
    }
    if (entry.sessions.isEmpty) continue;

    reports.add(generator.generateReport(
      classSubject: entry.classSubject,
      sessions: entry.sessions.toList(),
      enrollments: entry.enrollments,
      allRecords: entry.records,
    ));
  }

  return const AnalyticsService().build(reports: reports);
});
