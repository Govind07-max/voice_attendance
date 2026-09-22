import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../core/utils.dart';
import '../models/student.dart';
import 'report_service.dart';

class ExcelImportPreview {
  final List<StudentModel> validStudents;
  final List<String> errorMessages;
  final int totalRowsParsed;

  ExcelImportPreview({
    required this.validStudents,
    required this.errorMessages,
    required this.totalRowsParsed,
  });

  bool get hasErrors => errorMessages.isNotEmpty;
}

abstract class ExcelService {
  ExcelImportPreview parseStudentExcel(Uint8List bytes, String teacherId);
  Uint8List generateCumulativeAttendanceExcel(AttendanceReport report);
}

class DefaultExcelService implements ExcelService {
  @override
  ExcelImportPreview parseStudentExcel(Uint8List bytes, String teacherId) {
    var excel = Excel.decodeBytes(bytes);
    List<StudentModel> validStudents = [];
    List<String> errorMessages = [];
    int totalRows = 0;

    if (excel.tables.isEmpty) {
      return ExcelImportPreview(
        validStudents: [],
        errorMessages: ['Excel file contains no worksheets.'],
        totalRowsParsed: 0,
      );
    }

    String tableKey = excel.tables.keys.first;
    Sheet? sheet = excel.tables[tableKey];
    if (sheet == null || sheet.maxRows <= 1) {
      return ExcelImportPreview(
        validStudents: [],
        errorMessages: ['Worksheet is empty or has no data rows.'],
        totalRowsParsed: 0,
      );
    }

    // Identify header column indices
    List<Data?> headerRow = sheet.rows.first;
    int prnCol = -1;
    int nameCol = -1;
    int emailCol = -1;

    for (int i = 0; i < headerRow.length; i++) {
      String colName = headerRow[i]?.value.toString().toLowerCase().trim() ?? '';
      if (colName.contains('prn') || colName.contains('roll') || colName.contains('id')) {
        prnCol = i;
      } else if (colName.contains('name') || colName.contains('student')) {
        nameCol = i;
      } else if (colName.contains('email') || colName.contains('mail')) {
        emailCol = i;
      }
    }

    if (prnCol == -1 || nameCol == -1) {
      return ExcelImportPreview(
        validStudents: [],
        errorMessages: ['Missing required column headers: PRN and Student Name.'],
        totalRowsParsed: 0,
      );
    }

    Set<String> seenPrns = {};

    for (int rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      List<Data?> row = sheet.rows[rowIndex];
      if (row.isEmpty) continue;
      totalRows++;

      String prn = prnCol < row.length ? (row[prnCol]?.value?.toString().trim() ?? '') : '';
      String name = nameCol < row.length ? (row[nameCol]?.value?.toString().trim() ?? '') : '';
      String email = emailCol != -1 && emailCol < row.length 
          ? (row[emailCol]?.value?.toString().trim() ?? '') 
          : '';

      if (prn.isEmpty && name.isEmpty) {
        continue; // Skip empty trailing rows
      }

      if (prn.isEmpty) {
        errorMessages.add('Row ${rowIndex + 1}: Missing PRN for student "$name".');
        continue;
      }
      if (name.isEmpty) {
        errorMessages.add('Row ${rowIndex + 1}: Missing Student Name for PRN "$prn".');
        continue;
      }

      if (seenPrns.contains(prn)) {
        errorMessages.add('Row ${rowIndex + 1}: Duplicate PRN "$prn" found in file.');
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
    );
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
}
