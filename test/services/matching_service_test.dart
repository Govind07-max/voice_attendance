import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/services/matching_service.dart';

void main() {
  late DefaultNameMatcher matcher;
  late List<StudentModel> sampleStudents;

  setUp(() {
    matcher = DefaultNameMatcher(fuzzyThreshold: 0.75);
    sampleStudents = [
      StudentModel(id: '1', teacherId: 't1', prn: '101', studentName: 'Rahul Patil', email: 'rahul101@test.com'),
      StudentModel(id: '2', teacherId: 't1', prn: '102', studentName: 'Sneha Sharma', email: 'sneha@test.com'),
      StudentModel(id: '3', teacherId: 't1', prn: '103', studentName: 'Amit Kumar', email: 'amit@test.com'),
      StudentModel(id: '4', teacherId: 't1', prn: '104', studentName: 'Rahul Patil', email: 'rahul104@test.com'), // Duplicate name
    ];
  });

  test('Single exact match returns single match result', () {
    final result = matcher.match('Sneha Sharma', sampleStudents);
    expect(result.type, MatchType.single);
    expect(result.matchedStudent?.prn, '102');
  });

  test('Duplicate names (Rahul Patil) return multiple match candidates requiring PRN selection', () {
    final result = matcher.match('Rahul Patil', sampleStudents);
    expect(result.type, MatchType.multiple);
    expect(result.candidateStudents.length, 2);
    expect(result.candidateStudents.map((s) => s.prn), containsAll(['101', '104']));
  });

  test('Fuzzy name match (e.g. "Sneha Shrama" typo) resolves to Sneha Sharma', () {
    final result = matcher.match('Sneha Shrama', sampleStudents);
    expect(result.type, MatchType.single);
    expect(result.matchedStudent?.prn, '102');
  });

  test('Unknown name returns no match', () {
    final result = matcher.match('John Doe', sampleStudents);
    expect(result.type, MatchType.none);
  });

  test('a dropped middle name still matches', () {
    final roster = [
      StudentModel(
          id: '1', teacherId: 't1', prn: '101',
          studentName: 'Arnav Santosh Patil'),
    ];
    final result = matcher.match('Arnav Patil', roster);
    expect(result.type, MatchType.single);
    expect(result.matchedStudent?.studentName, 'Arnav Santosh Patil');
  });

  test('a spoken middle initial still matches', () {
    final roster = [
      StudentModel(
          id: '1', teacherId: 't1', prn: '101', studentName: 'Arnav Patil'),
    ];
    final result = matcher.match('Arnav P Patil', roster);
    expect(result.type, MatchType.single);
    expect(result.matchedStudent?.prn, '101');
  });
}
