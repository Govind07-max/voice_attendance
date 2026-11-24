import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/services/voice_command_service.dart';

List<StudentModel> roster() => [
      StudentModel(
          id: 's1', teacherId: 't1', prn: '72145001', studentName: 'Aayush Nagras'),
      StudentModel(
          id: 's2', teacherId: 't1', prn: '72145002', studentName: 'Riya Kamble'),
      StudentModel(
          id: 's3', teacherId: 't1', prn: '72145003', studentName: 'Sumit Bhosale'),
      StudentModel(
          id: 's4', teacherId: 't1', prn: '72145010', studentName: 'Pooja Chavan'),
      // Two students whose PRNs share the same last 3 digits ("501").
      StudentModel(
          id: 's5', teacherId: 't1', prn: '72145501', studentName: 'Amit Verma'),
      StudentModel(
          id: 's6', teacherId: 't1', prn: '72146501', studentName: 'Kiran Salunkhe'),
    ];

void main() {
  final parser = VoiceCommandParser();
  final students = roster();

  group('status keyword detection', () {
    test('"name present" -> present', () {
      final cmd = parser.parse('Aayush Nagras present');
      expect(cmd.status, VoiceStatus.present);
      expect(cmd.nameText, 'Aayush Nagras');
    });

    test('"name absent" -> absent', () {
      final cmd = parser.parse('Riya Kamble absent');
      expect(cmd.status, VoiceStatus.absent);
      expect(cmd.nameText, 'Riya Kamble');
    });

    test('no keyword -> status is null', () {
      final cmd = parser.parse('Aayush Nagras');
      expect(cmd.status, isNull);
      expect(cmd.nameText, 'Aayush Nagras');
    });

    test('tolerates recogniser spellings', () {
      expect(parser.parse('Aayush Nagras preznt').status, VoiceStatus.present);
      expect(parser.parse('Aayush Nagras prsent').status, VoiceStatus.present);
      expect(parser.parse('Aayush Nagras absnt').status, VoiceStatus.absent);
    });

    test('handles classroom phrasing', () {
      expect(parser.parse('Aayush Nagras is present').status,
          VoiceStatus.present);
      expect(parser.parse('Aayush Nagras present hai').status,
          VoiceStatus.present);
      expect(parser.parse('Aayush Nagras is absent').status, VoiceStatus.absent);
    });

    test('"absent" is checked before "present" (they sound alike)', () {
      expect(parser.parse('Aayush absent').status, VoiceStatus.absent);
    });

    test('strips filler words', () {
      final cmd = parser.parse('roll number 501 student is present');
      expect(cmd.digits, '501');
      expect(cmd.status, VoiceStatus.present);
    });

    test('a student name that contains a keyword word is not stripped away', () {
      // "Prasant" alone must not be read as the word "present".
      final cmd = parser.parse('Prasant');
      expect(cmd.status, isNull);
      expect(cmd.nameText, 'Prasant');
    });
  });

  group('name resolution', () {
    test('"Aayush Nagras present" resolves to the student', () {
      final cmd = parser.parse('Aayush Nagras present');
      final result = parser.resolve(cmd, students);
      expect(result.type.name, 'single');
      expect(result.matchedStudent!.studentName, 'Aayush Nagras');
    });

    test('a fuzzy name still matches', () {
      final cmd = parser.parse('Aayush Nagras present');
      final result = parser.resolve(cmd, students);
      expect(result.matchedStudent!.prn, '72145001');
    });

    test('an unknown name resolves to nothing', () {
      final cmd = parser.parse('John Doe present');
      final result = parser.resolve(cmd, students);
      expect(result.type.name, 'none');
    });

    test('duplicate names need a PRN choice', () {
      final dupes = [
        StudentModel(id: 'a', teacherId: 't1', prn: '1', studentName: 'Rahul Patil'),
        StudentModel(id: 'b', teacherId: 't1', prn: '2', studentName: 'Rahul Patil'),
      ];
      final cmd = parser.parse('Rahul Patil present');
      final result = parser.resolve(cmd, dupes);
      expect(result.type.name, 'multiple');
      expect(result.candidateStudents.length, 2);
    });
  });

  group('PRN by the last 3 digits', () {
    test('spoken digits match the PRN suffix', () {
      // "002" is unique -> Sumit/Riya's PRN 72145002
      final cmd = parser.parse('002 present');
      final result = parser.resolve(cmd, students);
      expect(result.type.name, 'single');
      expect(result.matchedStudent!.studentName, 'Riya Kamble');
    });

    test('a single spoken digit is zero padded', () {
      // "one" -> "1" -> padded to "001" -> unique
      final cmd = parser.parse('one present');
      final result = parser.resolve(cmd, students);
      expect(result.type.name, 'single');
      expect(result.matchedStudent!.studentName, 'Aayush Nagras');
    });

    test('"one zero" -> 010', () {
      final cmd = parser.parse('one zero present');
      final result = parser.resolve(cmd, students);
      expect(result.type.name, 'single');
      expect(result.matchedStudent!.studentName, 'Pooja Chavan');
    });

    test('number words are understood', () {
      final cmd = parser.parse('five zero one present');
      expect(cmd.digits, '501');
      final result = parser.resolve(cmd, students);
      // Two students end with 501 -> the teacher must pick one.
      expect(result.type.name, 'multiple');
      expect(result.candidateStudents.length, 2);
    });

    test('a shared suffix asks the teacher to choose', () {
      final cmd = parser.parse('501 present');
      final result = parser.resolve(cmd, students);
      expect(result.type.name, 'multiple');
      expect(result.candidateStudents.length, 2);
    });

    test('the full PRN is matched exactly', () {
      final cmd = parser.parse('72145002 present');
      final result = parser.resolve(cmd, students);
      expect(result.type.name, 'single');
      expect(result.matchedStudent!.studentName, 'Riya Kamble');
    });

    test('an unknown number matches nothing', () {
      final cmd = parser.parse('999 present');
      final result = parser.resolve(cmd, students);
      expect(result.type.name, 'none');
    });

    test('a number with a status of absent works too', () {
      final cmd = parser.parse('002 absent');
      expect(cmd.status, VoiceStatus.absent);
      expect(cmd.digits, '002');
    });
  });

  group('cumulative dictation / interim results', () {
    test('one result with several instructions is split into commands', () {
      final commands =
          parser.parseAll('Aayush Nagras present Riya Kamble present');
      expect(commands.length, 2);
      expect(commands[0].nameText, 'Aayush Nagras');
      expect(commands[0].status, VoiceStatus.present);
      expect(commands[1].nameText, 'Riya Kamble');
      expect(commands[1].status, VoiceStatus.present);
    });

    test('several PRNs in one result are split too', () {
      final commands = parser.parseAll('002 present 001 present');
      expect(commands.length, 2);
      expect(commands[0].digits, '002');
      expect(commands[1].digits, '001');
    });

    test('a name that starts with a status-like word stays intact', () {
      final cmd = parser.parse('Prasant Patil present');
      expect(cmd.status, VoiceStatus.present);
      expect(cmd.nameText, 'Prasant Patil');
    });

    test('a fuzzy status-sounding name without "present" is a name', () {
      final cmd = parser.parse('Prashant Patil');
      expect(cmd.status, isNull);
      expect(cmd.nameText, 'Prashant Patil');
    });

    test('a status-sounding middle name is not split out of the command', () {
      final commands = parser.parseAll('Aayush Prashant Patil present');
      expect(commands.length, 1);
      expect(commands.single.nameText, 'Aayush Prashant Patil');
      expect(commands.single.status, VoiceStatus.present);
    });

    test('"pre sent" is not mistaken for absent', () {
      expect(parser.parse('Aayush Nagras pre sent').status, isNull);
    });

    test('"double zero one" is understood as 001', () {
      expect(parser.parse('double zero one present').digits, '001');
    });

    test('a PRN imported without its leading zeros still matches', () {
      final shortRoster = [
        StudentModel(
            id: 'short', teacherId: 't1', prn: '1', studentName: 'Short Prn'),
      ];
      final command = parser.parse('001 present');
      final result = parser.resolve(command, shortRoster);
      expect(result.type.name, 'single');
      expect(result.matchedStudent!.studentName, 'Short Prn');
    });
  });

  group('edge cases', () {
    test('empty input', () {
      final cmd = parser.parse('');
      expect(cmd.nameText, isEmpty);
      expect(cmd.digits, isNull);
      expect(cmd.status, isNull);
    });

    test('just the keyword is not a student', () {
      final cmd = parser.parse('present');
      final result = parser.resolve(cmd, students);
      expect(result.type.name, 'none');
    });

    test('an empty roster matches nothing', () {
      final cmd = parser.parse('Aayush Nagras present');
      expect(parser.resolve(cmd, []).type.name, 'none');
    });
  });
}
