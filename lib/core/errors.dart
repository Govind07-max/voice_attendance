/// Turns raw backend exceptions into something a teacher can act on.
///
/// The app must never show a raw Postgres/PostgREST/Auth message.
class AppErrors {
  const AppErrors._();

  /// A friendly, actionable message for any error.
  static String humanize(Object error) {
    final raw = error.toString();
    final lowered = raw.toLowerCase();
    final code = _code(raw) ?? _sqlState(raw);

    // ---- Auth ----
    if (code == 'invalid_credentials' ||
        lowered.contains('invalid login credentials')) {
      return 'Wrong email or password. Please try again.';
    }
    if (code == 'email_not_confirmed' ||
        lowered.contains('email not confirmed')) {
      return 'Please confirm your email address before signing in.';
    }
    if (code == 'user_already_exists' ||
        lowered.contains('user already registered') ||
        lowered.contains('already been registered')) {
      return 'An account with this email already exists. Sign in instead.';
    }
    if (code == 'weak_password' || lowered.contains('password should be')) {
      return 'That password is too weak. Use at least 6 characters.';
    }
    if (lowered.contains('over_email_send_rate_limit') ||
        lowered.contains('email rate limit')) {
      return 'Too many emails were requested. Please wait a few minutes and '
          'try again.';
    }
    if (lowered.contains('unable to validate email address') ||
        lowered.contains('invalid email')) {
      return 'That email address does not look valid.';
    }
    if (code == 'signup_disabled' || lowered.contains('signups not allowed')) {
      return 'New sign-ups are currently disabled. Contact your administrator.';
    }

    // ---- Database ----
    switch (code) {
      // 23505 = unique_violation
      case '23505':
        if (raw.contains('unique_lecture')) {
          return 'A lecture already exists for this date and period. '
              'Choose a different period.';
        }
        if (raw.contains('unique_teacher_prn')) {
          return 'That PRN already belongs to another student.';
        }
        if (raw.contains('unique_class_subject')) {
          return 'This subject is already connected to this class.';
        }
        if (raw.contains('unique_session_student')) {
          return 'That student is already marked for this lecture.';
        }
        return 'That record already exists.';
      // 23503 = foreign_key_violation
      case '23503':
        return 'This record is still in use elsewhere, so it cannot be '
            'removed yet.';
      // 42501 = insufficient_privilege (RLS)
      case '42501':
        return 'You do not have access to this record.';
      // 22P02 = invalid_text_representation (bad uuid)
      case '22P02':
        return 'Your session has expired. Please sign in again.';
      // PGRST116 = no rows returned
      case 'PGRST116':
        return 'That record could not be found.';
    }

    // ---- Session / JWT ----
    if (raw.contains('PGRST301') ||
        lowered.contains('empty jwt') ||
        lowered.contains('jwt expired') ||
        lowered.contains('invalid jwt') ||
        lowered.contains('refresh token')) {
      return 'Your session has expired. Please sign in again.';
    }

    // ---- Network ----
    if (lowered.contains('socketexception') ||
        lowered.contains('failed host lookup') ||
        lowered.contains('network is unreachable') ||
        lowered.contains('connection refused') ||
        lowered.contains('clientexception') ||
        lowered.contains('connection closed')) {
      return 'No internet connection. Your marks are saved on this phone and '
          'will sync automatically.';
    }
    if (lowered.contains('timeoutexception') ||
        lowered.contains('timed out') ||
        lowered.contains('timeout')) {
      return 'The cloud is not responding. It may be waking up — please retry '
          'in a moment.';
    }
    if (lowered.contains('429') || lowered.contains('rate limit')) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    if (lowered.contains('500') ||
        lowered.contains('502') ||
        lowered.contains('503') ||
        lowered.contains('504')) {
      return 'The server had a problem. Please retry in a moment.';
    }

    // ---- Fallback: strip exception noise ----
    var message = raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('PostgrestException(message: ', '')
        .replaceFirst('AuthException(message: ', '')
        .replaceFirst('ClientException: ', '')
        .trim();
    if (message.length > 240) message = '${message.substring(0, 240)}…';
    if (message.isEmpty) {
      return 'Something went wrong. Please try again.';
    }
    return message;
  }

  /// True when the failure is temporary (no network, server waking up), so the
  /// app should keep the change locally and retry later.
  static bool isTransient(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('network is unreachable') ||
        raw.contains('connection refused') ||
        raw.contains('clientexception') ||
        raw.contains('connection closed') ||
        raw.contains('timeoutexception') ||
        raw.contains('timed out') ||
        raw.contains('timeout') ||
        raw.contains('429') ||
        raw.contains('rate limit') ||
        raw.contains('500') ||
        raw.contains('502') ||
        raw.contains('503') ||
        raw.contains('504');
  }

  /// True when the error means the teacher must sign in again.
  static bool isAuthExpired(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('jwt expired') ||
        raw.contains('invalid jwt') ||
        raw.contains('pgrst301') ||
        raw.contains('empty jwt') ||
        raw.contains('refresh token');
  }

  /// Pulls the PostgREST / Postgres / GoTrue error code out of the message.
  static String? _code(String raw) {
    final match = RegExp(r'"code"\s*:\s*"?(\w+)"?').firstMatch(raw);
    if (match != null) return match.group(1);

    final dartMatch = RegExp(r'\bcode:\s*"?(\w+)"?').firstMatch(raw);
    if (dartMatch != null) return dartMatch.group(1);

    return null;
  }

  /// Some callers wrap the error into a plain Exception and lose the `code:`
  /// field, but the SQLSTATE is usually still in the text.
  static String? _sqlState(String raw) {
    for (final state in const [
      '23505',
      '23503',
      '42501',
      '22P02',
      'PGRST301',
      'PGRST116',
    ]) {
      if (raw.contains(state)) return state;
    }
    return null;
  }
}
