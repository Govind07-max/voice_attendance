import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/core/utils.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/services/matching_service.dart';

void main() {
  group('Voice Speech-to-Text & Name Matching System Verification', () {
    late DefaultNameMatcher nameMatcher;
    late List<StudentModel> enrolledRoster;

    setUp(() {
      nameMatcher = DefaultNameMatcher(fuzzyThreshold: 0.75);
      enrolledRoster = [
        StudentModel(id: 'st1', teacherId: 't1', prn: '101', studentName: 'Rahul Patil', email: 'rahul101@univ.edu'),
        StudentModel(id: 'st2', teacherId: 't1', prn: '102', studentName: 'Sneha Sharma', email: 'sneha@univ.edu'),
        StudentModel(id: 'st3', teacherId: 't1', prn: '103', studentName: 'Amit Kumar', email: 'amit@univ.edu'),
        StudentModel(id: 'st4', teacherId: 't1', prn: '104', studentName: 'Rahul Patil', email: 'rahul104@univ.edu'), // Duplicate name
        StudentModel(id: 'st5', teacherId: 't1', prn: '105', studentName: 'Priya Verma', email: 'priya@univ.edu'),
      ];
    });

    test('1. Speech Normalization cleans capitalization, extra spaces & punctuation', () {
      expect(AppUtils.normalizeName('  Rahul   Patil! '), equals('rahul patil'));
      expect(AppUtils.normalizeName('SNEHA, SHARMA.'), equals('sneha sharma'));
      expect(AppUtils.normalizeName('Amit-Kumar'), equals('amitkumar'));
    });

    test('2. Single Spoken Name Exact Match marks correct student', () {
      final result = nameMatcher.match('Sneha Sharma', enrolledRoster);
      expect(result.type, equals(MatchType.single));
      expect(result.matchedStudent?.prn, equals('102'));
      expect(result.matchedStudent?.studentName, equals('Sneha Sharma'));
      expect(result.confidenceScore, equals(1.0));
    });

    test('3. Partial Spoken First Name Exact Token Match (e.g., "Priya")', () {
      final result = nameMatcher.match('Priya', enrolledRoster);
      expect(result.type, equals(MatchType.single));
      expect(result.matchedStudent?.prn, equals('105'));
    });

    test('4. Rule 5 Ambiguity Handling: Spoken "Rahul Patil" detects multiple PRNs', () {
      final result = nameMatcher.match('Rahul Patil', enrolledRoster);
      expect(result.type, equals(MatchType.multiple));
      expect(result.candidateStudents.length, equals(2));
      final candidatePrns = result.candidateStudents.map((s) => s.prn).toList();
      expect(candidatePrns, containsAll(['101', '104']));
    });

    test('5. Safe Fuzzy Levenshtein Match handles speech recognition typos (e.g. "Sneha Shrama")', () {
      final result = nameMatcher.match('Sneha Shrama', enrolledRoster);
      expect(result.type, equals(MatchType.single));
      expect(result.matchedStudent?.prn, equals('102'));
      expect(result.confidenceScore, greaterThanOrEqualTo(0.75));
    });

    test('6. Rule 6 Protection: Unrecognized spoken text (e.g. "John Doe") returns MatchType.none', () {
      final result = nameMatcher.match('John Doe', enrolledRoster);
      expect(result.type, equals(MatchType.none));
      expect(result.matchedStudent, isNull);
    });

    test('7. Empty spoken string returns MatchType.none', () {
      final result = nameMatcher.match('', enrolledRoster);
      expect(result.type, equals(MatchType.none));
    });
  });
}
