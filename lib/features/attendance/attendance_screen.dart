import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../models/class_subject.dart';
import '../../models/student.dart';
import '../../providers/attendance_controller.dart';
import '../../providers/classes_provider.dart';
import '../../services/attendance_writer.dart';
import '../../services/speech_service.dart';
import '../../services/matching_service.dart';
import '../../services/voice_command_service.dart';
import 'review_attendance_screen.dart';
import 'widgets/duplicate_match_dialog.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  @override
  Widget build(BuildContext context) {
    final classSubjectsAsync = ref.watch(classSubjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Attendance Session',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: classSubjectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _MessageState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load classes',
          message: e.toString(),
          onRetry: () => ref.invalidate(classSubjectsProvider),
        ),
        data: (classSubjects) {
          if (classSubjects.isEmpty) {
            return const _MessageState(
              icon: Icons.school_outlined,
              title: 'No class + subject yet',
              message:
                  'Go to the Classes tab, create a class and connect a subject. '
                  'Then import the student roster and start taking attendance.',
            );
          }
          return _ClassSubjectPicker(
            classSubjects: classSubjects,
            onSelected: (cs) {
              // Open the live lecture screen for this class + subject.
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _AttendanceSessionView(classSubject: cs),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Step 1 — pick the class + subject this lecture belongs to.
class _ClassSubjectPicker extends StatelessWidget {
  final List<ClassSubjectModel> classSubjects;
  final void Function(ClassSubjectModel) onSelected;

  const _ClassSubjectPicker({
    required this.classSubjects,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: classSubjects.length,
      itemBuilder: (context, index) {
        final cs = classSubjects[index];
        final className = cs.classDetails?.className ?? 'Class';
        final subjectName = cs.subjectDetails?.subjectName ?? 'Subject';
        final code = cs.subjectDetails?.subjectCode ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.record_voice_over,
                  color: AppColors.primary, size: 22),
            ),
            title: Text(subjectName,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '$className • $code • ${cs.thresholdPercent.toStringAsFixed(0)}% threshold',
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onSelected(cs),
          ),
        );
      },
    );
  }
}

/// Step 2 — the live lecture.
class _AttendanceSessionView extends ConsumerStatefulWidget {
  final ClassSubjectModel classSubject;
  const _AttendanceSessionView({required this.classSubject});

  @override
  ConsumerState<_AttendanceSessionView> createState() =>
      _AttendanceSessionViewState();
}

class _AttendanceSessionViewState extends ConsumerState<_AttendanceSessionView>
    with SingleTickerProviderStateMixin {
  final SpeechService _speechService = FlutterSpeechService();
  final VoiceCommandParser _commandParser = VoiceCommandParser();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isListening = false;
  bool _isStartingMic = false;
  bool _keepListening = false;
  bool _restartScheduled = false;
  bool _dialogOpen = false;
  Timer? _partialTimer;
  String? _pendingPartialText;
  final Set<String> _handledAmbiguities = {};
  String _lastRecognizedText = '';
  String _status = 'Tap Start, then tap the microphone and speak a name.';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(attendanceControllerProvider(widget.classSubject.id).notifier)
          .load(widget.classSubject);
    });
  }

  @override
  void dispose() {
    _keepListening = false;
    _partialTimer?.cancel();
    _speechService.stopListening();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    final provider = attendanceControllerProvider(widget.classSubject.id);
    final state = ref.read(provider);

    if (!state.hasSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please tap Start first!')),
      );
      return;
    }
    if (_isStartingMic) return;

    if (_isListening) {
      _flushPendingPartial();
      _keepListening = false;
      _partialTimer?.cancel();
      await _speechService.stopListening();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    _keepListening = true;
    _handledAmbiguities.clear();
    setState(() => _isStartingMic = true);
    final ok = await _speechService.initialize();
    if (!mounted) return;
    setState(() => _isStartingMic = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Microphone unavailable. Allow mic permission in App Settings, then tap the mic again.'),
          duration: Duration(seconds: 4),
        ),
      );
      setState(() {
        _status =
            'Mic blocked. Grant microphone permission and retry — no typing needed.';
      });
      return;
    }

    setState(() => _isListening = true);
    await _startListeningSession();
  }

  /// The student names, so the recogniser knows the vocabulary.
  List<String> _contextualPhrases() {
    final roster =
        ref.read(attendanceControllerProvider(widget.classSubject.id)).roster;
    return roster.map((s) => s.studentName).toList();
  }

  Future<void> _startListeningSession() async {
    try {
      await _speechService.startListening(
        onResult: _handleSpeechResult,
        onStatus: _handleSpeechStatus,
        contextualPhrases: _contextualPhrases(),
      );
    } catch (e) {
      debugPrint('[SPEECH] could not start listening: $e');
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _status = 'Microphone could not start. Tap the mic to try again.';
      });
    }
  }

  void _handleSpeechResult(String recognizedText, bool isFinal) {
    if (!mounted) return;
    setState(() {
      _lastRecognizedText = recognizedText;
      if (isFinal) _isListening = false;
    });

    _partialTimer?.cancel();
    if (isFinal) {
      _pendingPartialText = null;
      _processSpokenText(recognizedText, isFinal: true);
      _restartListeningIfNeeded();
      return;
    }

    // Some recognisers (notably the web one) only ever emit interim results.
    // A complete instruction ("... present") is safe to apply once the text
    // has settled. A bare partial name still never marks anybody.
    _pendingPartialText = recognizedText;
    _partialTimer = Timer(const Duration(milliseconds: 300), () {
      _flushPendingPartial();
    });
  }

  void _flushPendingPartial() {
    final pending = _pendingPartialText;
    if (pending == null) return;
    _pendingPartialText = null;
    _partialTimer?.cancel();
    if (!mounted) return;
    _processSpokenText(pending, isFinal: false);
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'notListening' ||
        status == 'done' ||
        status == 'doneNoResult') {
      // The recogniser may close without ever sending a final result (web).
      // Apply the last settled interim phrase before reopening the mic.
      _flushPendingPartial();
      if (_isListening) setState(() => _isListening = false);
      if (_keepListening) _restartListeningIfNeeded();
    }
  }

  /// Closes the microphone before handing the lecture to the review screen,
  /// so a phrase cannot be marked while the teacher is finalizing it.
  Future<void> _openReview() async {
    _flushPendingPartial();
    _keepListening = false;
    _partialTimer?.cancel();
    await _speechService.stopListening();
    if (!mounted) return;
    setState(() => _isListening = false);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewAttendanceScreen(
          classSubject: widget.classSubject,
          classSubjectId: widget.classSubject.id,
        ),
      ),
    );
  }

  /// Re-opens the microphone after a phrase was handled.
  Future<void> _restartListeningIfNeeded() async {
    if (!mounted || !_keepListening || _restartScheduled) return;
    _flushPendingPartial();
    _restartScheduled = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted || !_keepListening) return;
      if (_speechService.isListening) return;
      setState(() => _isListening = true);
      await _startListeningSession();
    } finally {
      _restartScheduled = false;
    }
  }

  /// Parses every complete instruction in a recogniser result and applies it.
  ///
  /// [isFinal] only controls one rule: a bare name without "present"/"absent"
  /// may default to absent once the platform says the phrase is complete. An
  /// interim fragment must never change a status by itself.
  void _processSpokenText(String text, {required bool isFinal}) {
    final provider = attendanceControllerProvider(widget.classSubject.id);
    final commands = _commandParser.parseAll(text);
    var handled = false;

    for (final command in commands) {
      if (command.status == null && !isFinal) continue;
      handled = true;

      // The status the teacher stated. Without the word "present" the student
      // is only ever marked absent.
      final status =
          command.status == VoiceStatus.present ? 'present' : 'absent';
      final spoken = command.rawText.isNotEmpty ? command.rawText : text;

      // Re-read before each command: a previous command may already have
      // changed the live map.
      final state = ref.read(provider);
      final result = _commandParser.resolve(command, state.roster);

      if (result.type == MatchType.single && result.matchedStudent != null) {
        final student = result.matchedStudent!;
        final alreadyApplied = state.attendanceMap[student.id] == status &&
            state.sourceMap[student.id] == 'voice';
        if (alreadyApplied) continue;

        if (mounted) {
          setState(() {
            _status = command.status == null
                ? '"$spoken" → ${student.studentName} marked ABSENT '
                    '(say "present" to change)'
                : '"$spoken" → ${student.studentName} ${status.toUpperCase()}';
          });
        }
        _markStatus(student, status, classSubjectId: widget.classSubject.id);
      } else if (result.type == MatchType.multiple) {
        _showDuplicateDialog(spoken, result, status);
      } else if (mounted) {
        setState(() {
          _status = command.digits != null
              ? 'No student with PRN ending in "${command.digits}".'
              : 'No match for "$spoken". Speak the name, or the last 3 digits '
                  'of the PRN, plus "present" or "absent".';
        });
      }
    }

    if (!handled && isFinal && mounted) {
      setState(() {
        _status = 'No match for "$text". Speak the name, or the last 3 digits '
            'of the PRN, plus "present" or "absent".';
      });
    }
  }

  void _showDuplicateDialog(String spoken, MatchResult result, String status) {
    final signature = '${spoken.toLowerCase()}|$status';
    // Interim results keep arriving for the same phrase; never stack dialogs.
    if (_dialogOpen || _handledAmbiguities.contains(signature)) return;
    if (!mounted) return;

    _dialogOpen = true;
    _handledAmbiguities.add(signature);
    showDialog<void>(
      context: context,
      builder: (_) => DuplicateMatchDialog(
        spokenName: spoken,
        candidateStudents: result.candidateStudents,
        onSelected: (student) => _markStatus(
          student,
          status,
          classSubjectId: widget.classSubject.id,
        ),
      ),
    ).whenComplete(() {
      _dialogOpen = false;
    });
  }

  Future<void> _markStatus(StudentModel student, String status,
      {required String classSubjectId}) async {
    final provider = attendanceControllerProvider(classSubjectId);
    final controller = ref.read(provider.notifier);
    final before = ref.read(provider).attendanceMap[student.id];

    final ok = await controller.markStatus(student, status, source: 'voice');
    if (!mounted) return;

    if (!ok && before == status) {
      setState(() {
        _status =
            '${student.studentName} (PRN: ${student.prn}) is already marked '
            '${status.toUpperCase()}.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${student.studentName} is already marked ${status.toUpperCase()}!'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = attendanceControllerProvider(widget.classSubject.id);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    if (state.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // A finalized lecture is read-only: never let a late microphone result
    // (or a stray tap) change a completed session.
    final canMark = state.hasSession && !state.isCompleted;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.classSubject.subjectDetails?.subjectName ?? 'Attendance',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (state.hasSession)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  'Period ${state.session?.periodNumber ?? 1}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _SessionHeader(
            classSubject: widget.classSubject,
            state: state,
            onStart: () => controller.startSession(),
            onPeriodChanged: (p) => controller.selectPeriod(p),
            onNewLecture: () => controller.load(widget.classSubject),
          ),
          _SyncBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              children: [
                if (state.error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(state.error!,
                              style: const TextStyle(
                                  color: AppColors.error, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            controller.clearError();
                            if (!state.hasSession) {
                              controller.startSession();
                            } else {
                              controller.load(widget.classSubject);
                            }
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                if (canMark) _buildMicArea(),
                if (state.hasSession) const SizedBox(height: 16),
                if (state.roster.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'No students enrolled in this class + subject yet.\n'
                      'Import the Excel roster from the Classes tab first.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ...state.roster.map((student) => _StudentRow(
                        student: student,
                        isPresent: state.attendanceMap[student.id] == 'present',
                        source: state.sourceMap[student.id] ?? 'default',
                        onToggle: canMark
                            ? (present) async {
                                await controller.setStatus(
                                    student, present ? 'present' : 'absent');
                              }
                            : null,
                      )),
                if (state.hasSession) const SizedBox(height: 16),
                if (state.hasSession)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: Icon(state.isCompleted
                          ? Icons.visibility_outlined
                          : Icons.check_circle_outline),
                      label: Text(state.isCompleted
                          ? 'View Finalized Lecture'
                          : 'Review & Finalize Lecture'),
                      onPressed: _openReview,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicArea() {
    return Column(
      children: [
        ScaleTransition(
          scale: _isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
          child: GestureDetector(
            onTap: _isStartingMic ? null : _toggleListening,
            child: Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _isListening
                      ? [AppColors.error, const Color(0xFFDC2626)]
                      : [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isListening ? AppColors.error : AppColors.primary)
                        .withValues(alpha: 0.4),
                    blurRadius: 24,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Icon(
                _isStartingMic
                    ? Icons.hourglass_empty_rounded
                    : (_isListening ? Icons.mic : Icons.mic_none_rounded),
                size: 58,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _isStartingMic
              ? 'Requesting mic permission...'
              : (_isListening
                  ? 'Listening... Speak student name'
                  : 'Tap Microphone to Speak'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        if (_lastRecognizedText.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Last recognized: "$_lastRecognizedText"',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark),
            ),
          ),
        Text(_status,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _SessionHeader extends ConsumerWidget {
  final ClassSubjectModel classSubject;
  final AttendanceState state;
  final VoidCallback onStart;
  final ValueChanged<int> onPeriodChanged;
  final VoidCallback onNewLecture;

  const _SessionHeader({
    required this.classSubject,
    required this.state,
    required this.onStart,
    required this.onPeriodChanged,
    required this.onNewLecture,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final className = classSubject.classDetails?.className ?? 'Class';
    final subjectName = classSubject.subjectDetails?.subjectName ?? 'Subject';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.school_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subjectName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    Text(
                        'Class: $className • ${state.roster.length} enrolled',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!state.hasSession)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PeriodPicker(
                      selected: state.selectedPeriod,
                      used: state.usedPeriods,
                      onChanged: onPeriodChanged,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: state.isStarting ? null : onStart,
                      child: Text(state.isStarting ? '...' : 'Start'),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.success),
                      ),
                      child: Text(state.isCompleted ? 'DONE' : 'ACTIVE',
                          style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 11)),
                    ),
                    if (state.isCompleted) ...[
                      const SizedBox(width: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onNewLecture,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label:
                            const Text('New', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Counter(
                  value: '${state.presentCount}',
                  label: 'PRESENT',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Counter(
                  value: '${state.absentCount}',
                  label: 'ABSENT',
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lets the teacher pick which period of the day this lecture is.
class _PeriodPicker extends StatelessWidget {
  final int selected;
  final Set<int> used;
  final ValueChanged<int> onChanged;

  const _PeriodPicker({
    required this.selected,
    required this.used,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('P',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark)),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selected,
              isDense: true,
              padding: EdgeInsets.zero,
              iconSize: 18,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark),
              items: [
                for (var p = 1; p <= 8; p++)
                  DropdownMenuItem(
                    value: p,
                    child: Text(
                      used.contains(p) ? '$p ✓' : '$p',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: used.contains(p)
                            ? AppColors.textSecondary
                            : AppColors.primaryDark,
                      ),
                    ),
                  ),
              ],
              onChanged: (p) {
                if (p != null) onChanged(p);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {  final String value;
  final String label;
  final Color color;
  const _Counter({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  final StudentModel student;
  final bool isPresent;
  final String source;
  final void Function(bool present)? onToggle;

  const _StudentRow({
    required this.student,
    required this.isPresent,
    required this.source,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isPresent
                ? AppColors.success.withValues(alpha: 0.3)
                : AppColors.borderLight),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isPresent
                ? AppColors.success.withValues(alpha: 0.15)
                : AppColors.borderLight,
            child: Text(
              student.prn.length <= 3
                  ? student.prn
                  : student.prn.substring(student.prn.length - 3),
              style: TextStyle(
                  color: isPresent
                      ? AppColors.success
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.studentName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text('PRN: ${student.prn} | ${source.toUpperCase()}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(isPresent ? 'PRESENT' : 'ABSENT'),
            selected: isPresent,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            selectedColor: AppColors.success,
            labelStyle: TextStyle(
                color: isPresent ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 11),
            onSelected: onToggle == null ? null : (val) => onToggle!(val),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown while marks are queued or the phone is offline.
///
/// Marks are never lost: they sit on the device and sync automatically once the
/// connection is back. The banner is the teacher's proof that nothing vanished.
class _SyncBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(attendanceWriterProvider);
    if (sync.pending == 0 && !sync.syncing && !sync.hasError) {
      return const SizedBox.shrink();
    }

    final isError = sync.hasError;
    final color = isError
        ? AppColors.error
        : sync.pending > 0
            ? AppColors.warning
            : AppColors.success;

    final label = sync.message ??
        (sync.syncing
            ? 'Syncing attendance…'
            : '${sync.pending} mark(s) waiting to sync.');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline
                : sync.syncing
                    ? Icons.sync
                    : Icons.cloud_off_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: color),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (sync.pending > 0)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: color,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: sync.syncing
                  ? null
                  : () => ref.read(attendanceWriterProvider.notifier).retryNow(),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
