import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/services/excel_service.dart';

Uint8List build(List<List<CellValue>> rows, {String sheetName = 'Sheet1'}) {
  final excel = Excel.createExcel();
  final sheet = excel[sheetName];
  for (final row in rows) {
    sheet.appendRow(row);
  }
  final bytes = excel.save()!;
  return Uint8List.fromList(bytes);
}

void main() {
  final service = DefaultExcelService();

  group('Excel import — simple sheet', () {
    test('parses PRN / Student Name / Email', () {
      final bytes = build([
        [TextCellValue('PRN'), TextCellValue('Student Name'), TextCellValue('Email')],
        [TextCellValue('101'), TextCellValue('Rahul Patil'), TextCellValue('r@univ.edu')],
        [TextCellValue('102'), TextCellValue('Sneha Sharma'), TextCellValue('s@univ.edu')],
      ]);

      final preview = service.parseStudentExcel(bytes, 't1');
      expect(preview.errorMessages, isEmpty);
      expect(preview.validStudents.length, 2);
      expect(preview.validStudents.first.prn, '101');
      expect(preview.validStudents.first.studentName, 'Rahul Patil');
      expect(preview.validStudents.first.email, 'r@univ.edu');
    });

    test('email column is optional', () {
      final bytes = build([
        [TextCellValue('PRN'), TextCellValue('Name')],
        [TextCellValue('101'), TextCellValue('Rahul Patil')],
      ]);

      final preview = service.parseStudentExcel(bytes, 't1');
      expect(preview.errorMessages, isEmpty);
      expect(preview.validStudents.single.email, isEmpty);
    });
  });

  group('Excel import — formatted sheets', () {
    test('finds the header below title and blank rows', () {
      final bytes = build([
        [TextCellValue('Department of E&TC')],
        [TextCellValue('Student List 2026-27')],
        [TextCellValue('')], // a real blank row
        [TextCellValue('PRN'), TextCellValue('Student Name'), TextCellValue('Email')],
        [TextCellValue('101'), TextCellValue('Rahul Patil'), TextCellValue('r@univ.edu')],
      ]);

      final preview = service.parseStudentExcel(bytes, 't1');
      expect(preview.errorMessages, isEmpty);
      expect(preview.validStudents.length, 1);
      // Header is on the 4th row of the sheet.
      expect(preview.headerRowNumber, 4);
    });

    test('"Admission ID" is the PRN and "Email ID" is the email', () {
      final bytes = build([
        [
          TextCellValue('Sr. No.'),
          TextCellValue('Admission ID'),
          TextCellValue('Student Name'),
          TextCellValue('Email ID'),
          TextCellValue('Semester'),
        ],
        [
          IntCellValue(1),
          TextCellValue('301'),
          TextCellValue('Vedant Joshi'),
          TextCellValue('vedant@univ.edu'),
          TextCellValue('VI'),
        ],
      ]);

      final preview = service.parseStudentExcel(bytes, 't1');
      expect(preview.errorMessages, isEmpty);
      expect(preview.validStudents.single.prn, '301');
      expect(preview.validStudents.single.studentName, 'Vedant Joshi');
      expect(preview.validStudents.single.email, 'vedant@univ.edu');
    });

    test('numeric PRN cells are read as plain numbers', () {
      final bytes = build([
        [TextCellValue('Roll No'), TextCellValue('Full Name')],
        [IntCellValue(701), TextCellValue('Riya Kamble')],
        [DoubleCellValue(702), TextCellValue('Arjun Verma')],
      ]);

      final preview = service.parseStudentExcel(bytes, 't1');
      expect(preview.errorMessages, isEmpty);
      expect(preview.validStudents.map((s) => s.prn).toList(), ['701', '702']);
    });

    test('a trailing "Total" row is ignored, not reported as an error', () {
      final bytes = build([
        [TextCellValue('PRN'), TextCellValue('Student Name'), TextCellValue('Email')],
        [TextCellValue('101'), TextCellValue('Rahul Patil'), TextCellValue('r@univ.edu')],
        [TextCellValue('Total'), TextCellValue('1'), TextCellValue('')],
      ]);

      final preview = service.parseStudentExcel(bytes, 't1');
      expect(preview.errorMessages, isEmpty);
      expect(preview.validStudents.length, 1);
    });

    test('columns in any order are detected', () {
      final bytes = build([
        [TextCellValue('Student Name'), TextCellValue('Email'), TextCellValue('PRN')],
        [TextCellValue('Kabir Joshi'), TextCellValue('k@univ.edu'), TextCellValue('801')],
      ]);

      final preview = service.parseStudentExcel(bytes, 't1');
      expect(preview.errorMessages, isEmpty);
      expect(preview.validStudents.single.prn, '801');
      expect(preview.validStudents.single.studentName, 'Kabir Joshi');
    });

    test('reads the sheet that holds the data, not an empty Sheet1', () {
      final excel = Excel.createExcel();
      // "Sheet1" stays empty (the default), the data is on "Roster".
      final roster = excel['Roster'];
      roster.appendRow([
        TextCellValue('PRN'),
        TextCellValue('Student Name'),
        TextCellValue('Email')
      ]);
      roster.appendRow([
        TextCellValue('101'),
        TextCellValue('Rahul Patil'),
        TextCellValue('r@univ.edu')
      ]);
      final bytes = excel.save()!;

      final preview = service.parseStudentExcel(Uint8List.fromList(bytes), 't1');
      expect(preview.errorMessages, isEmpty);
      expect(preview.validStudents.length, 1);
      expect(preview.sheetName, 'Roster');
    });
  });

  group('Excel import — validation', () {
    test('reports a missing required column with a helpful message', () {
      final bytes = build([
        [TextCellValue('Roll No'), TextCellValue('Semester')],
        [TextCellValue('101'), TextCellValue('VI')],
      ]);

      final preview = service.parseStudentExcel(bytes, 't1');
      expect(preview.validStudents, isEmpty);
      expect(preview.errorMessages, hasLength(1));
      expect(preview.errorMessages.first, contains('header row'));
    });

    test('reports a duplicate PRN', () {
      final bytes = build([
        [TextCellValue('PRN'), TextCellValue('Student Name')],
        [TextCellValue('101'), TextCellValue('Rahul Patil')],
        [TextCellValue('101'), TextCellValue('Someone Else')],
      ]);

      final preview = service.parseStudentExcel(bytes, 't1');
      expect(preview.validStudents.length, 1);
      expect(preview.errorMessages.single, contains('Duplicate PRN'));
    });

    test('reports a student with no PRN', () {
      final bytes = build([
        [TextCellValue('PRN'), TextCellValue('Student Name')],
        [TextCellValue(''), TextCellValue('Rahul Patil')],
      ]);

      final preview = service.parseStudentExcel(bytes, 't1');
      expect(preview.validStudents, isEmpty);
      expect(preview.errorMessages.single, contains('Missing PRN'));
    });

    test('an empty workbook is reported clearly', () {
      final excel = Excel.createExcel();
      final bytes = excel.save()!;
      final preview = service.parseStudentExcel(Uint8List.fromList(bytes), 't1');
      expect(preview.validStudents, isEmpty);
      expect(preview.errorMessages, isNotEmpty);
    });
  });
}
