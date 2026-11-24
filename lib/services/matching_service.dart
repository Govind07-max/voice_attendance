import '../core/utils.dart';
import '../models/student.dart';

enum MatchType { single, multiple, none }

class MatchResult {
  final MatchType type;
  final StudentModel? matchedStudent;
  final List<StudentModel> candidateStudents;
  final double confidenceScore;

  MatchResult({
    required this.type,
    this.matchedStudent,
    this.candidateStudents = const [],
    this.confidenceScore = 0.0,
  });

  factory MatchResult.single(StudentModel student, double score) {
    return MatchResult(
      type: MatchType.single,
      matchedStudent: student,
      candidateStudents: [student],
      confidenceScore: score,
    );
  }

  factory MatchResult.multiple(List<StudentModel> candidates) {
    return MatchResult(
      type: MatchType.multiple,
      candidateStudents: candidates,
      confidenceScore: 0.8,
    );
  }

  factory MatchResult.none() {
    return MatchResult(
      type: MatchType.none,
    );
  }
}

abstract class NameMatcher {
  MatchResult match(String recognizedText, List<StudentModel> enrolledStudents);
}

class DefaultNameMatcher implements NameMatcher {
  final double fuzzyThreshold;

  DefaultNameMatcher({this.fuzzyThreshold = 0.75});

  @override
  MatchResult match(String recognizedText, List<StudentModel> enrolledStudents) {
    String query = AppUtils.normalizeName(recognizedText);
    if (query.isEmpty || enrolledStudents.isEmpty) {
      return MatchResult.none();
    }

    // Step 1: Exact Normalized Match
    List<StudentModel> exactMatches = enrolledStudents.where((student) {
      String studentNorm = AppUtils.normalizeName(student.studentName);
      return studentNorm == query;
    }).toList();

    if (exactMatches.length == 1) {
      return MatchResult.single(exactMatches.first, 1.0);
    } else if (exactMatches.length > 1) {
      // Rule 5: Ambiguous exact names require teacher PRN confirmation
      return MatchResult.multiple(exactMatches);
    }

    // Step 2: Partial/Tokens Exact Match (e.g. spoken "Rahul" matching "Rahul Patil")
    List<StudentModel> tokenMatches = enrolledStudents.where((student) {
      List<String> tokens = AppUtils.normalizeName(student.studentName).split(' ');
      return tokens.contains(query);
    }).toList();

    if (tokenMatches.length == 1) {
      return MatchResult.single(tokenMatches.first, 0.9);
    } else if (tokenMatches.length > 1) {
      return MatchResult.multiple(tokenMatches);
    }

    // Step 2b: Every spoken word appears in the student's name. This handles
    // names where the teacher drops a middle name ("Arnav Patil" ->
    // "Arnav Santosh Patil") and middle initials ("Arnav P Patil").
    final queryTokens =
        query.split(' ').where((token) => token.isNotEmpty).toList();
    if (queryTokens.length > 1) {
      List<StudentModel> subsetMatches = enrolledStudents.where((student) {
        final nameTokens = AppUtils.normalizeName(student.studentName)
            .split(' ')
            .where((token) => token.isNotEmpty)
            .toList();
        return queryTokens.every((queryToken) {
          if (queryToken.length == 1) {
            // A single letter is an initial: it may prefix any name word.
            return nameTokens.any((nameToken) => nameToken.startsWith(queryToken));
          }
          return nameTokens.contains(queryToken);
        });
      }).toList();

      if (subsetMatches.length == 1) {
        return MatchResult.single(subsetMatches.first, 0.88);
      } else if (subsetMatches.length > 1) {
        return MatchResult.multiple(subsetMatches);
      }
    }

    // Step 3: Safe Fuzzy Score Matching (Levenshtein)
    List<MapEntry<StudentModel, double>> scoredCandidates = [];
    for (var student in enrolledStudents) {
      double score = AppUtils.similarityScore(query, student.studentName);
      if (score >= fuzzyThreshold) {
        scoredCandidates.add(MapEntry(student, score));
      }
    }

    if (scoredCandidates.isEmpty) {
      return MatchResult.none();
    }

    // Sort candidates by highest score descending
    scoredCandidates.sort((a, b) => b.value.compareTo(a.value));

    double highestScore = scoredCandidates.first.value;
    // Find all candidates with score close to highest score (within 0.05 difference)
    List<StudentModel> topMatches = scoredCandidates
        .where((entry) => (highestScore - entry.value) <= 0.05)
        .map((entry) => entry.key)
        .toList();

    if (topMatches.length == 1) {
      return MatchResult.single(topMatches.first, highestScore);
    } else {
      return MatchResult.multiple(topMatches);
    }
  }
}
