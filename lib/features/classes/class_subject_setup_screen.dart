import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../models/class_subject.dart';
import '../../providers/classes_provider.dart';
import '../../providers/database_provider.dart';
import '../students/student_import_screen.dart';

class ClassSubjectSetupScreen extends ConsumerStatefulWidget {
  final ClassSubjectModel classSubject;

  const ClassSubjectSetupScreen({super.key, required this.classSubject});

  @override
  ConsumerState<ClassSubjectSetupScreen> createState() =>
      _ClassSubjectSetupScreenState();
}

class _ClassSubjectSetupScreenState
    extends ConsumerState<ClassSubjectSetupScreen> {
  late final TextEditingController _formUrlCtrl;
  late final TextEditingController _thresholdCtrl;
  late bool _alertEnabled;
  late String _alertFrequency;
  late TimeOfDay _alertTime;
  late int _weeklyDay;
  late int _intervalDays;
  late int _reminderDays;
  bool _isSaving = false;

  static const List<String> _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    final cs = widget.classSubject;
    _formUrlCtrl = TextEditingController(text: cs.googleFormUrl);
    _thresholdCtrl =
        TextEditingController(text: cs.thresholdPercent.toStringAsFixed(1));
    _alertEnabled = cs.alertEnabled;
    // Guard against values that are not in the dropdown lists, otherwise
    // Flutter throws "There should be exactly one item with the value".
    _alertFrequency =
        const ['daily', 'weekly', 'biweekly'].contains(cs.alertFrequency)
            ? cs.alertFrequency
            : 'weekly';
    _alertTime = _parseAlertTime(cs.alertTime);
    _weeklyDay = cs.weeklyDay >= 1 && cs.weeklyDay <= 7 ? cs.weeklyDay : 1;
    _intervalDays = _intervalForFrequency(_alertFrequency, cs.intervalDays);
    _reminderDays =
        const [3, 7, 14, 30].contains(cs.reminderDays) ? cs.reminderDays : 7;
  }

  @override
  void dispose() {
    _formUrlCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  static TimeOfDay _parseAlertTime(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.trim());
    if (match == null) return const TimeOfDay(hour: 9, minute: 0);
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || hour < 0 || hour > 23 || minute == null) {
      return const TimeOfDay(hour: 9, minute: 0);
    }
    if (minute < 0 || minute > 59) {
      return const TimeOfDay(hour: 9, minute: 0);
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _formatAlertTime(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  static int _intervalForFrequency(String frequency, int current) {
    if (frequency == 'daily') return 1;
    if (frequency == 'weekly') return 7;
    return const [14, 21, 28].contains(current) ? current : 14;
  }

  Future<void> _pickAlertTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _alertTime,
      helpText: 'Send low-attendance alerts at',
    );
    if (!mounted || picked == null) return;
    setState(() => _alertTime = picked);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  Future<void> _save() async {
    final formUrl = _formUrlCtrl.text.trim();
    final uri = formUrl.isEmpty ? null : Uri.tryParse(formUrl);
    if (formUrl.isNotEmpty &&
        (uri == null ||
            !uri.hasScheme ||
            !(uri.scheme == 'http' || uri.scheme == 'https') ||
            uri.host.isEmpty)) {
      _showError(
          'Enter a valid Google Form URL starting with http:// or https://.');
      return;
    }

    final threshold = double.tryParse(_thresholdCtrl.text.trim());
    if (threshold == null || threshold <= 0 || threshold > 100) {
      _showError(
          'Attendance threshold must be greater than 0 and at most 100.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updated = ClassSubjectModel(
        id: widget.classSubject.id,
        teacherId: widget.classSubject.teacherId,
        classId: widget.classSubject.classId,
        subjectId: widget.classSubject.subjectId,
        googleFormUrl: formUrl,
        thresholdPercent: threshold,
        alertEnabled: _alertEnabled,
        alertFrequency: _alertFrequency,
        alertTime: _formatAlertTime(_alertTime),
        weeklyDay: _weeklyDay,
        intervalDays: _intervalDays,
        reminderDays: _reminderDays,
        active: widget.classSubject.active,
        classDetails: widget.classSubject.classDetails,
        subjectDetails: widget.classSubject.subjectDetails,
      );

      await ref.read(databaseServiceProvider).updateClassSubject(updated);
      ref.invalidate(classSubjectsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Class-Subject settings saved!'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showError('Could not save settings: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.classSubject;
    final className = cs.classDetails?.className ?? 'Class';
    final subjectName = cs.subjectDetails?.subjectName ?? 'Subject';

    return Scaffold(
      appBar: AppBar(
        title: Text('$className - Settings',
            maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    Text(subjectName,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    Text('Class: $className',
                        style: const TextStyle(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Google Form Link Section (Rule 15)
            const Text('Google Form URL',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'Used in low-attendance warning emails sent to students in this specific class + subject.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _formUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://forms.google.com/...',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 20),

            // Attendance Threshold Section (Rule 12)
            const Text('Attendance Threshold (%)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
                'Students below this percentage trigger low-attendance alerts (Default: 75%).'),
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
                      title: const Text('Enable Low-Attendance Email Alerts',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                          'Automatically check and notify students below threshold'),
                      value: _alertEnabled,
                      onChanged: (val) => setState(() => _alertEnabled = val),
                      activeThumbColor: AppColors.primary,
                    ),
                    if (_alertEnabled) ...[
                      const Divider(),
                      ListTile(
                        title: const Text('Alert Schedule Frequency'),
                        trailing: DropdownButton<String>(
                          value: _alertFrequency,
                          items: const [
                            DropdownMenuItem(
                                value: 'daily', child: Text('Daily')),
                            DropdownMenuItem(
                                value: 'weekly', child: Text('Weekly')),
                            DropdownMenuItem(
                                value: 'biweekly', child: Text('Bi-Weekly')),
                          ],
                          onChanged: (val) {
                            if (val == null) return;
                            setState(() {
                              _alertFrequency = val;
                              _intervalDays =
                                  _intervalForFrequency(val, _intervalDays);
                            });
                          },
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: const Text('Send Alerts At'),
                        subtitle: Text(
                          MaterialLocalizations.of(context).formatTimeOfDay(
                            _alertTime,
                            alwaysUse24HourFormat:
                                MediaQuery.alwaysUse24HourFormatOf(context),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _pickAlertTime,
                      ),
                      if (_alertFrequency == 'weekly')
                        ListTile(
                          title: const Text('Day of Week'),
                          trailing: DropdownButton<int>(
                            value: _weeklyDay,
                            items: [
                              for (var day = 1; day <= 7; day++)
                                DropdownMenuItem(
                                  value: day,
                                  child: Text(_weekdayNames[day - 1]),
                                ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _weeklyDay = val);
                              }
                            },
                          ),
                        ),
                      if (_alertFrequency == 'biweekly')
                        ListTile(
                          title: const Text('Repeat Interval'),
                          trailing: DropdownButton<int>(
                            value: _intervalDays,
                            items: const [
                              DropdownMenuItem(
                                  value: 14, child: Text('Every 14 days')),
                              DropdownMenuItem(
                                  value: 21, child: Text('Every 21 days')),
                              DropdownMenuItem(
                                  value: 28, child: Text('Every 28 days')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _intervalDays = val);
                              }
                            },
                          ),
                        ),
                      ListTile(
                        title: const Text('Anti-Spam Reminder Interval'),
                        subtitle: Text(
                            'Do not re-email student within $_reminderDays days'),
                        trailing: DropdownButton<int>(
                          value: _reminderDays,
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('3 days')),
                            DropdownMenuItem(value: 7, child: Text('7 days')),
                            DropdownMenuItem(value: 14, child: Text('14 days')),
                            DropdownMenuItem(value: 30, child: Text('30 days')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _reminderDays = val);
                            }
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Text(
                          'The Google Apps Script checks every 15 minutes and '
                          'sends only when this schedule is due. Times use the '
                          'teacher timezone.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
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
                style:
                    OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                icon: const Icon(Icons.file_upload),
                label: const Text('Manage & Import Student Roster (Excel XLSX)',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentImportScreen(classSubject: cs),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style:
                    ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? 'Saving…' : 'Save Settings'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
