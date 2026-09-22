import 'package:flutter/material.dart';
import '../../core/constants.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController(text: 'Prof. Govind Suryawanshi');
  final _facultyIdCtrl = TextEditingController(text: 'FAC-2026-09');
  final _deptCtrl = TextEditingController(text: 'Computer Engineering');
  final _emailCtrl = TextEditingController(text: 'govind@univ.edu');
  final _thresholdCtrl = TextEditingController(text: '75.0');

  // Teacher availability slots (Rule 16)
  final List<Map<String, String>> _availabilitySlots = [
    {'day': 'Monday', 'time': '02:00 PM - 04:00 PM'},
    {'day': 'Wednesday', 'time': '11:00 AM - 01:00 PM'},
    {'day': 'Friday', 'time': '03:00 PM - 05:00 PM'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Profile & Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Card Header
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.person, size: 36, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_nameCtrl.text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('${_deptCtrl.text} | ID: ${_facultyIdCtrl.text}', style: const TextStyle(color: AppColors.textSecondary)),
                          Text(_emailCtrl.text, style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Profile Edit Fields
            const Text('Personal Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 12),
            TextField(controller: _facultyIdCtrl, decoration: const InputDecoration(labelText: 'Faculty ID')),
            const SizedBox(height: 12),
            TextField(controller: _deptCtrl, decoration: const InputDecoration(labelText: 'Department')),
            const SizedBox(height: 12),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email Address')),
            const SizedBox(height: 20),

            // Default Threshold Setting (Rule 12)
            const Text('Default Attendance Threshold (%)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _thresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Default Threshold (%)',
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 24),

            // Teacher Availability Meeting Slots (Rule 16)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Available Meeting Slots', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _showAddSlotDialog(context),
                ),
              ],
            ),
            const Text(
              'Available slots are communicated in low-attendance warning emails.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: _availabilitySlots.map((slot) => ListTile(
                  leading: const Icon(Icons.access_time, color: AppColors.accent),
                  title: Text(slot['day']!),
                  subtitle: Text(slot['time']!),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: () {
                      setState(() => _availabilitySlots.remove(slot));
                    },
                  ),
                )).toList(),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile details updated successfully!')),
                  );
                },
                child: const Text('Save Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSlotDialog(BuildContext context) {
    String selectedDay = 'Monday';
    final timeCtrl = TextEditingController(text: '02:00 PM - 04:00 PM');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Meeting Availability Slot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedDay,
              items: const [
                DropdownMenuItem(value: 'Monday', child: Text('Monday')),
                DropdownMenuItem(value: 'Tuesday', child: Text('Tuesday')),
                DropdownMenuItem(value: 'Wednesday', child: Text('Wednesday')),
                DropdownMenuItem(value: 'Thursday', child: Text('Thursday')),
                DropdownMenuItem(value: 'Friday', child: Text('Friday')),
              ],
              onChanged: (val) {
                if (val != null) selectedDay = val;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: timeCtrl,
              decoration: const InputDecoration(labelText: 'Time Range (e.g. 02:00 PM - 04:00 PM)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _availabilitySlots.add({'day': selectedDay, 'time': timeCtrl.text});
              });
              Navigator.pop(ctx);
            },
            child: const Text('Add Slot'),
          ),
        ],
      ),
    );
  }
}
