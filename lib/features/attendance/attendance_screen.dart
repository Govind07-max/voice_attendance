import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/student.dart';
import '../../services/matching_service.dart';
import '../../services/speech_service.dart';
import 'review_attendance_screen.dart';
import 'widgets/duplicate_match_dialog.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final SpeechService _speechService = FlutterSpeechService();
  final NameMatcher _nameMatcher = DefaultNameMatcher(fuzzyThreshold: 0.75);

  String _selectedClass = 'BE Computer A';
  String _selectedSubject = 'Ubiquitous Computing';
  bool _isSessionActive = false;
  bool _isListening = false;
  String _lastRecognizedText = '';
  String _lastStatusMessage = 'Tap the microphone and speak present student names.';

  // Master Roster for demo
  final List<StudentModel> _roster = [
    StudentModel(id: '1', teacherId: 't1', prn: '101', studentName: 'Rahul Patil', email: 'rahul101@univ.edu'),
    StudentModel(id: '2', teacherId: 't1', prn: '102', studentName: 'Sneha Sharma', email: 'sneha@univ.edu'),
    StudentModel(id: '3', teacherId: 't1', prn: '103', studentName: 'Amit Kumar', email: 'amit@univ.edu'),
    StudentModel(id: '4', teacherId: 't1', prn: '104', studentName: 'Rahul Patil', email: 'rahul104@univ.edu'), // Duplicate name
    StudentModel(id: '5', teacherId: 't1', prn: '105', studentName: 'Priya Verma', email: 'priya@univ.edu'),
  ];

  // Rule 4: Map studentId -> status ('present', 'absent')
  final Map<String, String> _attendanceMap = {};
  final Map<String, String> _sourceMap = {}; // 'voice', 'manual', 'default'

  void _startLectureSession() {
    setState(() {
      _isSessionActive = true;
      _attendanceMap.clear();
      _sourceMap.clear();
      // Rule 4: All enrolled students default to Absent
      for (var student in _roster) {
        _attendanceMap[student.id] = 'absent';
        _sourceMap[student.id] = 'default';
      }
      _lastStatusMessage = 'Lecture session started. Speak present student names.';
    });
  }

  void _toggleListening() async {
    if (!_isSessionActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please start an attendance session first!')),
      );
      return;
    }

    if (_isListening) {
      await _speechService.stopListening();
      setState(() => _isListening = false);
    } else {
      bool ok = await _speechService.initialize();
      if (!ok) {
        // Fallback for environment where speech_to_text hardware audio is unavailable
        _showManualSpeechSimDialog();
        return;
      }

      setState(() => _isListening = true);
      await _speechService.startListening(
        onResult: (recognizedText) {
          setState(() {
            _lastRecognizedText = recognizedText;
            _isListening = false;
          });
          _processSpokenText(recognizedText);
        },
      );
    }
  }

  void _processSpokenText(String text) {
    MatchResult result = _nameMatcher.match(text, _roster);

    if (result.type == MatchType.single && result.matchedStudent != null) {
      _markStudentPresent(result.matchedStudent!, source: 'voice');
    } else if (result.type == MatchType.multiple) {
      // Rule 5: Ambiguous names require teacher selection
      showDialog(
        context: context,
        builder: (_) => DuplicateMatchDialog(
          spokenName: text,
          candidateStudents: result.candidateStudents,
          onSelected: (student) => _markStudentPresent(student, source: 'voice'),
        ),
      );
    } else {
      // Rule 6: Unknown names are not marked
      setState(() {
        _lastStatusMessage = 'No match found for "$text". Please retry speaking or mark manually.';
      });
    }
  }

  void _markStudentPresent(StudentModel student, {required String source}) {
    // Rule 7: Prevent duplicate attendance
    if (_attendanceMap[student.id] == 'present') {
      setState(() {
        _lastStatusMessage = 'Student ${student.studentName} (PRN: ${student.prn}) is already marked present.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${student.studentName} (PRN: ${student.prn}) already marked present!'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _attendanceMap[student.id] = 'present';
      _sourceMap[student.id] = source;
      _lastStatusMessage = 'Marked PRESENT: ${student.studentName} (PRN: ${student.prn}) via $source.';
    });
  }

  void _showManualSpeechSimDialog() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voice Speech Simulation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter spoken student name (e.g. "Rahul Patil", "Sneha Sharma", "Amit"):'),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Spoken name...',
                prefixIcon: Icon(Icons.mic),
              ),
              onSubmitted: (val) {
                Navigator.pop(ctx);
                if (val.isNotEmpty) {
                  setState(() => _lastRecognizedText = val);
                  _processSpokenText(val);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (textCtrl.text.isNotEmpty) {
                setState(() => _lastRecognizedText = textCtrl.text);
                _processSpokenText(textCtrl.text);
              }
            },
            child: const Text('Simulate Voice Input'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int presentCount = _attendanceMap.values.where((v) => v == 'present').length;
    int absentCount = _roster.length - presentCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Attendance Session'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Class & Subject Selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Class', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          Text(_selectedClass, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Subject', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          Text(_selectedSubject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                    if (!_isSessionActive)
                      ElevatedButton(
                        onPressed: _startLectureSession,
                        child: const Text('Start'),
                      )
                    else
                      const Chip(label: Text('ACTIVE'), backgroundColor: Colors.greenAccent),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Live Counters Banner
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Column(
                      children: [
                        Text('$presentCount', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.success)),
                        const Text('PRESENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.success)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Column(
                      children: [
                        Text('$absentCount', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.error)),
                        const Text('ABSENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.error)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Microphone Button (Section 27 UI guidelines: microphone control must be prominent)
            GestureDetector(
              onTap: _toggleListening,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? AppColors.error : AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening ? AppColors.error : AppColors.primary).withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  size: 56,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isListening ? 'Listening... Speak student name' : 'Tap Microphone to Speak',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (_lastRecognizedText.isNotEmpty)
              Text(
                'Last recognized text: "$_lastRecognizedText"',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            const SizedBox(height: 4),
            Text(
              _lastStatusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),

            // Enrolled Students List & Status Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Enrolled Students', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Review & Finish'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReviewAttendanceScreen(
                          roster: _roster,
                          attendanceMap: _attendanceMap,
                          sourceMap: _sourceMap,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _roster.length,
              itemBuilder: (context, index) {
                final student = _roster[index];
                bool isPresent = _attendanceMap[student.id] == 'present';
                String source = _sourceMap[student.id] ?? 'default';

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isPresent ? AppColors.success.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                      child: Text(
                        student.prn.substring(student.prn.length > 3 ? student.prn.length - 3 : 0),
                        style: TextStyle(color: isPresent ? AppColors.success : Colors.grey, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(student.studentName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('PRN: ${student.prn} | Source: $source'),
                    trailing: ChoiceChip(
                      label: Text(isPresent ? 'PRESENT' : 'ABSENT'),
                      selected: isPresent,
                      selectedColor: AppColors.success,
                      labelStyle: TextStyle(color: isPresent ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                      onSelected: (val) {
                        setState(() {
                          _attendanceMap[student.id] = val ? 'present' : 'absent';
                          _sourceMap[student.id] = 'manual';
                        });
                      },
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
