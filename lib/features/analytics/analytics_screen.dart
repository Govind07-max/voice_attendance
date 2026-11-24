import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../models/analytics.dart';
import '../../models/class_subject.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/classes_provider.dart';
import '../../providers/teacher_attendance_data_provider.dart';
import '../students/student_history_screen.dart';

/// Teacher-wide attendance analytics shown inside the Reports tab.
class AnalyticsView extends ConsumerStatefulWidget {
  const AnalyticsView({super.key});

  @override
  ConsumerState<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends ConsumerState<AnalyticsView> {
  String _scope = analyticsAllClassesScope;

  Future<void> _refresh() async {
    ref.invalidate(teacherAttendanceDataProvider);
    ref.invalidate(analyticsProvider(_scope));
    try {
      await ref.read(analyticsProvider(_scope).future);
    } catch (_) {
      // The error state is rendered by the AsyncValue below.
    }
  }

  @override
  Widget build(BuildContext context) {
    final classSubjectsAsync = ref.watch(classSubjectsProvider);
    final analyticsAsync = ref.watch(analyticsProvider(_scope));

    return classSubjectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        message: AppErrors.humanize(error),
        onRetry: () => ref.invalidate(classSubjectsProvider),
      ),
      data: (classSubjects) {
        // A class can disappear while this view is open (deleted/archived).
        // Fall back to the teacher-wide view instead of showing an empty scope.
        final scopeStillExists = _scope == analyticsAllClassesScope ||
            classSubjects.any((cs) => cs.id == _scope);
        if (!scopeStillExists && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _scope = analyticsAllClassesScope);
          });
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              _ScopeSelector(
                classSubjects: classSubjects,
                scope: _scope,
                onChanged: (scope) => setState(() => _scope = scope),
                onRefresh: _refresh,
              ),
              const SizedBox(height: 16),
              analyticsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => _ErrorState(
                  message: AppErrors.humanize(error),
                  onRetry: () => ref.invalidate(analyticsProvider(_scope)),
                ),
                data: (snapshot) => _AnalyticsBody(snapshot: snapshot),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScopeSelector extends StatelessWidget {
  final List<ClassSubjectModel> classSubjects;
  final String scope;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onRefresh;

  const _ScopeSelector({
    required this.classSubjects,
    required this.scope,
    required this.onChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: scope,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Analytics scope',
              prefixIcon: Icon(Icons.filter_alt_outlined),
            ),
            items: [
              const DropdownMenuItem(
                value: analyticsAllClassesScope,
                child: Text('All classes'),
              ),
              ...classSubjects.map((cs) {
                final className = cs.classDetails?.className ?? 'Class';
                final subjectName = cs.subjectDetails?.subjectName ?? 'Subject';
                return DropdownMenuItem(
                  value: cs.id,
                  child: Text('$className • $subjectName',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              }),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Refresh analytics',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  final TeacherAnalyticsSnapshot snapshot;

  const _AnalyticsBody({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    if (!snapshot.hasLectures) {
      return const _EmptyState(
        icon: Icons.insights_outlined,
        title: 'No analytics yet',
        message:
            'Finalize a lecture for this class to see attendance charts and trends.',
      );
    }
    if (!snapshot.hasAttendance) {
      return const _EmptyState(
        icon: Icons.pie_chart_outline,
        title: 'No attendance records yet',
        message:
            'The lectures are finalized, but there are no enrolled students or attendance marks to analyze.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _KpiCard(
                    icon: Icons.groups_rounded,
                    label: 'Students',
                    value: '${snapshot.totalStudents}',
                    color: AppColors.info,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _KpiCard(
                    icon: Icons.menu_book_rounded,
                    label: 'Finalized lectures',
                    value: '${snapshot.totalLectures}',
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _KpiCard(
                    icon: Icons.trending_up_rounded,
                    label: 'Overall attendance',
                    value: '${snapshot.overallPercentage.toStringAsFixed(1)}%',
                    color: AppColors.success,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _KpiCard(
                    icon: Icons.warning_amber_rounded,
                    label: 'Students below threshold',
                    value: '${snapshot.studentsBelowThreshold}',
                    color: snapshot.studentsBelowThreshold == 0
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Present vs absent',
          subtitle: 'Every eligible attendance mark in this scope',
          child: _DonutChart(
            centerValue: '${snapshot.overallPercentage.toStringAsFixed(1)}%',
            centerLabel: 'present',
            sections: [
              _ChartSection(
                value: snapshot.totalPresent.toDouble(),
                color: AppColors.success,
              ),
              _ChartSection(
                value: snapshot.totalAbsent.toDouble(),
                color: AppColors.error,
              ),
            ],
            legend: [
              _LegendItem(
                label: 'Present',
                color: AppColors.success,
                count: snapshot.totalPresent,
              ),
              _LegendItem(
                label: 'Absent',
                color: AppColors.error,
                count: snapshot.totalAbsent,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Attendance health',
          subtitle: 'Student records grouped by each class’s own threshold',
          child: _DonutChart(
            centerValue: '${snapshot.totalEligible}',
            centerLabel: 'student records',
            sections: [
              _ChartSection(
                value: _bucketValue(snapshot, 'On track'),
                color: AppColors.success,
              ),
              _ChartSection(
                value: _bucketValue(snapshot, 'Near risk'),
                color: AppColors.warning,
              ),
              _ChartSection(
                value: _bucketValue(snapshot, 'Critical'),
                color: AppColors.error,
              ),
            ],
            legend: snapshot.healthBands
                .map((bucket) => _LegendItem(
                      label: bucket.label,
                      color: _healthColor(bucket.label),
                      count: bucket.count,
                      percentage: bucket.percentage,
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Class comparison',
          subtitle: 'Average attendance by class + subject',
          child: _ClassBarChart(points: snapshot.classComparison),
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Attendance trend',
          subtitle: 'Percentage of eligible marks that were present',
          child: _TrendLineChart(points: snapshot.trend),
        ),
        const SizedBox(height: 16),
        _PerformanceList(
          title: 'Needs attention',
          subtitle: 'Lowest attendance below class threshold',
          entries: snapshot.needsAttention,
          emptyMessage:
              'No students are below their class threshold in this scope.',
        ),
        const SizedBox(height: 12),
        _PerformanceList(
          title: 'Top performers',
          subtitle: 'Highest attendance in this scope',
          entries: snapshot.topStudents,
          emptyMessage: 'No eligible student records yet.',
        ),
      ],
    );
  }

  double _bucketValue(TeacherAnalyticsSnapshot snapshot, String label) {
    for (final bucket in snapshot.healthBands) {
      if (bucket.label == label) return bucket.count.toDouble();
    }
    return 0;
  }

  Color _healthColor(String label) {
    switch (label) {
      case 'On track':
        return AppColors.success;
      case 'Near risk':
        return AppColors.warning;
      default:
        return AppColors.error;
    }
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              )),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ChartSection {
  final double value;
  final Color color;

  const _ChartSection({
    required this.value,
    required this.color,
  });
}

class _DonutChart extends StatelessWidget {
  final String centerValue;
  final String centerLabel;
  final List<_ChartSection> sections;
  final List<_LegendItem> legend;

  const _DonutChart({
    required this.centerValue,
    required this.centerLabel,
    required this.sections,
    required this.legend,
  });

  @override
  Widget build(BuildContext context) {
    final total = sections.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) {
      return const _EmptyChart(message: 'No marks to chart yet.');
    }

    return Column(
      children: [
        SizedBox(
          height: 184,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 52,
                  centerSpaceColor: Colors.white,
                  startDegreeOffset: -90,
                  sections: sections
                      .map((section) => PieChartSectionData(
                            value: section.value,
                            color: section.color,
                            radius: 42,
                            showTitle: false,
                            borderSide:
                                const BorderSide(color: Colors.white, width: 2),
                          ))
                      .toList(),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    centerValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    centerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 8,
          children: legend
              .map((item) => _Legend(
                    label: item.label,
                    color: item.color,
                    value: '${item.count}'
                        '${item.percentage == null ? '' : ' • ${item.percentage!.toStringAsFixed(1)}%'}',
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _LegendItem {
  final String label;
  final Color color;
  final int count;
  final double? percentage;

  const _LegendItem({
    required this.label,
    required this.color,
    required this.count,
    this.percentage,
  });
}

class _Legend extends StatelessWidget {
  final String label;
  final Color color;
  final String value;

  const _Legend({
    required this.label,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '$label: $value',
            softWrap: true,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ClassBarChart extends StatelessWidget {
  final List<ClassAttendancePoint> points;

  const _ClassBarChart({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _EmptyChart(message: 'No class data to compare yet.');
    }

    final chartWidth = math.max(320.0, points.length * 92.0);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: chartWidth,
        height: 224,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, right: 4),
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: 100,
              alignment: BarChartAlignment.spaceAround,
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: points[i].averagePercentage,
                        width: 22,
                        color: points[i].averagePercentage <
                                points[i].classSubject.thresholdPercent
                            ? AppColors.error
                            : AppColors.primary,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: 100,
                          color: AppColors.borderLight.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
              ],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 25,
                getDrawingHorizontalLine: (value) => const FlLine(
                  color: AppColors.borderLight,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: 25,
                    getTitlesWidget: (value, meta) => Text(
                      '${value.toInt()}%',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SizedBox(
                          width: 78,
                          child: Text(
                            points[index].subjectName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendLineChart extends StatelessWidget {
  final List<AttendanceTrendPoint> points;

  const _TrendLineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _EmptyChart(message: 'No dated attendance data yet.');
    }

    final visible =
        points.length > 12 ? points.sublist(points.length - 12) : points;
    final step = math.max(1, (visible.length / 4).ceil());
    final maxX = math.max(1, visible.length - 1).toDouble();

    return SizedBox(
      height: 220,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 8),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: maxX,
            minY: 0,
            maxY: 100,
            clipData: const FlClipData.all(),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < visible.length; i++)
                    FlSpot(i.toDouble(), visible[i].percentage),
                ],
                isCurved: true,
                curveSmoothness: 0.25,
                color: AppColors.primary,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
            ],
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 25,
              getDrawingHorizontalLine: (value) => const FlLine(
                color: AppColors.borderLight,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: 25,
                  getTitlesWidget: (value, meta) => Text(
                    '${value.toInt()}%',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 ||
                        index >= visible.length ||
                        index % step != 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '${visible[index].date.day}/${visible[index].date.month}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PerformanceList extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<StudentPerformance> entries;
  final String emptyMessage;

  const _PerformanceList({
    required this.title,
    required this.subtitle,
    required this.entries,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              )),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              )),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                emptyMessage,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            ...entries.map((entry) => Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      foregroundColor: AppColors.primaryDark,
                      child: Text(entry.student.prn.length <= 3
                          ? entry.student.prn
                          : entry.student.prn
                              .substring(entry.student.prn.length - 3)),
                    ),
                    title: Text(
                      entry.student.studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${entry.className} • ${entry.subjectName}\n'
                      '${entry.attended}/${entry.conducted} lectures attended',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _PercentagePill(
                      percentage: entry.percentage,
                      color:
                          entry.percentage < entry.classSubject.thresholdPercent
                              ? AppColors.error
                              : AppColors.success,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            StudentHistoryScreen(student: entry.student),
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

class _PercentagePill extends StatelessWidget {
  final double percentage;
  final Color color;

  const _PercentagePill({required this.percentage, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${percentage.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final String message;

  const _EmptyChart({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppColors.primary),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 40, color: AppColors.error),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
