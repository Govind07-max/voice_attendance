/// One attendance write waiting to reach Postgres.
///
/// A mark is immutable so the offline queue can keep an exact copy on disk and
/// replay it later without ambiguity.
class AttendanceMark {
  final String sessionId;
  final String studentId;
  final String status; // 'present' | 'absent'
  final String source; // 'voice' | 'manual' | 'default'
  final DateTime markedAt;

  const AttendanceMark({
    required this.sessionId,
    required this.studentId,
    required this.status,
    required this.source,
    required this.markedAt,
  });

  /// One row per student per session — the queue de-duplicates on this key.
  String get key => '$sessionId|$studentId';

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'student_id': studentId,
        'status': status,
        'source': source,
        'marked_at': markedAt.toIso8601String(),
      };

  /// The shape stored on disk (keeps `sessionId` readable for the queue file).
  Map<String, dynamic> toStorageJson() => {
        'sessionId': sessionId,
        'studentId': studentId,
        'status': status,
        'source': source,
        'markedAt': markedAt.toIso8601String(),
      };

  factory AttendanceMark.fromStorageJson(Map<String, dynamic> json) {
    return AttendanceMark(
      sessionId: json['sessionId'] as String,
      studentId: json['studentId'] as String,
      status: json['status'] as String? ?? 'absent',
      source: json['source'] as String? ?? 'manual',
      markedAt: json['markedAt'] != null
          ? DateTime.parse(json['markedAt'] as String)
          : DateTime.now(),
    );
  }

  AttendanceMark copyWith({String? status, String? source, DateTime? markedAt}) {
    return AttendanceMark(
      sessionId: sessionId,
      studentId: studentId,
      status: status ?? this.status,
      source: source ?? this.source,
      markedAt: markedAt ?? this.markedAt,
    );
  }
}
