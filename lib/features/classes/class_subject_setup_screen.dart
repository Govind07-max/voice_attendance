import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../students/student_import_screen.dart';

class ClassSubjectSetupScreen extends StatefulWidget {
  final String className;
  final String subjectName;

  const ClassSubjectSetupScreen({
    super.key,
    required this.className,
    required this.subjectName,
  });

  @override
  State<ClassSubjectSetupScreen> createState() => _ClassSubjectSetupScreenState();
}

class _ClassSubjectSetupScreenState extends State<ClassSubjectSetupScreen> {
  late TextEditingController _formUrlCtrl;
  late TextEditingController _thresholdCtrl;
  bool _alertEnabled = true;
  String _alertFrequency = 'weekly';
  int _reminderDays = 7;

  @override
  void initState() {
    super.initState();
    _formUrlCtrl = TextEditingController(text: 'https://forms.google.com/example-attendance-form');
    _thresholdCtrl = TextEditingController(text: '75.0');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.className} - Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.subjectName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                    Text('Class: ${widget.className}', style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Google Form Link Section (Rule 15)
            const Text('Google Form URL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'Used in low-attendance warning emails sent to students in this specific class + subject.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _formUrlCtrl,
              decoration: const InputDecoration(
                hintText: 'https://forms.google.com/...',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 20),

            // Attendance Threshold Section (Rule 12)
            const Text('Attendance Threshold (%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Students below this percentage trigger low-attendance alerts (Default: 75%).'),
            const SizedBox(height: 8),
            TextField(
              controller: _thresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '75.0',
                suffixText: '%',
                prefixIcon: Icon(Icons.tune),
              ),
            ),
            const SizedBox(height: 20),

            // Alert Settings Section (Rule 13 & 14)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('Enable Low-Attendance Email Alerts', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Automatically check and notify students below threshold'),
                      value: _alertEnabled,
                      onChanged: (val) => setState(() => _alertEnabled = val),
                      activeColor: AppColors.primary,
                    ),
                    if (_alertEnabled) ...[
                      const Divider(),
                      ListTile(
                        title: const Text('Alert Schedule Frequency'),
                        trailing: DropdownButton<String>(
                          value: _alertFrequency,
                          items: const [
                            DropdownMenuItem(value: 'daily', child: Text('Daily')),
                            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                            DropdownMenuItem(value: 'biweekly', child: Text('Bi-Weekly')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _alertFrequency = val);
                          },
                        ),
                      ),
                      ListTile(
                        title: const Text('Anti-Spam Reminder Interval'),
                        subtitle: Text('Do not re-email student within $_reminderDays days'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Student Roster Import Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                icon: const Icon(Icons.file_upload),
                label: const Text('Manage & Import Student Roster (Excel XLSX)'),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentImportScreen()));
                },
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Class-Subject settings saved successfully!')),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
