import 'package:flutter/material.dart';
import '../../core/constants.dart';
import 'class_subject_setup_screen.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  // Demo class list
  final List<Map<String, String>> _classes = [
    {
      'name': 'BE Computer A',
      'year': '2026-2027',
      'semester': 'VIII',
      'subject': 'Ubiquitous Computing',
      'code': 'CS801',
    },
    {
      'name': 'BE Computer B',
      'year': '2026-2027',
      'semester': 'VIII',
      'subject': 'Ubiquitous Computing',
      'code': 'CS801',
    },
    {
      'name': 'TE Computer A',
      'year': '2026-2027',
      'semester': 'VI',
      'subject': 'Database Management Systems',
      'code': 'CS602',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classes & Subjects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddClassDialog(context),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _classes.length,
        itemBuilder: (context, index) {
          final item = _classes[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: const Icon(Icons.class_, color: AppColors.primary),
              ),
              title: Text(
                item['name']!,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('Subject: ${item['subject']} (${item['code']})'),
                  Text('Year: ${item['year']} | Sem: ${item['semester']}'),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClassSubjectSetupScreen(
                        className: item['name']!,
                        subjectName: item['subject']!,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('Add Class'),
        onPressed: () => _showAddClassDialog(context),
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
        title: const Text('Add New Class & Subject'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Class Name (e.g. BE Computer A)')),
              const SizedBox(height: 12),
              TextField(controller: yearCtrl, decoration: const InputDecoration(labelText: 'Academic Year')),
              const SizedBox(height: 12),
              TextField(controller: semCtrl, decoration: const InputDecoration(labelText: 'Semester')),
              const SizedBox(height: 12),
              TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: 'Subject Name')),
              const SizedBox(height: 12),
              TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Subject Code')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && subjectCtrl.text.isNotEmpty) {
                setState(() {
                  _classes.add({
                    'name': nameCtrl.text,
                    'year': yearCtrl.text,
                    'semester': semCtrl.text,
                    'subject': subjectCtrl.text,
                    'code': codeCtrl.text.isNotEmpty ? codeCtrl.text : 'CS101',
                  });
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
