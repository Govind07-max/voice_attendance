import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/utils.dart';
import '../../models/class_subject.dart';
import '../../providers/classes_provider.dart';
import '../../providers/database_provider.dart';
import '../../services/excel_service.dart';
import '../../services/pdf_service.dart';
import '../../services/report_service.dart';
import '../students/student_history_screen.dart';
import '../analytics/analytics_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    final classSubjectsAsync = ref.watch(classSubjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _view == 0 ? 'Cumulative Attendance Reports' : 'Attendance Analytics',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: _view == 0 ? 'View analytics' : 'View reports',
            onPressed: () => setState(() => _view = _view == 0 ? 1 : 0),
            icon: Icon(_view == 0
                ? Icons.insights_outlined
                : Icons.table_chart_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('Report'),
                    icon: Icon(Icons.table_chart_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('Analytics'),
                    icon: Icon(Icons.insights_outlined, size: 17),
                  ),
                ],
                selected: {_view},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                onSelectionChanged: (selection) {
                  setState(() => _view = selection.first);
                },
              ),
            ),
          ),
          Expanded(
            child: _view == 0
                ? classSubjectsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          AppErrors.humanize(e),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    ),
                    data: (classSubjects) {
                      if (classSubjects.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Text(
                              'Create a class + subject first. Reports appear here once a lecture is finalized.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return _ReportPicker(classSubjects: classSubjects);
                    },
                  )
                : const AnalyticsView(),
          ),
        ],
      ),
    );
  }
}

class _ReportPicker extends ConsumerStatefulWidget {
  final List<ClassSubjectModel> classSubjects;
  const _ReportPicker({required this.classSubjects});

  @override
  ConsumerState<_ReportPicker> createState() => _ReportPickerState();
}

class _ReportPickerState extends ConsumerState<_ReportPicker> {
  /// The selected class + subject **id**. Using the id (not the model object)
  /// keeps the dropdown valid when the provider refetches and returns new
  /// model instances for the same rows.
  String? _selectedId;
  AttendanceReport? _report;
  bool _loading = false;
  String? _error;

