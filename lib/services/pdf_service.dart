import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/utils.dart';
import '../models/attendance_session.dart';
import 'report_service.dart';

/// Builds the printable matrix sheet that mirrors the on-screen report.
///
/// Sessions are split into horizontal chunks and students into vertical chunks
/// so every page starts with a full header — no cut-off rows, no missing column
/// labels, whatever the class size.
class PdfService {
  static const int _sessionsPerChunk = 6;
  static const int _rowsPerPage = 24;

  const PdfService();

  Future<Uint8List> generateCumulativeAttendancePdf(
    AttendanceReport report,
  ) async {
    final document = pw.Document(
      title: 'Cumulative Attendance',
      author: 'Smart Attendance',
    );

    final className =
        report.classSubject.classDetails?.className ?? 'Class';
    final subjectName =
        report.classSubject.subjectDetails?.subjectName ?? 'Subject';
    final subjectCode =
        report.classSubject.subjectDetails?.subjectCode ?? '';
    final threshold = report.classSubject.thresholdPercent;

    final sessionChunks = <List<AttendanceSessionModel>>[];
    if (report.sessions.isEmpty) {
      sessionChunks.add(const []);
    } else {
      for (var i = 0; i < report.sessions.length;
          i += _sessionsPerChunk) {
        sessionChunks.add(report.sessions.sublist(
          i,
          math.min(i + _sessionsPerChunk, report.sessions.length),
        ));
      }
    }

    final rows = report.studentRows;
    var pageNumber = 0;

    for (final chunk in sessionChunks) {
      final rowPages = <List<StudentReportRow>>[];
      if (rows.isEmpty) {
        rowPages.add(const []);
      } else {
        for (var i = 0; i < rows.length; i += _rowsPerPage) {
          rowPages.add(rows.sublist(
            i,
            math.min(i + _rowsPerPage, rows.length),
          ));
        }
      }

      for (final pageRows in rowPages) {
        pageNumber++;
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 18),
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _header(
                  className: className,
                  subjectName: subjectName,
                  subjectCode: subjectCode,
                  threshold: threshold,
                  sessions: chunk.length,
                  page: pageNumber,
                ),
                pw.SizedBox(height: 8),
                _table(report, chunk, pageRows, threshold),
                pw.Spacer(),
                _legend(threshold),
              ],
            ),
          ),
        );
      }
    }

    // A report with no lectures still gets one page of context.
    if (pageNumber == 0) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _header(
                className: className,
                subjectName: subjectName,
                subjectCode: subjectCode,
                threshold: threshold,
                sessions: 0,
                page: 1,
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'No finalized lectures yet. Take a lecture and finalize it, '
                'then export the report again.',
              ),
            ],
          ),
        ),
      );
    }

    return document.save();
  }

  pw.Widget _header({
    required String className,
    required String subjectName,
    required String subjectCode,
    required double threshold,
    required int sessions,
    required int page,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CUMULATIVE ATTENDANCE REPORT',
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange800,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  '$subjectName${subjectCode.isEmpty ? '' : ' ($subjectCode)'}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Class: $className   •   $sessions lecture(s)   •   '
                  'Threshold: ${threshold.toStringAsFixed(0)}%',
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  AppUtils.formatDate(DateTime.now()),
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  'Page $page',
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 1, color: PdfColors.orange300),
      ],
    );
  }

  pw.Widget _table(
    AttendanceReport report,
    List<AttendanceSessionModel> sessions,
    List<StudentReportRow> rows,
    double threshold,
  ) {
    final headers = <String>[
      'PRN',
      'Student Name',
      ...sessions.map((s) =>
          '${AppUtils.formatDate(s.lectureDate)}\nP${s.periodNumber}'),
      'Attended',
      'Total',
      '%',
    ];

    final data = rows.map((row) {
      return <String>[
        row.student.prn,
        row.student.studentName,
        ...sessions.map((s) => row.sessionStatusMap[s.id] ?? '-'),
        '${row.attendedCount}',
        '${row.eligibleConductedCount}',
        row.percentage.toStringAsFixed(1),
      ];
    }).toList();

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.orange100),
          children: headers
              .map((h) => pw.Padding(
                    padding:
                        const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                    child: pw.Text(
                      h,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ))
              .toList(),
        ),
        ...data.map((cells) {
          final percentage = double.tryParse(cells.last) ?? 0;
          final isLow = percentage < threshold;
          return pw.TableRow(
            decoration: isLow
                ? const pw.BoxDecoration(color: PdfColors.red50)
                : null,
            children: cells.asMap().entries.map((entry) {
              final isLast = entry.key == cells.length - 1;
              final isStatus = entry.key >= 2 &&
                  entry.key < cells.length - 3;
              final value = entry.value;
              final isPresent = value == 'P';
              final isAbsent = value == 'A';

              return pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                child: pw.Text(
                  value,
                  textAlign: isStatus || isLast
                      ? pw.TextAlign.center
                      : pw.TextAlign.left,
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: isStatus
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    color: isPresent
                        ? PdfColors.green700
                        : isAbsent
                            ? PdfColors.red700
                            : isLast && isLow
                                ? PdfColors.red800
                                : PdfColors.black,
                  ),
                ),
              );
            }).toList(),
          );
        }),
        if (data.isEmpty)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  'No enrolled students yet.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _legend(double threshold) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'P = present   A = absent   - = before enrollment (not counted)',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
        pw.Text(
          'Students below ${threshold.toStringAsFixed(0)}% are highlighted.',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ],
    );
  }
}
