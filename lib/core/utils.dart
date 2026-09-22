import 'package:intl/intl.dart';

class AppUtils {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _timeFormat = DateFormat('hh:mm a');
  static final DateFormat _isoFormat = DateFormat('yyyy-MM-dd');

  static String formatDate(DateTime date) => _dateFormat.format(date);
  static String formatTime(DateTime time) => _timeFormat.format(time);
  static String formatIsoDate(DateTime date) => _isoFormat.format(date);

  /// Normalizes spoken or imported names by converting to lowercase, 
  /// trimming extra spaces, and removing punctuation.
  static String normalizeName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '') // remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ') // consolidate whitespace
        .trim();
  }

  /// Levenshtein Distance for safe fuzzy matching between spoken name and student list
  static int levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1.codeUnitAt(i) == s2.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = [
          v1[j] + 1,
          v0[j + 1] + 1,
          v0[j] + cost
        ].reduce((a, b) => a < b ? a : b);
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[s2.length];
  }

  /// Normalized Similarity Score between 0.0 and 1.0
  static double similarityScore(String str1, String str2) {
    String s1 = normalizeName(str1);
    String s2 = normalizeName(str2);
    if (s1.isEmpty && s2.isEmpty) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    int distance = levenshteinDistance(s1, s2);
    int maxLength = s1.length > s2.length ? s1.length : s2.length;
    return 1.0 - (distance / maxLength);
  }
}
