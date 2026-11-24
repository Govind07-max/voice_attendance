import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors.dart';
import '../models/attendance_mark.dart';
import '../models/attendance_session.dart';
import '../models/class_subject.dart';
import '../models/student.dart';
import '../services/attendance_writer.dart';
import '../services/database_service.dart';
import 'database_provider.dart';
class AttendanceState {
  final String? classSubjectId;
  final AttendanceSessionModel? session;
  final Map<String, String> attendanceMap; // studentId -> present | absent
  final Map<String, String> sourceMap; // studentId -> voice | manual | default
  final List<StudentModel> roster;
  final bool isLoading;
  final bool isStarting;

  /// Periods already used today for this class + subject.
  final Set<int> usedPeriods;

  /// The period the teacher picked for the next lecture.
  final int selectedPeriod;

  /// Human readable error (never a raw exception).
  final String? error;

  const AttendanceState({
    this.classSubjectId,
    this.session,
    this.attendanceMap = const {},
    this.sourceMap = const {},
    this.roster = const [],
    this.isLoading = false,
    this.isStarting = false,
    this.usedPeriods = const {},
    this.selectedPeriod = 1,
    this.error,
  });

  bool get hasSession => session != null;
  bool get isCompleted => session?.status == 'completed';

  int get presentCount =>
      attendanceMap.values.where((v) => v == 'present').length;

  int get absentCount => roster.length - presentCount;

  /// The next free period for today.
  int get suggestedPeriod {
    for (var p = 1; p <= 8; p++) {
      if (!usedPeriods.contains(p)) return p;
    }
    return 1;
  }

