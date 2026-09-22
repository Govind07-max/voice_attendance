import 'package:flutter/material.dart';
import '../../core/constants.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  // Demo list of students below 75% threshold (Rules 12, 13, 14, 15)
  final List<Map<String, dynamic>> _lowAttendanceStudents = [
    {
      'prn': '103',
      'name': 'Amit Kumar',
      'class': 'BE Computer A',
      'subject': 'Ubiquitous Computing',
      'percentage': 50.0,
      'attended': 2,
      'conducted': 4,
      'lastAlertSent': '22 Sep 2026, 09:00 AM',
      'alertState': 'Initial Sent',
    },
    {
      'prn': '104',
      'name': 'Rahul Patil',
      'class': 'BE Computer A',
      'subject': 'Ubiquitous Computing',
      'percentage': 25.0,
      'attended': 1,
      'conducted': 4,
      'lastAlertSent': '22 Sep 2026, 09:00 AM',
      'alertState': 'Initial Sent',
    },
  ];

  void _triggerScheduledCheck() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Triggered Apps Script low-attendance check. Emails queued with Google Form link & teacher slots.'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Low Attendance Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Run Scheduled Low-Attendance Check',
            onPressed: _triggerScheduledCheck,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alert Info Card
            Card(
              color: AppColors.warning.withOpacity(0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.warning),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications_active, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Text(
                          '${_lowAttendanceStudents.length} Students Below 75% Threshold',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Google Apps Script periodically emails these students with the class-specific Google Form link and teacher availability slots.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
                      icon: const Icon(Icons.send),
                      label: const Text('Run Alert Automation Now'),
                      onPressed: _triggerScheduledCheck,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            const Text('Flagged Low-Attendance Roster', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lowAttendanceStudents.length,
              itemBuilder: (context, index) {
                final student = _lowAttendanceStudents[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.error.withOpacity(0.1),
                              child: Text(
                                '${student['percentage'].toInt()}%',
                                style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    student['name'],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text('PRN: ${student['prn']} | ${student['class']}'),
                                ],
                              ),
                            ),
                            Chip(
                              label: Text('${student['percentage']}%'),
                              backgroundColor: AppColors.error.withOpacity(0.15),
                              labelStyle: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Attended: ${student['attended']} / ${student['conducted']} Lectures'),
                            Text('Status: ${student['alertState']}', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Last Alert Sent: ${student['lastAlertSent']}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
