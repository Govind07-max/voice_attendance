import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/models/attendance_mark.dart';
import 'package:voice_attendance/services/attendance_writer.dart';
import 'package:voice_attendance/services/database_service.dart';

/// Only the batch write is exercised; everything else is unused.
class FakeDb implements DatabaseService {
  final List<List<AttendanceMark>> batches = [];
  Object? error;

  @override
  Future<void> markAttendanceBatch(List<AttendanceMark> marks) async {
    if (error != null) throw error!;
    batches.add(List.of(marks));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class MemoryStore implements MarkStore {
  List<AttendanceMark> saved = [];

  @override
  Future<List<AttendanceMark>> read() async => List.of(saved);

  @override
  Future<void> write(List<AttendanceMark> marks) async {
    saved = List.of(marks);
  }
}

AttendanceMark mark(String studentId, String status,
    {String source = 'voice', DateTime? at}) {
  return AttendanceMark(
    sessionId: 'session-1',
    studentId: studentId,
    status: status,
    source: source,
    markedAt: at ?? DateTime.now(),
  );
}

void main() {
  group('AttendanceWriter', () {
    test('batches many rapid marks into one request', () async {
      final db = FakeDb();
      final store = MemoryStore();
      final writer = AttendanceWriter(
        db: db,
        store: store,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(writer.dispose);

      writer.enqueue(mark('s1', 'present'));
      writer.enqueue(mark('s2', 'present'));
      writer.enqueue(mark('s3', 'absent'));

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(db.batches.length, 1, reason: 'one round trip for the lecture');
      expect(db.batches.single.length, 3);
      expect(writer.pendingCount, 0);
      expect(writer.state.pending, 0);
      expect(store.saved, isEmpty);
    });

    test('a newer mark for the same student replaces the older one', () async {
      final db = FakeDb();
      final writer = AttendanceWriter(
        db: db,
        store: MemoryStore(),
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(writer.dispose);

      // The teacher says "present", then corrects to "absent".
      writer.enqueue(mark('s1', 'present'));
      writer.enqueue(mark('s1', 'absent'));

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(db.batches.length, 1);
      expect(db.batches.single.length, 1, reason: 'never two rows per student');
      expect(db.batches.single.single.status, 'absent');
    });

    test('keeps marks when offline, then replays them on retry', () async {
      final db = FakeDb()
        ..error = Exception('SocketException: Failed host lookup');
      final store = MemoryStore();
      final writer = AttendanceWriter(
        db: db,
        store: store,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(writer.dispose);

      writer.enqueue(mark('s1', 'present'));
      final firstFlush = await writer.flush();

      expect(firstFlush, isFalse);
      expect(writer.pendingCount, 1);
      expect(store.saved.length, 1, reason: 'saved on the device');
      expect(writer.state.message, contains('Offline'));
      expect(writer.state.hasError, isFalse);

      // Internet is back.
      db.error = null;
      final secondFlush = await writer.retryNow();

      expect(secondFlush, isTrue);
      expect(db.batches.length, 1);
      expect(db.batches.single.single.studentId, 's1');
      expect(writer.pendingCount, 0);
      expect(store.saved, isEmpty, reason: 'queue cleared after syncing');
      expect(writer.state.message, isNull);
    });

    test('replays a queue left over from a previous launch', () async {
      final store = MemoryStore()..saved = [mark('s9', 'present')];
      final db = FakeDb();
      final writer = AttendanceWriter(
        db: db,
        store: store,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(writer.dispose);

      await writer.init();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(db.batches.length, 1);
      expect(db.batches.single.single.studentId, 's9');
      expect(writer.pendingCount, 0);
    });

    test('drops a permanently rejected mark and shows a friendly reason',
        () async {
      final db = FakeDb()
        ..error = Exception(
            '23505 duplicate key value violates unique constraint "unique_lecture"');
      final writer = AttendanceWriter(
        db: db,
        store: MemoryStore(),
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(writer.dispose);

      writer.enqueue(mark('s1', 'present'));
      final synced = await writer.flush();

      expect(synced, isFalse);
      expect(writer.pendingCount, 0,
          reason: 'a poison mark must not wedge the queue');
      expect(writer.state.hasError, isTrue);
      expect(writer.state.message, contains('already exists'));
      expect(writer.state.message, isNot(contains('23505')));
    });

    test('flush reports false while marks are still waiting', () async {
      final db = FakeDb()
        ..error = Exception('TimeoutException: operation timed out');
      final writer = AttendanceWriter(
        db: db,
        store: MemoryStore(),
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(writer.dispose);

      writer.enqueue(mark('s1', 'present'));
      expect(await writer.flush(), isFalse);
      expect(writer.pendingCount, 1);
      // Finalize uses this to refuse closing a lecture with unsaved marks.
    });

    test('a second flush waits for the in-flight write instead of failing',
        () async {
      final db = _SlowDb();
      final writer = AttendanceWriter(
        db: db,
        store: MemoryStore(),
        // Do not let the debounce timer fire; this test controls flushing.
        debounce: const Duration(days: 1),
      );
      addTearDown(writer.dispose);

      writer.enqueue(mark('s1', 'present'));
      final firstFlush = writer.flush();
      await Future<void>.delayed(Duration.zero);
      final secondFlush = writer.flush();

      db.gate.complete();

      expect(await firstFlush, isTrue);
      expect(await secondFlush, isTrue,
          reason: 'finalize must not report unsaved marks while syncing');
      expect(db.calls, 1);
      expect(writer.pendingCount, 0);
    });

    test('survives a persistence failure without losing the mark', () async {
      final db = FakeDb();
      final writer = AttendanceWriter(
        db: db,
        store: _BrokenStore(),
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(writer.dispose);

      writer.enqueue(mark('s1', 'present'));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Disk failed, but the in-memory queue still reached Postgres.
      expect(db.batches.length, 1);
      expect(writer.pendingCount, 0);
    });
  });
}

class _SlowDb implements DatabaseService {
  final Completer<void> gate = Completer<void>();
  int calls = 0;

  @override
  Future<void> markAttendanceBatch(List<AttendanceMark> marks) async {
    calls++;
    await gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _BrokenStore implements MarkStore {
  @override
  Future<List<AttendanceMark>> read() async => [];

  @override
  Future<void> write(List<AttendanceMark> marks) async {
    throw Exception('disk full');
  }
}
