import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../core/utils.dart';
import '../models/student.dart';
import 'report_service.dart';

class ExcelImportPreview {
  final List<StudentModel> validStudents;
  final List<String> errorMessages;
  final int totalRowsParsed;
  final int headerRowNumber; // 1-based row where the headers were found
  final String sheetName; // worksheet the rows came from

  ExcelImportPreview({
    required this.validStudents,
    required this.errorMessages,
    required this.totalRowsParsed,
    this.headerRowNumber = 1,
    this.sheetName = '',
  });

  bool get hasErrors => errorMessages.isNotEmpty;
}

abstract class ExcelService {
  ExcelImportPreview parseStudentExcel(Uint8List bytes, String teacherId);
  Uint8List generateCumulativeAttendanceExcel(AttendanceReport report);
  Uint8List generateSessionAttendanceExcel({
    required String className,
    required String subjectName,
    required DateTime date,
    required List<StudentModel> roster,
    required Map<String, String> attendanceMap,
  });
}

/// Where each required column was found in the header row.
class _ColumnMap {
  int prn = -1;
  int name = -1;
  int email = -1;

  bool get isValid => prn >= 0 && name >= 0;
}

class DefaultExcelService implements ExcelService {
  /// How many rows to scan for the header row (real sheets often have a
  /// title, a subtitle and a blank line above the table).
  static const int _maxHeaderScanRows = 25;

  @override
  ExcelImportPreview parseStudentExcel(Uint8List bytes, String teacherId) {
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      return ExcelImportPreview(
        validStudents: [],
        errorMessages: ['Excel file contains no worksheets.'],
        totalRowsParsed: 0,
      );
    }

    // Pick the worksheet that actually holds data. A workbook created by
    // Excel often keeps an empty "Sheet1" next to the real sheet.
    Sheet? sheet;
    String sheetName = '';
    int bestRows = 0;
    excel.tables.forEach((name, s) {
      if (s.maxRows > bestRows) {
        bestRows = s.maxRows;
        sheet = s;
        sheetName = name;
      }
    });

    if (sheet == null || bestRows <= 1) {
      return ExcelImportPreview(
        validStudents: [],
        errorMessages: [
          'Worksheet is empty or has no data rows. Make sure the file has a '
              'header row (PRN, Student Name) and at least one student.',
        ],
        totalRowsParsed: 0,
        sheetName: sheetName,
      );
    }

    // Find the header row: the first row that yields BOTH a PRN-like and a
    // name-like column. This tolerates title/subtitle/blank rows above it.
    int headerRow = -1;
    _ColumnMap cols = _ColumnMap();
    final rows = sheet!.rows;
    final scanLimit =
        rows.length < _maxHeaderScanRows ? rows.length : _maxHeaderScanRows;

    for (int r = 0; r < scanLimit; r++) {
      final detected = _detectColumns(rows[r]);
      if (detected.isValid) {
        headerRow = r;
        cols = detected;
        break;
      }
    }

    if (headerRow == -1) {
      return ExcelImportPreview(
        validStudents: [],
        errorMessages: [
          'Could not find a header row with PRN and Student Name columns in '
              '"$sheetName".\n'
              'The first row of the table should contain a PRN column '
              '(PRN / Roll No / Admission ID / Student ID) and a name column '
              '(Name / Student Name).',
        ],
        totalRowsParsed: 0,
        sheetName: sheetName,
      );
    }

    final validStudents = <StudentModel>[];
    final errorMessages = <String>[];
    final seenPrns = <String>{};
    int totalRows = 0;

    for (int r = headerRow + 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      final prn = _cellText(row, cols.prn);
      final name = _cellText(row, cols.name);
      final email = _cellText(row, cols.email);

      // Skip completely empty rows.
      if (prn.isEmpty && name.isEmpty) continue;

      // Skip summary/footer rows such as "Total | 60 | " — they are not
      // students and must not be reported as errors.
      if (_isSummaryRow(row, prn, name)) continue;

      totalRows++;

      if (prn.isEmpty) {
        errorMessages.add(
            'Row ${r + 1}: Missing PRN for student "$name".');
        continue;
      }
      if (name.isEmpty) {
        errorMessages.add(
            'Row ${r + 1}: Missing Student Name for PRN "$prn".');
        continue;
      }

      if (seenPrns.contains(prn)) {
        errorMessages
            .add('Row ${r + 1}: Duplicate PRN "$prn" found in file.');
        continue;
      }

      seenPrns.add(prn);
      validStudents.add(StudentModel(
        id: '',
        teacherId: teacherId,
        prn: prn,
        studentName: name,
        email: email,
      ));
    }

