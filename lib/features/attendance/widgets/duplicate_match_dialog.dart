import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../models/student.dart';

class DuplicateMatchDialog extends StatelessWidget {
  final String spokenName;
  final List<StudentModel> candidateStudents;
  final ValueChanged<StudentModel> onSelected;

  const DuplicateMatchDialog({
    super.key,
    required this.spokenName,
    required this.candidateStudents,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.help_outline, color: AppColors.warning),
          const SizedBox(width: 8),
          const Text('Multiple Students Found'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spoken name "$spokenName" matches multiple enrolled students. Please select the correct student PRN:',
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: candidateStudents.map((student) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        child: Text(
                          student.prn.substring(student.prn.length > 3 ? student.prn.length - 3 : 0),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(
                        student.studentName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('PRN: ${student.prn}'),
                      trailing: const Icon(Icons.check_circle_outline, color: AppColors.primary),
                      onTap: () {
                        Navigator.of(context).pop();
                        onSelected(student);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel / Retry'),
        ),
      ],
    );
  }
}