  AttendanceState copyWith({
    String? classSubjectId,
    AttendanceSessionModel? session,
    Map<String, String>? attendanceMap,
    Map<String, String>? sourceMap,
    List<StudentModel>? roster,
    bool? isLoading,
    bool? isStarting,
    Set<int>? usedPeriods,
    int? selectedPeriod,
    String? error,
    bool clearError = false,
    bool clearSession = false,
  }) {
    return AttendanceState(
      classSubjectId: classSubjectId ?? this.classSubjectId,
      session: clearSession ? null : (session ?? this.session),
      attendanceMap: attendanceMap ?? this.attendanceMap,
      sourceMap: sourceMap ?? this.sourceMap,
      roster: roster ?? this.roster,
      isLoading: isLoading ?? this.isLoading,
      isStarting: isStarting ?? this.isStarting,
      usedPeriods: usedPeriods ?? this.usedPeriods,
      selectedPeriod: selectedPeriod ?? this.selectedPeriod,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owns the live lecture session: starts it, mirrors attendance locally for
/// instant UI, and persists every mark to Postgres.
class AttendanceController extends StateNotifier<AttendanceState> {
  final DatabaseService _db;
  final AttendanceWriter? _writer;
  /// Taken from the class + subject being marked (used for the edit audit).
  String? _teacherId;

  AttendanceController(this._db, {AttendanceWriter? writer})
      : _writer = writer,
        super(const AttendanceState());

  /// Loads the roster, today's periods, and resumes an in-progress lecture.
  Future<void> load(ClassSubjectModel classSubject) async {
    _teacherId = classSubject.teacherId;
    state = state.copyWith(
      classSubjectId: classSubject.id,
      isLoading: true,
      clearError: true,
    );

    try {
      final enrollments = await _db.getEnrollments(classSubject.id);
      final roster = enrollments
          .map((e) => e.student)
          .whereType<StudentModel>()
          .toList();

      final today = await _db.getSessionsForDate(
        classSubjectId: classSubject.id,
        date: DateTime.now(),
      );
      final usedPeriods = today.map((s) => s.periodNumber).toSet();

      final active = await _db.getActiveSessions(classSubject.id);
      if (active.isNotEmpty) {
        final session = active.first;
        final records = await _db.getAttendanceRecordsForSession(session.id);
        final map = <String, String>{};
        final sources = <String, String>{};
        for (final r in records) {
          map[r.studentId] = r.status;
          sources[r.studentId] = r.source;
        }
        state = state.copyWith(
          session: session,
          roster: roster,
          attendanceMap: map,
          sourceMap: sources,
          usedPeriods: usedPeriods,
          selectedPeriod: session.periodNumber,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          roster: roster,
          session: null,
          clearSession: true,
          attendanceMap: {},
          sourceMap: {},
          usedPeriods: usedPeriods,
          selectedPeriod: _nextFree(usedPeriods),
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: AppErrors.humanize(e),
      );
    }
  }

  int _nextFree(Set<int> used) {
    for (var p = 1; p <= 8; p++) {
      if (!used.contains(p)) return p;
    }
    return 1;
  }

  /// Picks the period for the next lecture.
  void selectPeriod(int period) {
    state = state.copyWith(selectedPeriod: period, clearError: true);
  }

  /// Rule 4: every enrolled student starts absent.
  Future<bool> startSession({DateTime? date, int? periodNumber}) async {
    final csId = state.classSubjectId;
    if (csId == null) return false;

    final period = periodNumber ?? state.selectedPeriod;
    state = state.copyWith(isStarting: true, clearError: true);
    try {
      final session = await _db.startAttendanceSession(
        classSubjectId: csId,
        date: date ?? DateTime.now(),
        periodNumber: period,
      );

      final map = <String, String>{};
      final sources = <String, String>{};
      for (final s in state.roster) {
        map[s.id] = 'absent';
        sources[s.id] = 'default';
      }

      state = state.copyWith(
        session: session,
        attendanceMap: map,
        sourceMap: sources,
        selectedPeriod: period,
        usedPeriods: {...state.usedPeriods, period},
        isStarting: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isStarting: false,
        error: AppErrors.humanize(e),
      );
      return false;
    }
  }

  /// Marks a student present or absent and persists it.
  ///
  /// The UI updates instantly; the write goes through [AttendanceWriter], which
  /// batches it and keeps it safely on disk if the network is down.
  ///
  /// Returns false when nothing changed (already in that state).
  Future<bool> markStatus(
    StudentModel student,
    String status, {
    required String source,
  }) async {
    final session = state.session;
    if (session == null || session.status == 'completed') return false;

    final currentStatus = state.attendanceMap[student.id];
    final currentSource = state.sourceMap[student.id];

    // Nothing to do: the status and how it was set are already identical.
    // (Rule 7: still only ever one record per student per session.)
    if (currentStatus == status && currentSource == source) {
      return false;
    }

    // Optimistic local update so the UI reacts instantly.
    state = state.copyWith(
      attendanceMap: {...state.attendanceMap, student.id: status},
      sourceMap: {...state.sourceMap, student.id: source},
      clearError: true,
    );

    final mark = AttendanceMark(
      sessionId: session.id,
      studentId: student.id,
      status: status,
      source: source,
      markedAt: DateTime.now(),
    );

    final writer = _writer;
    if (writer != null) {
      writer.enqueue(mark);
      // Audit trail is for teacher edits only, and must never block the mark.
      if (source == 'manual') {
        _logEdit(session.id, student.id, currentStatus, status, currentSource);
      }
      return true;
    }

    try {
      await _db.markStudentAttendance(
        sessionId: session.id,
        studentId: student.id,
        status: status,
        source: source,
      );
      if (source == 'manual') {
        _logEdit(session.id, student.id, currentStatus, status, currentSource);
      }
      return true;
    } catch (e) {
      // No offline queue available: restore exactly what was there before.
      final map = {...state.attendanceMap};
      if (currentStatus == null) {
        map.remove(student.id);
      } else {
        map[student.id] = currentStatus;
      }
      final sources = {...state.sourceMap};
      if (currentSource == null) {
        sources.remove(student.id);
      } else {
        sources[student.id] = currentSource;
      }
      state = state.copyWith(
        attendanceMap: map,
        sourceMap: sources,
        error: AppErrors.humanize(e),
      );
      return false;
    }
  }

  /// Fire-and-forget audit entry for a manual edit (never blocks the UI).
  void _logEdit(
    String sessionId,
    String studentId,
    String? oldStatus,
    String newStatus,
    String? oldSource,
  ) {
    final teacherId = _teacherId;
    if (teacherId == null) return;
    if (oldStatus == newStatus) return;

    _db
        .logAttendanceEdit(
          teacherId: teacherId,
          sessionId: sessionId,
          studentId: studentId,
          oldStatus: oldStatus,
          newStatus: newStatus,
          oldSource: oldSource,
          newSource: 'manual',
        )
        .catchError((Object e) {
      // The audit trail is best-effort; a failure must not affect attendance.
      return;
    });
  }

  /// Convenience wrapper for a present mark.
  Future<bool> markPresent(StudentModel student, {required String source}) {
    return markStatus(student, 'present', source: source);
  }

  /// Manual toggle (present <-> absent) from the review screen.
  Future<bool> setStatus(StudentModel student, String status) async {
    return markStatus(student, status, source: 'manual');
  }

  /// Marks the lecture complete.
  ///
  /// Refuses while marks are still waiting to sync, so a finalized lecture can
  /// never be missing attendance that the teacher already took.
  Future<bool> finalize() async {
    final session = state.session;
    if (session == null) return false;
    // Finalizing is idempotent: never re-complete (or re-share) a lecture that
    // is already closed.
    if (session.status == 'completed') return true;

    final writer = _writer;
    if (writer != null) {
      final synced = await writer.flush();
      if (!synced) {
        state = state.copyWith(
          error: '${writer.pendingCount} mark(s) are still waiting to sync. '
              'Connect to the internet, then finalize.',
        );
        return false;
      }
    }

    try {
      await _db.completeSession(session.id);
      state = state.copyWith(
        session: AttendanceSessionModel(
          id: session.id,
          classSubjectId: session.classSubjectId,
          lectureDate: session.lectureDate,
          periodNumber: session.periodNumber,
          startedAt: session.startedAt,
          endedAt: DateTime.now(),
          status: 'completed',
        ),
        clearError: true,
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: AppErrors.humanize(e));
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void reset() {
    state = const AttendanceState();
  }
}

final attendanceControllerProvider = StateNotifierProvider.autoDispose
    .family<AttendanceController, AttendanceState, String>((ref, classSubjectId) {
  final db = ref.watch(databaseServiceProvider);
  final writer = ref.read(attendanceWriterProvider.notifier);
  return AttendanceController(db, writer: writer);
});