    return ExcelImportPreview(
      validStudents: validStudents,
      errorMessages: errorMessages,
      totalRowsParsed: totalRows,
      headerRowNumber: headerRow + 1,
      sheetName: sheetName,
    );
  }

  /// Reads a cell as clean text.
  ///
  /// The excel package wraps values in `CellValue` subclasses, and
  /// `TextCellValue.toString()` returns "TextSpan(text: ...)" — so every
  /// type has to be unwrapped explicitly.
  String _cellText(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    final value = row[index]?.value;
    if (value == null) return '';

    if (value is TextCellValue) return value.value.text?.trim() ?? '';
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) {
      final v = value.value;
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    if (value is DateCellValue) {
      return '${value.year}-${value.month}-${value.day}';
    }
    if (value is BoolCellValue) return value.value.toString();
    return value.toString().trim();
  }

  /// Detects the PRN / name / email columns in a candidate header row.
  _ColumnMap _detectColumns(List<Data?> row) {
    final map = _ColumnMap();

    for (int i = 0; i < row.length; i++) {
      final raw = _cellText(row, i);
      final header = _normalizeHeader(raw);
      if (header.isEmpty) continue;

      // Email columns are never a PRN or a name column.
      if (header.contains('email') || header.contains('mail')) {
        if (map.email == -1) map.email = i;
        continue;
      }

      if (map.name == -1 && _isNameHeader(header)) {
        map.name = i;
        continue;
      }

      if (map.prn == -1 && _isIdHeader(header)) {
        map.prn = i;
        continue;
      }

      // "Student" on its own is a weak name signal.
      if (map.name == -1 &&
          (header == 'student' || header == 'students') &&
          map.prn == -1 &&
          !_isIdHeader(header)) {
        map.name = i;
      }
    }

    return map;
  }

  String _normalizeHeader(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '') // remove spaces & punctuation
        .trim();
  }

  bool _isNameHeader(String h) {
    if (h.contains('filename') ||
        h.contains('username') ||
        h.contains('nickname')) {
      return false;
    }
    if (h.contains('name')) return true;
    return false;
  }

  bool _isIdHeader(String h) {
    // Row counters are not PRNs.
    if (h == 'sr' ||
        h == 'srno' ||
        h.startsWith('srno') ||
        h == 'sno' ||
        h == 'sl' ||
        h == 'slno' ||
        h == 'serial' ||
        h == 'serialno' ||
        h == 'no' ||
        h == 'number') {
      return false;
    }
    if (h.contains('prn')) return true;
    if (h.contains('roll')) return true;
    if (h.contains('admission')) return true;
    if (h.contains('enrol') || h.contains('enroll')) return true;
    if (h.contains('regno') || h.contains('registration')) return true;
    if (h.contains('usn')) return true;
    if (h == 'id' || h.endsWith('id')) return true;
    if (h.endsWith('no')) return true;
    return false;
  }

  /// True for trailing "Total 60" style rows.
  bool _isSummaryRow(List<Data?> row, String prn, String name) {
    // Exact labels — "Sumit" must not be treated as a summary row.
    const exactLabels = {
      'total',
      'totals',
      'grandtotal',
      'sum',
      'subtotal',
      'totalstudents',
      'totalno',
      'totalnoofstudents',
      'totalstrength',
      'overalltotal',
    };

    // The label can sit in any column (often the first one).
    for (int i = 0; i < row.length; i++) {
      final cell = _normalizeHeader(_cellText(row, i));
      if (cell.isEmpty) continue;
      if (exactLabels.contains(cell)) return true;
      if (cell.startsWith('total')) return true;
    }

    // No name and a non-numeric PRN -> a label row, not a student.
    if (name.isEmpty && prn.isNotEmpty && double.tryParse(prn) == null) {
      return true;
    }

    return false;
  }

  @override
  Uint8List generateCumulativeAttendanceExcel(AttendanceReport report) {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Attendance Report'];
    excel.delete('Sheet1');

    // Header Row
    List<CellValue> headers = [
      TextCellValue('PRN'),
      TextCellValue('Student Name'),
    ];

    for (var session in report.sessions) {
      headers.add(TextCellValue(AppUtils.formatDate(session.lectureDate)));
    }

    headers.addAll([
      TextCellValue('Attended'),
      TextCellValue('Conducted'),
      TextCellValue('Percentage (%)'),
    ]);

    sheet.appendRow(headers);

    // Data Rows
    for (var row in report.studentRows) {
      List<CellValue> rowData = [
        TextCellValue(row.student.prn),
        TextCellValue(row.student.studentName),
      ];

      for (var session in report.sessions) {
        String status = row.sessionStatusMap[session.id] ?? '-';
        rowData.add(TextCellValue(status));
      }

      rowData.addAll([
        IntCellValue(row.attendedCount),
        IntCellValue(row.eligibleConductedCount),
        DoubleCellValue(row.percentage),
      ]);

      sheet.appendRow(rowData);
    }

    List<int>? fileBytes = excel.save();
    return Uint8List.fromList(fileBytes ?? []);
  }

  @override
  Uint8List generateSessionAttendanceExcel({
    required String className,
    required String subjectName,
    required DateTime date,
    required List<StudentModel> roster,
    required Map<String, String> attendanceMap,
  }) {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Attendance'];
    excel.delete('Sheet1');

    final dateStr = AppUtils.formatDate(date);
    sheet.appendRow([
      TextCellValue('Class: $className'),
      TextCellValue('Subject: $subjectName'),
      TextCellValue('Date: $dateStr'),
    ]);
    sheet.appendRow([
      TextCellValue('PRN'),
      TextCellValue('Student Name'),
      TextCellValue('Status ($dateStr)'),
    ]);

    for (var s in roster) {
      final status = (attendanceMap[s.id] ?? 'absent').toUpperCase();
      sheet.appendRow([
        TextCellValue(s.prn),
        TextCellValue(s.studentName),
        TextCellValue(status),
      ]);
    }

    final present = attendanceMap.values.where((v) => v == 'present').length;
    sheet.appendRow([
      TextCellValue('Present: $present'),
      TextCellValue('Absent: ${roster.length - present}'),
      TextCellValue('Total: ${roster.length}'),
    ]);

    List<int>? fileBytes = excel.save();
    return Uint8List.fromList(fileBytes ?? []);
  }
}
