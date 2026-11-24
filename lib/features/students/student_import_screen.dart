import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../models/class_subject.dart';
import '../../models/student.dart';
import '../../providers/classes_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/teacher_attendance_data_provider.dart';
import '../../services/excel_service.dart';

class StudentImportScreen extends ConsumerStatefulWidget {
  final ClassSubjectModel? classSubject;

  const StudentImportScreen({super.key, this.classSubject});

  @override
  ConsumerState<StudentImportScreen> createState() =>
      _StudentImportScreenState();
}

class _StudentImportScreenState extends ConsumerState<StudentImportScreen> {
  final ExcelService _excelService = DefaultExcelService();
  String? _fileName;
  ExcelImportPreview? _preview;
  bool _isProcessing = false;
  bool _isImporting = false;

  Future<void> _pickExcelFile() async {
    try {
      final PlatformFile? picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (picked == null) return;
      final Uint8List bytes = await picked.readAsBytes();

      if (bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read that file. Try another XLSX file.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      setState(() {
        _fileName = picked.name;
        _isProcessing = true;
        _preview = null;
      });

      final preview = _excelService.parseStudentExcel(bytes, 't1');
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error reading Excel file: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _confirmImport() async {
    final preview = _preview;
    final cs = widget.classSubject;
    final teacherId = ref.read(teacherIdProvider);
    if (preview == null || preview.validStudents.isEmpty) return;

    if (cs == null || teacherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Open the roster from a class + subject so the students can be enrolled.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isImporting = true);
    try {
      await ref.read(databaseServiceProvider).bulkImportStudentsAndEnroll(
            teacherId: teacherId,
            classSubjectId: cs.id,
            students: preview.validStudents,
          );

      if (!mounted) return;
      setState(() {
        _preview = null;
        _fileName = null;
      });

      ref.invalidate(rosterProvider(cs.id));
      ref.invalidate(classSubjectsProvider);
      ref.invalidate(teacherCountsProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Imported ${preview.validStudents.length} students into ${cs.classDetails?.className ?? 'class'}.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.classSubject;
    final rosterAsync = cs == null
        ? const AsyncValue.data(<StudentModel>[])
        : ref.watch(rosterProvider(cs.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Roster & Excel Import',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: AppColors.primary.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_upload_outlined,
                        size: 48, color: AppColors.primary),
                    const SizedBox(height: 8),
                    const Text(
                      'Upload Student Roster Spreadsheet',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Expected columns: PRN | Student Name | Email',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (cs != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Saving into ${cs.classDetails?.className ?? 'class'} • ${cs.subjectDetails?.subjectName ?? 'subject'}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.file_open),
                      label: Text(_fileName != null
                          ? 'File: $_fileName'
                          : 'Choose XLSX File'),
                      onPressed: _isProcessing ? null : _pickExcelFile,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_preview != null) ...[
              const Text('Import Preview',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_preview!.hasErrors) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _preview!.errorMessages
                        .map((err) => Text('• $err',
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 13)))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                        'Parsed ${_preview!.validStudents.length} valid student rows.',
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success),
                    onPressed: _isImporting ? null : _confirmImport,
                    child: Text(_isImporting ? 'Importing…' : 'Confirm Import'),
                  ),
                ],
              ),
              const Divider(height: 24),
            ],
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Enrolled Roster',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: rosterAsync.maybeWhen(
                    data: (list) => Text('(${list.length} Students)',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ),
                const Spacer(),
                if (cs != null)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Manual Add Student',
                    onPressed: () => _showManualAddDialog(context, cs),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rosterAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(e.toString())),
                data: (students) => students.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No students yet. Upload the Excel roster to enroll them.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final s = students[index];
                          final currentCs = cs;
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    AppColors.primary.withValues(alpha: 0.1),
                                child: Text(s.prn.length <= 3
                                    ? s.prn
                                    : s.prn.substring(s.prn.length - 3)),
                              ),
                              title: Text(s.studentName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  'PRN: ${s.prn} | Email: ${s.email.isNotEmpty ? s.email : 'N/A'}'),
                              trailing: currentCs == null
                                  ? null
                                  : IconButton(
                                      tooltip: 'Remove from this class',
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: AppColors.error),
                                      onPressed: () => _removeStudent(
                                        context,
                                        cs: currentCs,
                                        student: s,
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManualAddDialog(
      BuildContext context, ClassSubjectModel cs) async {
    final prnCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final teacherId = ref.read(teacherIdProvider);
    if (teacherId == null) return;

    String? errorText;
    final student = await showDialog<StudentModel>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Student Manually'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: prnCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'PRN Number', helperText: 'Required')),
                const SizedBox(height: 12),
                TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Student Full Name',
                        helperText: 'Required')),
                const SizedBox(height: 12),
                TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Student Email',
                      helperText:
                          'Optional, but needed for low-attendance alerts',
                    )),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final prn = prnCtrl.text.trim();
                final name = nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

                if (prn.isEmpty || name.isEmpty) {
                  setDialogState(() {
                    errorText = 'PRN and student name are required.';
                  });
                  return;
                }
                if (email.isNotEmpty && !emailPattern.hasMatch(email)) {
                  setDialogState(() {
                    errorText =
                        'Enter a valid email address, or leave it blank.';
                  });
                  return;
                }

                Navigator.pop(
                  ctx,
                  StudentModel(
                    id: '',
                    teacherId: teacherId,
                    prn: prn,
                    studentName: name,
                    email: email,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (student == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(databaseServiceProvider).bulkImportStudentsAndEnroll(
        teacherId: teacherId,
        classSubjectId: cs.id,
        students: [student],
      );
      ref.invalidate(rosterProvider(cs.id));
      ref.invalidate(classSubjectsProvider);
      ref.invalidate(teacherCountsProvider);
      ref.invalidate(teacherAttendanceDataProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(student.email.isEmpty
              ? 'Added ${student.studentName}. No email on file, so low-attendance emails will be skipped.'
              : 'Added ${student.studentName}.'),
          backgroundColor:
              student.email.isEmpty ? AppColors.warning : AppColors.success,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
            content: Text('Could not add student: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _removeStudent(
    BuildContext context, {
    required ClassSubjectModel cs,
    required StudentModel student,
  }) async {
    final className = cs.classDetails?.className ?? 'Class';
    final subjectName = cs.subjectDetails?.subjectName ?? 'Subject';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Student?'),
        content: Text(
          'Remove ${student.studentName} (PRN ${student.prn}) from '
          '$className • $subjectName?\n\n'
          'This only removes them from this class + subject. Their student '
          'record and past attendance history are kept.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(databaseServiceProvider).removeStudentFromClass(
            classSubjectId: cs.id,
            studentId: student.id,
          );
      ref.invalidate(rosterProvider(cs.id));
      ref.invalidate(classSubjectsProvider);
      ref.invalidate(teacherCountsProvider);
      ref.invalidate(teacherAttendanceDataProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Removed ${student.studentName} from $className.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not remove student: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
