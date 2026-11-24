import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../models/class_model.dart';
import '../../models/class_subject.dart';
import '../../models/subject.dart';
import '../../providers/classes_provider.dart';
import '../../providers/database_provider.dart';
import 'class_subject_setup_screen.dart';

class ClassesScreen extends ConsumerStatefulWidget {
  const ClassesScreen({super.key});

  @override
  ConsumerState<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends ConsumerState<ClassesScreen> {
  bool _isWorking = false;

  Future<void> _createClassAndSubject({
    required String className,
    required String year,
    required String semester,
    required String subjectName,
    required String subjectCode,
  }) async {
    final teacherId = ref.read(teacherIdProvider);
    if (teacherId == null) return;
    setState(() => _isWorking = true);

    try {
      final db = ref.read(databaseServiceProvider);

      final classModel = await db.createClass(ClassModel(
        id: '',
        teacherId: teacherId,
        className: className,
        academicYear: year,
        semester: semester,
      ));

      // Reuse an existing subject with the same code, otherwise create it.
      final subjects = await db.getSubjects(teacherId);
      SubjectModel subject;
      final existing =
          subjects.where((s) => s.subjectCode == subjectCode).firstOrNull;
      if (existing != null) {
        subject = existing;
      } else {
        subject = await db.createSubject(SubjectModel(
          id: '',
          teacherId: teacherId,
          subjectCode: subjectCode,
          subjectName: subjectName,
        ));
      }

      await db.createClassSubject(ClassSubjectModel(
        id: '',
        teacherId: teacherId,
        classId: classModel.id,
        subjectId: subject.id,
        classDetails: classModel,
        subjectDetails: subject,
      ));

      ref.invalidate(classesProvider);
      ref.invalidate(classSubjectsProvider);
      ref.invalidate(subjectsProvider);
      ref.invalidate(teacherCountsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created $className • $subjectName'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not create class: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classSubjectsAsync = ref.watch(classSubjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classes & Subjects',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add class',
            onPressed: _isWorking ? null : () => _showAddClassDialog(context),
          ),
        ],
      ),
      body: classSubjectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 48, color: AppColors.primary),
                const SizedBox(height: 12),
                Text(e.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.invalidate(classSubjectsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (classSubjects) {
          if (classSubjects.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.school_outlined,
                        size: 56, color: AppColors.primary),
                    const SizedBox(height: 14),
                    const Text('No classes yet',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'Create a class and connect a subject to start taking attendance.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Class'),
                      onPressed: () => _showAddClassDialog(context),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: classSubjects.length,
            itemBuilder: (context, index) {
              final cs = classSubjects[index];
              final className = cs.classDetails?.className ?? 'Class';
              final subjectName = cs.subjectDetails?.subjectName ?? 'Subject';
              final code = cs.subjectDetails?.subjectCode ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.class_rounded,
                          color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(className,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('Subject: $subjectName ($code)',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          Text(
                              'Year: ${cs.classDetails?.academicYear ?? '-'} | Sem: ${cs.classDetails?.semester ?? '-'}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          color: AppColors.textSecondary),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClassSubjectSetupScreen(
                              classSubject: cs,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('Add Class'),
        onPressed: _isWorking ? null : () => _showAddClassDialog(context),
      ),
    );
  }

  void _showAddClassDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final yearCtrl = TextEditingController(text: '2026-2027');
    final semCtrl = TextEditingController(text: 'VIII');
    final subjectCtrl = TextEditingController();
    final codeCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add New Class & Subject'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Class Name (e.g. BE E&TC A)')),
              const SizedBox(height: 12),
              TextField(
                  controller: yearCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Academic Year')),
              const SizedBox(height: 12),
              TextField(
                  controller: semCtrl,
                  decoration: const InputDecoration(labelText: 'Semester')),
              const SizedBox(height: 12),
              TextField(
                  controller: subjectCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Subject Name')),
              const SizedBox(height: 12),
              TextField(
                  controller: codeCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Subject Code')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final subject = subjectCtrl.text.trim();
              if (name.isEmpty || subject.isEmpty) return;
              Navigator.pop(ctx);
              _createClassAndSubject(
                className: name,
                year: yearCtrl.text.trim(),
                semester: semCtrl.text.trim(),
                subjectName: subject,
                subjectCode: codeCtrl.text.trim().isEmpty
                    ? 'EC101'
                    : codeCtrl.text.trim(),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
