import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/student.dart';
import '../../services/excel_service.dart';

class StudentImportScreen extends StatefulWidget {
  const StudentImportScreen({super.key});

  @override
  State<StudentImportScreen> createState() => _StudentImportScreenState();
}

class _StudentImportScreenState extends State<StudentImportScreen> {
  final ExcelService _excelService = DefaultExcelService();
  String? _fileName;
  ExcelImportPreview? _preview;
  bool _isProcessing = false;

  // Demo student list if no file uploaded
  List<StudentModel> _students = [
    StudentModel(id: '1', teacherId: 't1', prn: '101', studentName: 'Rahul Patil', email: 'rahul.patil@univ.edu'),
    StudentModel(id: '2', teacherId: 't1', prn: '102', studentName: 'Sneha Sharma', email: 'sneha.sharma@univ.edu'),
    StudentModel(id: '3', teacherId: 't1', prn: '103', studentName: 'Amit Kumar', email: 'amit.kumar@univ.edu'),
    StudentModel(id: '4', teacherId: 't1', prn: '104', studentName: 'Rahul Patil', email: 'rahul.p104@univ.edu'), // Duplicate name demo
    StudentModel(id: '5', teacherId: 't1', prn: '105', studentName: 'Priya Verma', email: 'priya.v@univ.edu'),
  ];

  Future<void> _pickExcelFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _fileName = result.files.single.name;
          _isProcessing = true;
        });

        Uint8List bytes = result.files.single.bytes!;
        final preview = _excelService.parseStudentExcel(bytes, 't1');

        setState(() {
          _preview = preview;
          _isProcessing = false;
        });
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading Excel file: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  void _confirmImport() {
    if (_preview != null && _preview!.validStudents.isNotEmpty) {
      setState(() {
        _students = List.from(_preview!.validStudents);
        _preview = null;
        _fileName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully imported ${_students.length} students!'), backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Roster & Excel Import'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Upload Banner
            Card(
              color: AppColors.primary.withOpacity(0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 48, color: AppColors.primary),
                    const SizedBox(height: 8),
                    const Text(
                      'Upload Student Roster Spreadsheet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Expected columns: PRN | Student Name | Email',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.file_open),
                      label: Text(_fileName != null ? 'File: $_fileName' : 'Choose XLSX File'),
                      onPressed: _isProcessing ? null : _pickExcelFile,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // File Validation Preview Modal
            if (_preview != null) ...[
              const Text('Import Preview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_preview!.hasErrors) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _preview!.errorMessages
                        .map((err) => Text('• $err', style: const TextStyle(color: AppColors.error, fontSize: 13)))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Text('Parsed ${_preview!.validStudents.length} valid student rows.'),
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                    onPressed: _confirmImport,
                    child: const Text('Confirm Import'),
                  ),
                ],
              ),
              const Divider(height: 24),
            ],

            // Student Roster List
            Row(
              children: [
                Text(
                  'Enrolled Roster (${_students.length} Students)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Manual Add Student',
                  onPressed: () => _showManualAddDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _students.length,
                itemBuilder: (context, index) {
                  final s = _students[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        child: Text(s.prn.substring(s.prn.length > 3 ? s.prn.length - 3 : 0)),
                      ),
                      title: Text(s.studentName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('PRN: ${s.prn} | Email: ${s.email.isNotEmpty ? s.email : 'N/A'}'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualAddDialog(BuildContext context) {
    final prnCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Student Manually'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: prnCtrl, decoration: const InputDecoration(labelText: 'PRN Number')),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Student Full Name')),
            const SizedBox(height: 12),
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Student Email')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (prnCtrl.text.isNotEmpty && nameCtrl.text.isNotEmpty) {
                setState(() {
                  _students.add(StudentModel(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    teacherId: 't1',
                    prn: prnCtrl.text,
                    studentName: nameCtrl.text,
                    email: emailCtrl.text,
                  ));
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
