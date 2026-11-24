import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/utils.dart';
import '../../models/attendance_alert.dart';
import '../../providers/attendance_stats_provider.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Attendance Alerts',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(lowAttendanceProvider);
                ref.invalidate(classSubjectStatsProvider);
                ref.invalidate(alertHistoryProvider);
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'At Risk Now'),
              Tab(text: 'Email History'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AtRiskTab(),
            _EmailHistoryTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — students below their subject threshold right now
// ---------------------------------------------------------------------------
class _AtRiskTab extends ConsumerWidget {
  const _AtRiskTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowAsync = ref.watch(lowAttendanceProvider);

    return lowAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorState(
        message: AppErrors.humanize(e),
        onRetry: () => ref.invalidate(lowAttendanceProvider),
      ),
      data: (low) {
        if (low.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_rounded,
                      size: 56, color: AppColors.success),
                  SizedBox(height: 14),
                  Text(
                    'No students below threshold',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Every enrolled student is at or above the configured '
                    'attendance threshold.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: low.length,
          itemBuilder: (context, index) {
            final stat = low[index];
            final className =
                stat.classSubject.classDetails?.className ?? 'Class';
            final subjectName =
                stat.classSubject.subjectDetails?.subjectName ?? 'Subject';
            final threshold = stat.classSubject.thresholdPercent;
            final hasEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                .hasMatch(stat.student.email.trim());

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            AppColors.error.withValues(alpha: 0.12),
                        child: Text(
                          stat.student.prn.length <= 3
                              ? stat.student.prn
                              : stat.student.prn
                                  .substring(stat.student.prn.length - 3),
                          style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(stat.student.studentName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            Text('PRN: ${stat.student.prn}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${stat.percentage.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('$className • $subjectName',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    'Attended ${stat.attended} of ${stat.conducted} lectures '
                    '(below ${threshold.toStringAsFixed(0)}%)',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!stat.classSubject.alertEnabled) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Email alerts are disabled for this class + subject.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600),
                    ),
                  ] else if (!hasEmail) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'No email on file - this student cannot receive alerts.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.error,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — emails the Apps Script actually sent (or failed to send)
// ---------------------------------------------------------------------------
class _EmailHistoryTab extends ConsumerWidget {
  const _EmailHistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(alertHistoryProvider);

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorState(
        message: AppErrors.humanize(e),
        onRetry: () => ref.invalidate(alertHistoryProvider),
      ),
      data: (history) {
        if (history.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mark_email_unread_outlined,
                      size: 56, color: AppColors.textSecondary),
                  SizedBox(height: 14),
                  Text(
                    'No alert emails yet',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'When the low-attendance automation runs, every email it '
                    'sends appears here with its delivery status.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: history.length,
          itemBuilder: (context, index) => _HistoryCard(item: history[index]),
        );
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final AlertHistoryItem item;

  const _HistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final alert = item.alert;
    final status = alert.status.toLowerCase();
    final color = switch (status) {
      'sent' => AppColors.success,
      'failed' => AppColors.error,
      _ => AppColors.warning,
    };
    final studentName = alert.student?.studentName ?? 'Student';
    final prn = alert.student?.prn ?? '';
    final threshold = item.classSubject.thresholdPercent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studentName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (prn.isNotEmpty)
                      Text(
                        'PRN: $prn',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Pill(
                label: alert.alertType == 'reminder' ? 'Reminder' : 'Initial',
                color: AppColors.primary,
              ),
              _Pill(
                label: '${alert.attendancePercent.toStringAsFixed(1)}%',
                color: alert.attendancePercent < threshold
                    ? AppColors.error
                    : AppColors.success,
              ),
              Text(
                '${alert.attendedCount}/${alert.conductedCount} lectures • below ${threshold.toStringAsFixed(0)}%',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${item.className} • ${item.subjectName}',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${status == 'sent' ? 'Sent' : status == 'failed' ? 'Attempted' : 'Queued'} ${AppUtils.formatDate(alert.sentAt)}',
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if ((alert.errorMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              alert.errorMessage!,
              style: const TextStyle(fontSize: 11, color: AppColors.error),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 44, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