  ClassSubjectModel? get _selected {
    for (final cs in widget.classSubjects) {
      if (cs.id == _selectedId) return cs;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.classSubjects.isNotEmpty) {
      _selectedId = widget.classSubjects.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(covariant _ReportPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list changed (loaded, or refetched with new instances): make sure
    // the selection still points at a row that exists.
    if (_selectedId == null && widget.classSubjects.isNotEmpty) {
      _selectedId = widget.classSubjects.first.id;
      _load();
    } else if (_selectedId != null && _selected == null) {
      _selectedId = widget.classSubjects.first.id;
      _load();
    }
  }

  Future<void> _load() async {
    final cs = _selected;
    if (cs == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseServiceProvider);
      final sessions = await db.getCompletedSessions(cs.id);
      if (sessions.isEmpty) {
        if (!mounted) return;
        setState(() {
          _report = null;
          _loading = false;
        });
        return;
      }
      final enrollments = await db.getEnrollments(cs.id);
      final records = await db
          .getAttendanceRecordsForSessions(sessions.map((s) => s.id).toList());

      final report = DefaultReportGenerator().generateReport(
        classSubject: cs,
        sessions: sessions,
        enrollments: enrollments,
        allRecords: records,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Class + Subject',
              prefixIcon: Icon(Icons.school_outlined),
            ),
            items: widget.classSubjects.map((cs) {
              final className = cs.classDetails?.className ?? 'Class';
              final subjectName = cs.subjectDetails?.subjectName ?? 'Subject';
              return DropdownMenuItem(
                value: cs.id,
                child: Text('$className • $subjectName',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (id) {
              if (id == null) return;
              setState(() => _selectedId = id);
              _load();
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null
                  ? Center(child: Text(_error!))
                  : (report == null
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Text(
                              'No finalized lectures yet for this class + subject.\n'
                              'Take a lecture and tap "Finalize Lecture" to add it to the report.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _ReportBody(report: report))),
        ),
      ],
    );
  }
}

class _ReportBody extends ConsumerStatefulWidget {
  final AttendanceReport report;
  const _ReportBody({required this.report});

  @override
  ConsumerState<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends ConsumerState<_ReportBody> {
  bool _isExporting = false;
  bool _isExportingPdf = false;

  Future<void> _export() async {
    setState(() => _isExporting = true);
    try {
      final bytes = DefaultExcelService()
          .generateCumulativeAttendanceExcel(widget.report);
      final className =
          widget.report.classSubject.classDetails?.className ?? 'Class';
      final safeClass = className.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final fileName =
          'Cumulative_Attendance_${safeClass}_${AppUtils.formatIsoDate(DateTime.now())}.xlsx';

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel generated (${bytes.length} bytes). Sharing…'),
          backgroundColor: AppColors.success,
        ),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Cumulative attendance report — $className',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Excel export failed: ${AppErrors.humanize(e)}'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _isExportingPdf = true);
    try {
      final bytes = await const PdfService()
          .generateCumulativeAttendancePdf(widget.report);
      final className =
          widget.report.classSubject.classDetails?.className ?? 'Class';
      final subject =
          widget.report.classSubject.subjectDetails?.subjectName ?? 'Subject';
      final safeClass = className.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final safeSubject = subject.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final fileName = 'Attendance_${safeClass}_${safeSubject}_'
          '${AppUtils.formatIsoDate(DateTime.now())}.pdf';

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF generated (${(bytes.length / 1024).round()} KB). '
              'Sharing…'),
          backgroundColor: AppColors.success,
        ),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Cumulative attendance report — $className',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('PDF export failed: ${AppErrors.humanize(e)}'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final className = report.classSubject.classDetails?.className ?? 'Class';
    final subjectName =
        report.classSubject.subjectDetails?.subjectName ?? 'Subject';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subjectName,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    Text(
                        'Class: $className • ${report.sessions.length} lectures',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.file_download_rounded, size: 18),
                      label: Text(_isExporting ? 'Saving…' : 'Export Excel'),
                      onPressed: _isExporting ? null : _export,
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: AppColors.primaryDark,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                      icon: _isExportingPdf
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text(_isExportingPdf ? 'Saving…' : 'Export PDF'),
                      onPressed: _isExportingPdf ? null : _exportPdf,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Cumulative Attendance Grid',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                    AppColors.primaryLight.withValues(alpha: 0.5)),
                columns: [
                  const DataColumn(
                      label: Text('PRN',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Student Name',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  ...report.sessions.map((s) => DataColumn(
                        label: Text(
                            '${s.lectureDate.day}/${s.lectureDate.month}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      )),
                  const DataColumn(
                      label: Text('Attended',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Conducted',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('%',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: report.studentRows.map((row) {
                  final bool isLow = row.isBelowThreshold(75.0);
                  return DataRow(
                    color: isLow
                        ? WidgetStateProperty.all(
                            AppColors.error.withValues(alpha: 0.05))
                        : null,
                    onSelectChanged: (selected) {
                      if (selected != true) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              StudentHistoryScreen(student: row.student),
                        ),
                      );
                    },
                    cells: [
                      DataCell(Text(row.student.prn,
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(row.student.studentName)),
                      ...report.sessions.map((s) {
                        final String status = row.sessionStatusMap[s.id] ?? '-';
                        final Color color = status == 'P'
                            ? AppColors.success
                            : (status == 'A' ? AppColors.error : Colors.grey);
                        return DataCell(Text(status,
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: color)));
                      }),
                      DataCell(Text('${row.attendedCount}')),
                      DataCell(Text('${row.eligibleConductedCount}')),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isLow
                                ? AppColors.error.withValues(alpha: 0.15)
                                : AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${row.percentage}%',
                            style: TextStyle(
                              color:
                                  isLow ? AppColors.error : AppColors.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
