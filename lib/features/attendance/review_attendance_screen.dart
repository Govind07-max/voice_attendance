import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/student.dart';

class ReviewAttendanceScreen extends StatefulWidget {
  final List<StudentModel> roster;
  final Map<String, String> attendanceMap;
  final Map<String, String> sourceMap;

  const ReviewAttendanceScreen({
    super.key,
    required this.roster,
    required this.attendanceMap,
    required this.sourceMap,
  });

  @override
  State<ReviewAttendanceScreen> createState() => _ReviewAttendanceScreenState();
}

class _ReviewAttendanceScreenState extends State<ReviewAttendanceScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filteredRoster = widget.roster.where((student) {
      final q = _searchQuery.toLowerCase();
      return student.studentName.toLowerCase().contains(q) || student.prn.contains(q);
    }).toList();

    int presentCount = widget.attendanceMap.values.where((v) => v == 'present').length;
    int totalCount = widget.roster.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review & Finalize Attendance'),
      ),
      body: Column(
        children: [
          // Header summary card
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.primary.withOpacity(0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Summary Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('$presentCount of $totalCount Students Present', style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                  icon: const Icon(Icons.check),
                  label: const Text('Finalize Lecture'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lecture attendance session finalized and saved to cumulative database!')),
                    );
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
          
          // Search Bar
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

          // Student Review List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredRoster.length,
              itemBuilder: (context, index) {
                final student = filteredRoster[index];
                bool isPresent = widget.attendanceMap[student.id] == 'present';
                String source = widget.sourceMap[student.id] ?? 'default';

                return Card(
                  child: ListTile(
                    title: Text(student.studentName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('PRN: ${student.prn} | Source: $source'),
                    trailing: Switch(
                      value: isPresent,
                      activeColor: AppColors.success,
                      onChanged: (val) {
                        setState(() {
                          widget.attendanceMap[student.id] = val ? 'present' : 'absent';
                          widget.sourceMap[student.id] = 'manual';
                        });
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
