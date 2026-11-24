import '../core/utils.dart';
import '../models/student.dart';
import 'matching_service.dart';

/// The status a teacher can state out loud.
enum VoiceStatus { present, absent }

/// A parsed voice instruction, e.g. "Aayush Nagras present".
class VoiceCommand {
  /// Exactly what the recogniser heard.
  final String rawText;

  /// The name left after the status keyword and filler words are removed.
  final String nameText;

  /// Set when the instruction is a number (a PRN, or part of a PRN).
  final String? digits;

  /// The stated status, or null when the teacher did not say present/absent.
  final VoiceStatus? status;

  const VoiceCommand({
    required this.rawText,
    required this.nameText,
    this.digits,
    this.status,
  });

  bool get hasStatus => status != null;

  @override
  String toString() =>
      'VoiceCommand("$rawText", name="$nameText", digits=$digits, status=$status)';
}

/// Turns a spoken phrase into a student + a status.
///
/// Supported shapes:
///   "Aayush Nagras present"  -> name + present
///   "Aayush Nagras absent"   -> name + absent
///   "Aayush Nagras"          -> name, no status (treated as absent)
///   "501 present"            -> PRN ending in 501 + present
///   "five zero one"          -> PRN ending in 001
class VoiceCommandParser {
  VoiceCommandParser({this.fuzzyThreshold = 0.75});

  final double fuzzyThreshold;

  /// Words that carry no information and are dropped before matching.
  static const Set<String> _fillerWords = {
    'is', 'are', 'am', 'he', 'she', 'it', 'this', 'that', 'the', 'a', 'an',
    'and', 'of', 'student', 'students', 'roll', 'rollno', 'number', 'no',
    'prn', 'id', 'ka', 'ki', 'ko', 'hai', 'ho', 'hain', 'nahi', 'mat',
    'mark', 'marks', 'marked', 'bhai', 'yaar', 'ji', 'please', 'to', 'for',
  };

  /// Word -> digit, for "five zero one" style instructions.
  static const Map<String, String> _digitWords = {
    'zero': '0', 'oh': '0', 'naught': '0',
    'one': '1', 'won': '1', 'two': '2', 'to': '2', 'too': '2',
    'three': '3', 'four': '4', 'for': '4', 'five': '5', 'six': '6',
    'seven': '7', 'eight': '8', 'ate': '8', 'nine': '9', 'nign': '9',
  };

  /// Consonant skeleton -> digit, so mis-spoken numbers still work.
  static const Map<String, String> _digitSkeletons = {
    'zr': '0', 'n': '1', 'wn': '1', 'tw': '2', 'thr': '3', 'fr': '4',
    'fv': '5', 'sx': '6', 'svn': '7', 'ght': '8', 'nn': '9',
  };

  /// Tens words -> value, so "twenty one" becomes 21.
  static const Map<String, int> _tensWords = {
    'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14,
    'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
    'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
    'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };

  /// Consonant skeleton -> tens value.
  static const Map<String, int> _tensSkeletons = {
    'tn': 10, 'lvn': 11, 'twlv': 12, 'thrtn': 13, 'frtn': 14, 'ftn': 15,
    'sxtn': 16, 'svntn': 17, 'ghtn': 18, 'ntn': 19, 'twnty': 20,
    'thrt': 30, 'frty': 40, 'fty': 50, 'sxty': 60, 'svnty': 70,
    'ghty': 80, 'nty': 90,
  };

  /// Consonant skeletons, so "preznt" is still recognised as "present".
  static const String _presentSkeleton = 'prsnt';
  static const String _absentSkeleton = 'bsnt';

  VoiceCommand parse(String utterance) {
    final raw = utterance.trim();
    return _parseTokens(_tokenize(raw), raw);
  }

  /// Parses one recogniser result into every complete instruction it contains.
  ///
  /// A dictation result can hold several names in one string
  /// ("Arnav Patil present Riya Kamble present"), and the web recogniser only
  /// ever emits interim results. Splitting on the status keywords lets the
  /// attendance screen apply each instruction as soon as it is complete,
  /// whether or not the platform ever calls it final.
  List<VoiceCommand> parseAll(String utterance) {
    final raw = utterance.trim();
    final tokens = _tokenize(raw);
    if (tokens.isEmpty) return const [];

    // Split after every clear status keyword. A fuzzy status-like word in the
    // middle ("Aayush Prashant Patil present") stays part of the name.
    final segments = <List<String>>[];
    var current = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      current.add(token);
      final isStatus = _statusForToken(token) != null;
      final canSplit =
          isStatus && (_isStrongStatusToken(token) || i == tokens.length - 1);
      if (canSplit) {
        segments.add(current);
        current = <String>[];
      }
    }
    if (current.isNotEmpty) segments.add(current);

    // A status-like word can also be the first part of a name ("Prasant").
    // When such a segment has no name of its own, fold it into the next one.
    final merged = <List<String>>[];
    var pending = <String>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = <String>[...pending, ...segments[i]];
      pending = <String>[];
      final hasName = segment.any((token) {
        final lowered = token.toLowerCase();
        return _statusForToken(token) == null &&
            !_fillerWords.contains(lowered);
      });
      if (!hasName && i < segments.length - 1) {
        pending = segment;
        continue;
      }
      merged.add(segment);
    }
    if (pending.isNotEmpty) merged.add(pending);

