import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../models/class_subject.dart';
import '../../models/student.dart';
import '../../providers/attendance_controller.dart';
import '../../services/excel_service.dart';

class ReviewAttendanceScreen extends ConsumerStatefulWidget {
  final String classSubjectId;
  final ClassSubjectModel? classSubject;

  const ReviewAttendanceScreen({
    super.key,
    required this.classSubjectId,
    this.classSubject,
  });

  @override
  ConsumerState<ReviewAttendanceScreen> createState() =>
      _ReviewAttendanceScreenState();
}

class _ReviewAttendanceScreenState extends ConsumerState<ReviewAttendanceScreen> {
  String _searchQuery = '';
  bool _isSaving = false;
  final ExcelService _excelService = DefaultExcelService();

  Future<void> _finalizeLecture() async {
    if (_isSaving) return;
    final provider = attendanceControllerProvider(widget.classSubjectId);
    final controller = ref.read(provider.notifier);
    final state = ref.read(provider);

    setState(() => _isSaving = true);
    try {
      final ok = await controller.finalize();
      if (!ok) {
        if (!mounted) return;
        final message = ref.read(provider).error ??
            'Could not finalize the lecture. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(message),
              backgroundColor: AppColors.error),
        );
        return;
      }

      // Dated Excel for this lecture.
      final date = state.session?.lectureDate ?? DateTime.now();
      final bytes = _excelService.generateSessionAttendanceExcel(
        className: widget.classSubject?.classDetails?.className ?? 'Class',
        subjectName: widget.classSubject?.subjectDetails?.subjectName ?? 'Subject',
        date: date,
        roster: state.roster,
        attendanceMap: state.attendanceMap,
      );

      final safeClass = (widget.classSubject?.classDetails?.className ?? 'Class')
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final fileName =
          'Attendance_${safeClass}_${AppUtils.formatIsoDate(date)}.xlsx';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Lecture saved for ${AppUtils.formatDate(date)} (${state.presentCount}/${state.roster.length} present). Sharing Excel…'),
          backgroundColor: AppColors.success,
        ),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text:
              '${widget.classSubject?.classDetails?.className ?? 'Class'} attendance ${AppUtils.formatDate(date)}',
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Saved, but Excel share failed: $e'),
            backgroundColor: AppColors.warning),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = attendanceControllerProvider(widget.classSubjectId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    final filteredRoster = state.roster.where((StudentModel student) {
      final q = _searchQuery.toLowerCase();
      return student.studentName.toLowerCase().contains(q) ||
          student.prn.contains(q);
    }).toList();

    final className = widget.classSubject?.classDetails?.className ?? 'Class';
    final subjectName =
        widget.classSubject?.subjectDetails?.subjectName ?? 'Subject';
    final lectureDate = state.session?.lectureDate;
    final isCompleted = state.isCompleted;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            isCompleted
                ? 'Finalized Attendance'
                : 'Review & Finalize Attendance',
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.primary.withValues(alpha: 0.05),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Summary Status',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      '${state.presentCount} of ${state.roster.length} Students Present',
                      style:
                          const TextStyle(color: AppColors.textSecondary),
                    ),
                    Text(
                      lectureDate != null
                          ? '$className • $subjectName • ${AppUtils.formatDate(lectureDate)}'
                          : '$className • $subjectName',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded,
                            size: 16, color: AppColors.success),
                        SizedBox(width: 6),
                        Text('FINALIZED',
                            style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                      ],
                    ),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check),
                    label: Text(_isSaving ? 'Saving…' : 'Finalize Lecture'),
                    onPressed: _isSaving ? null : _finalizeLecture,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search student by name or PRN...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredRoster.length,
              itemBuilder: (context, index) {
                final student = filteredRoster[index];
                final bool isPresent =
                    state.attendanceMap[student.id] == 'present';
                final String source = state.sourceMap[student.id] ?? 'default';

                return Card(
                  child: ListTile(
                    title: Text(student.studentName,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text('PRN: ${student.prn} | Source: $source'),
                    trailing: Switch(
                      value: isPresent,
                      activeThumbColor: AppColors.success,
                      onChanged: state.isCompleted
                          ? null
                          : (val) async {
                              await controller.setStatus(
                                  student, val ? 'present' : 'absent');
                            },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
