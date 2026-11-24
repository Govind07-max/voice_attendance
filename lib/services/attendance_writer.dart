import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors.dart';
import '../models/attendance_mark.dart';
import '../providers/database_provider.dart';
import 'database_service.dart';

/// What the UI needs to know about the write pipeline.
class SyncState {
  final int pending;
  final bool syncing;
  final String? message;
  final bool hasError;

  const SyncState({
    this.pending = 0,
    this.syncing = false,
    this.message,
    this.hasError = false,
  });

  bool get isBusy => syncing || pending > 0;

  SyncState copyWith({
    int? pending,
    bool? syncing,
    String? message,
    bool? hasError,
    bool clearMessage = false,
  }) {
    return SyncState(
      pending: pending ?? this.pending,
      syncing: syncing ?? this.syncing,
      message: clearMessage ? null : (message ?? this.message),
      hasError: hasError ?? this.hasError,
    );
  }
}

/// Where pending marks are kept between app launches.
abstract class MarkStore {
  Future<List<AttendanceMark>> read();
  Future<void> write(List<AttendanceMark> marks);
}

/// Default store: a JSON blob in SharedPreferences (works on Android and web).
class SharedPrefsMarkStore implements MarkStore {
  static const String _key = 'pending_attendance_marks_v1';

  @override
  Future<List<AttendanceMark>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => AttendanceMark.fromStorageJson(
              Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[SYNC] could not read the offline queue: $e');
      return const [];
    }
  }

  @override
  Future<void> write(List<AttendanceMark> marks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (marks.isEmpty) {
        await prefs.remove(_key);
        return;
      }
      final encoded =
          jsonEncode(marks.map((m) => m.toStorageJson()).toList());
      await prefs.setString(_key, encoded);
    } catch (e) {
      debugPrint('[SYNC] could not persist the offline queue: $e');
    }
  }
}

/// Batches attendance writes and never loses a mark.
///
/// Every mark is applied to the UI instantly, queued here, and sent to Postgres
/// in a single upsert after a short debounce. If the network is down the queue
/// is written to disk and replayed automatically once the connection returns
/// (on the next mark, on retry, or every 20 seconds).
class AttendanceWriter extends StateNotifier<SyncState> {
  AttendanceWriter({
    required DatabaseService db,
    MarkStore? store,
    this.debounce = const Duration(milliseconds: 600),
  })  : _db = db,
        _store = store ?? SharedPrefsMarkStore(),
        super(const SyncState());

  final DatabaseService _db;
  final MarkStore _store;
  final Duration debounce;

  /// Latest mark per student per session — one row, never duplicates.
  final Map<String, AttendanceMark> _queue = {};

  Timer? _debounceTimer;
  Timer? _retryTimer;
  Future<bool>? _activeFlush;
  bool _disposed = false;
  bool _loaded = false;

  int get pendingCount => _queue.length;

  /// Loads whatever was saved on this device and immediately tries to sync.
  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final saved = await _store.read();
      for (final mark in saved) {
        _queue.putIfAbsent(mark.key, () => mark);
      }
      _emit();
      if (_queue.isNotEmpty) {
        unawaited(flush());
      }
    } catch (e) {
      debugPrint('[SYNC] queue init failed: $e');
    }
  }

  /// Adds (or replaces) a mark and schedules a batched write.
  void enqueue(AttendanceMark mark) {
    if (_disposed) return;
    // A newer mark for the same student always wins.
    _queue[mark.key] = mark;
    _emit();
    unawaited(_persist());

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(flush()));
  }

  /// Sends everything queued in one or more requests.
  ///
  /// Concurrent callers share the same drain, so finalizing while the
  /// debounced write is already in flight waits for it instead of falsely
  /// reporting that marks are unsaved.
  ///
  /// Returns true when the queue is empty afterwards and nothing failed.
  Future<bool> flush() {
    _debounceTimer?.cancel();
    final running = _activeFlush;
    if (running != null) return running;

    final future = _drainQueue();
    _activeFlush = future;
    return future.whenComplete(() {
      if (identical(_activeFlush, future)) _activeFlush = null;
    });
  }

  Future<bool> _drainQueue() async {
    if (_disposed) return _queue.isEmpty;
    if (_queue.isEmpty) {
      _emit();
      return true;
    }

    state = state.copyWith(syncing: true, clearMessage: true, hasError: false);

    try {
      while (!_disposed && _queue.isNotEmpty) {
        // A newer mark may have arrived while the previous request was in
        // flight, so take a fresh snapshot for every round.
        final batch = _queue.values.toList(growable: false);
        try {
          await _db.markAttendanceBatch(batch);
        } catch (e) {
          if (AppErrors.isTransient(e)) {
            // Keep everything; the next mark / retry / timer will send it.
            if (!_disposed) {
              state = SyncState(
                pending: _queue.length,
                message:
                    'Offline — ${_queue.length} mark(s) saved on this device '
                    'and will sync automatically.',
                hasError: false,
              );
            }
            _scheduleRetry();
            await _persist();
            return false;
          }

          // A permanent error would wedge the queue forever: drop just those
          // marks and tell the teacher what happened.
          _removeSent(batch);
          if (!_disposed) {
            state = SyncState(
              pending: _queue.length,
              message: AppErrors.humanize(e),
              hasError: true,
            );
          }
          await _persist();
          return false;
        }

        // Remove only the exact versions we sent — a newer mark may have
        // arrived while the request was in flight and must stay queued.
        _removeSent(batch);
        // Reflect the result immediately: a slow (or broken) disk must never
        // leave the UI stuck on "syncing".
        if (!_disposed) {
          state = _queue.isEmpty
              ? const SyncState()
              : state.copyWith(pending: _queue.length, syncing: true);
        }
        await _persist();
      }
      return _queue.isEmpty;
    } finally {
      if (!_disposed) {
        _emit(syncing: false);
      }
    }
  }

  void _removeSent(List<AttendanceMark> batch) {
    for (final sent in batch) {
      final current = _queue[sent.key];
      if (current != null && current.markedAt == sent.markedAt) {
        _queue.remove(sent.key);
      }
    }
  }

  /// Retries right now (the "Retry" button on the offline banner).
  Future<bool> retryNow() async {
    _retryTimer?.cancel();
    return flush();
  }

  /// Disk writes must never break attendance marking (a full disk, a missing
  /// plugin on web, etc.). The in-memory queue stays authoritative.
  Future<void> _persist() async {
    try {
      await _store.write(_queue.values.toList());
    } catch (e) {
      debugPrint('[SYNC] could not persist the queue: $e');
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_disposed) return;
    _retryTimer = Timer(const Duration(seconds: 20), () {
      if (!_disposed && _queue.isNotEmpty) {
        unawaited(flush());
      }
    });
  }

  void _emit({bool? syncing}) {
    if (_disposed) return;
    state = state.copyWith(
      pending: _queue.length,
      syncing: syncing ?? state.syncing,
    );
  }

  @override
  void dispose() {
    // Riverpod may dispose the notifier itself; never clean up twice.
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}

/// App-wide write pipeline (one queue for every lecture).
final attendanceWriterProvider =
    StateNotifierProvider<AttendanceWriter, SyncState>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final writer = AttendanceWriter(db: db);
  unawaited(writer.init());
  return writer;
});