    final commands = <VoiceCommand>[];
    for (final segment in merged) {
      final command = _parseTokens(segment, segment.join(' '));
      // A lone "present" is not a student.
      if (command.nameText.isEmpty && command.digits == null) continue;
      commands.add(command);
    }
    return commands;
  }

  /// Parses one instruction. [tokens] are the words exactly as recognised,
  /// [raw] is what is shown back to the teacher.
  VoiceCommand _parseTokens(List<String> tokens, String raw) {
    if (tokens.isEmpty) {
      return VoiceCommand(rawText: raw.trim(), nameText: '');
    }
    final loweredTokens = tokens.map((t) => t.toLowerCase()).toList();

    // Only the LAST status keyword changes the status. A name such as
    // "Prasant Patil present" starts with a status-like word, but only the
    // trailing "present" is the instruction.
    //
    // A fuzzy status match ("Prashant" sounds like "present") is only trusted
    // when it is the last meaningful word. Otherwise it is a name.
    VoiceStatus? status;
    var statusIndex = -1;
    for (var i = 0; i < loweredTokens.length; i++) {
      final tokenStatus = _statusForToken(loweredTokens[i]);
      if (tokenStatus == null) continue;
      final isLastMeaningful = !_hasMeaningfulTokenAfter(loweredTokens, i);
      if (!isLastMeaningful && !_isStrongStatusToken(loweredTokens[i])) {
        continue;
      }
      status = tokenStatus;
      statusIndex = i;
    }

    // Keep every other word exactly as it was spoken, so the name still reads
    // nicely on screen.
    final keptIndexes = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      if (i == statusIndex) continue;
      if (loweredTokens[i].isEmpty) continue;
      keptIndexes.add(i);
    }

    // If stripping the keyword left nothing, the "keyword" was probably part
    // of a student name (e.g. a student called "Prasant") — keep it.
    if (keptIndexes.isEmpty && status != null) {
      keptIndexes.addAll(List<int>.generate(tokens.length, (i) => i));
      status = null;
    }

    // Drop filler words.
    final meaningfulIndexes = <int>[];
    for (final i in keptIndexes) {
      if (_fillerWords.contains(loweredTokens[i])) continue;
      meaningfulIndexes.add(i);
    }

    // Numbers -> PRN, otherwise -> name.
    final meaningfulTokens =
        meaningfulIndexes.map((i) => loweredTokens[i]).toList();
    final digitText = _extractDigits(meaningfulTokens);
    final nameText = digitText == null
        ? meaningfulIndexes.map((i) => tokens[i]).join(' ').trim()
        : '';

    return VoiceCommand(
      rawText: raw.trim(),
      nameText: nameText,
      digits: digitText,
      status: status,
    );
  }

  List<String> _tokenize(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    return trimmed.split(RegExp(r'\s+'));
  }

  /// The status keyword [token] represents, if any.
  VoiceStatus? _statusForToken(String token) {
    final skeleton = _skeleton(token);
    if (skeleton.isEmpty) return null;
    // "absent" is checked first: "present" and "absent" are acoustically
    // similar and the recogniser confuses them often.
    if (_matchesSkeleton(skeleton, _absentSkeleton)) return VoiceStatus.absent;
    if (_matchesSkeleton(skeleton, _presentSkeleton)) return VoiceStatus.present;
    return null;
  }

  /// True when [token] is unmistakably a status word (not a name that merely
  /// sounds like one, such as "Prashant").
  bool _isStrongStatusToken(String token) {
    final skeleton = _skeleton(token);
    return skeleton == _presentSkeleton ||
        skeleton.startsWith(_presentSkeleton) ||
        skeleton == _absentSkeleton ||
        skeleton.startsWith(_absentSkeleton);
  }

  bool _hasMeaningfulTokenAfter(List<String> tokens, int index) {
    for (var i = index + 1; i < tokens.length; i++) {
      if (!_fillerWords.contains(tokens[i].toLowerCase())) return true;
    }
    return false;
  }

  /// Resolves the command to a student, using the PRN suffix first when the
  /// teacher spoke a number, otherwise the name matcher.
  MatchResult resolve(VoiceCommand command, List<StudentModel> roster) {
    if (roster.isEmpty) return MatchResult.none();

    if (command.digits != null) {
      return _matchByPrn(command.digits!, roster);
    }

    if (command.nameText.isEmpty) return MatchResult.none();

    return DefaultNameMatcher(fuzzyThreshold: fuzzyThreshold)
        .match(command.nameText, roster);
  }

  /// Matches a spoken number against the PRNs.
  ///
  /// The teacher only needs the **last 3 digits**: "501" finds PRN 72145501.
  /// The spoken digits are left-padded with zeros, so "one" also finds "001".
  MatchResult _matchByPrn(String digits, List<StudentModel> roster) {
    final spoken = digits.replaceAll(RegExp(r'\D'), '');
    if (spoken.isEmpty) return MatchResult.none();

    // Compare only the digits, and pad short PRNs so that a roster value that
    // lost its leading zeros during Excel import ("1") still matches "001".
    String prnDigits(StudentModel student) =>
        student.prn.replaceAll(RegExp(r'\D'), '');

    // 1. Exact PRN.
    final exact =
        roster.where((s) => prnDigits(s) == spoken).toList();
    if (exact.length == 1) return MatchResult.single(exact.first, 1.0);
    if (exact.length > 1) return MatchResult.multiple(exact);

    // 2. Last three digits.
    final tail = spoken.length >= 3
        ? spoken.substring(spoken.length - 3)
        : spoken.padLeft(3, '0');
    final matches = roster.where((s) {
      final prn = prnDigits(s);
      if (prn.isEmpty) return false;
      return prn.padLeft(3, '0').endsWith(tail);
    }).toList();
    if (matches.length == 1) return MatchResult.single(matches.first, 0.95);
    if (matches.length > 1) return MatchResult.multiple(matches);

    return MatchResult.none();
  }

  /// Returns the spoken number as a digit string, or null if it is not a number.
  String? _extractDigits(List<String> tokens) {
    if (tokens.isEmpty) return null;

    final buffer = StringBuffer();
    var foundAny = false;

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final skeleton = _skeleton(token);

      // Plain digits, e.g. "501" or "7 2 1".
      if (RegExp(r'^\d+$').hasMatch(token)) {
        buffer.write(token);
        foundAny = true;
        continue;
      }

      // "double zero one" / "triple five" -> 001 / 555.
      final repeat = token == 'double'
          ? 2
          : token == 'triple'
              ? 3
              : 0;
      if (repeat > 0 && i + 1 < tokens.length) {
        final next = tokens[i + 1];
        final unit =
            _digitWords[next] ?? _digitSkeletons[_skeleton(next)];
        if (unit != null) {
          buffer.write(List.filled(repeat, unit).join());
          foundAny = true;
          i++;
          continue;
        }
      }

      final digit = _digitWords[token] ?? _digitSkeletons[skeleton];
      if (digit != null) {
        buffer.write(digit);
        foundAny = true;
        continue;
      }

      final tens = _tensWords[token] ?? _tensSkeletons[skeleton];
      if (tens != null) {
        // "twenty one" -> 21
        var value = tens;
        if (i + 1 < tokens.length) {
          final nextSkeleton = _skeleton(tokens[i + 1]);
          final unit = _digitWords[tokens[i + 1]] ??
              _digitSkeletons[nextSkeleton];
          if (unit != null) {
            value += int.parse(unit);
            i++;
          }
        }
        buffer.write(value.toString());
        foundAny = true;
        continue;
      }

      // Not a number at all.
      return null;
    }

    return foundAny ? buffer.toString() : null;
  }

  /// Removes vowels so recogniser spellings still line up.
  String _skeleton(String word) {
    return word
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z]'), '')
        .replaceAll(RegExp(r'[aeiou]'), '');
  }

  /// True when the skeleton equals the target or is within one edit of it.
  bool _matchesSkeleton(String skeleton, String target) {
    if (skeleton == target) return true;
    if (skeleton.startsWith(target)) return true; // "presents"
    // Do not fuzz short words: "sent" (snt) must not become "absent" (bsnt).
    if (skeleton.length < 4) return false;
    return AppUtils.levenshteinDistance(skeleton, target) <= 1;
  }
}
