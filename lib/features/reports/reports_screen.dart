import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/attendance_record.dart';
import '../../models/attendance_session.dart';
import '../../models/class_model.dart';
import '../../models/class_subject.dart';
import '../../models/enrollment.dart';
import '../../models/student.dart';
import '../../models/subject.dart';
import '../../services/excel_service.dart';
import '../../services/report_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ReportGenerator _reportGenerator = DefaultReportGenerator();
  final ExcelService _excelService = DefaultExcelService();

  late AttendanceReport _report;

  @override
  void initState() {
    super.initState();
    _buildDemoReport();
  }

  void _buildDemoReport() {
    final classModel = ClassModel(
      id: 'c1',
      teacherId: 't1',
      className: 'BE Computer A',
      academicYear: '2026-2027',
      semester: 'VIII',
    );
    final subjectModel = SubjectModel(
      id: 's1',
      teacherId: 't1',
      subjectCode: 'CS801',
      subjectName: 'Ubiquitous Computing',
    );

    final classSubject = ClassSubjectModel(
      id: 'cs1',
      teacherId: 't1',
      classId: 'c1',
      subjectId: 's1',
      classDetails: classModel,
      subjectDetails: subjectModel,
    );

    final students = [
      StudentModel(id: '1', teacherId: 't1', prn: '101', studentName: 'Rahul Patil'),
      StudentModel(id: '2', teacherId: 't1', prn: '102', studentName: 'Sneha Sharma'),
      StudentModel(id: '3', teacherId: 't1', prn: '103', studentName: 'Amit Kumar'),
      StudentModel(id: '4', teacherId: 't1', prn: '104', studentName: 'Rahul Patil'),
      StudentModel(id: '5', teacherId: 't1', prn: '105', studentName: 'Priya Verma'),
    ];

    final enrollments = students.map((s) => EnrollmentModel(
      id: 'e_${s.id}',
      classSubjectId: 'cs1',
      studentId: s.id,
      enrolledFrom: DateTime(2026, 9, 1),
      student: s,
    )).toList();

    final sessions = [
      AttendanceSessionModel(id: 'sess1', classSubjectId: 'cs1', lectureDate: DateTime(2026, 9, 15)),
      AttendanceSessionModel(id: 'sess2', classSubjectId: 'cs1', lectureDate: DateTime(2026, 9, 18)),
      AttendanceSessionModel(id: 'sess3', classSubjectId: 'cs1', lectureDate: DateTime(2026, 9, 21)),
      AttendanceSessionModel(id: 'sess4', classSubjectId: 'cs1', lectureDate: DateTime(2026, 9, 23)),
    ];

    final records = [
      // Rahul Patil 101 (3/4 = 75%)
      AttendanceRecordModel(id: 'r1', sessionId: 'sess1', studentId: '1', status: 'present'),
      AttendanceRecordModel(id: 'r2', sessionId: 'sess2', studentId: '1', status: 'present'),
      AttendanceRecordModel(id: 'r3', sessionId: 'sess3', studentId: '1', status: 'absent'),
      AttendanceRecordModel(id: 'r4', sessionId: 'sess4', studentId: '1', status: 'present'),

      // Sneha Sharma 102 (4/4 = 100%)
      AttendanceRecordModel(id: 'r5', sessionId: 'sess1', studentId: '2', status: 'present'),
      AttendanceRecordModel(id: 'r6', sessionId: 'sess2', studentId: '2', status: 'present'),
      AttendanceRecordModel(id: 'r7', sessionId: 'sess3', studentId: '2', status: 'present'),
      AttendanceRecordModel(id: 'r8', sessionId: 'sess4', studentId: '2', status: 'present'),

      // Amit Kumar 103 (2/4 = 50% - Low Attendance)
      AttendanceRecordModel(id: 'r9', sessionId: 'sess1', studentId: '3', status: 'present'),
      AttendanceRecordModel(id: 'r10', sessionId: 'sess2', studentId: '3', status: 'absent'),
      AttendanceRecordModel(id: 'r11', sessionId: 'sess3', studentId: '3', status: 'absent'),
      AttendanceRecordModel(id: 'r12', sessionId: 'sess4', studentId: '3', status: 'present'),

      // Rahul Patil 104 (1/4 = 25% - Low Attendance)
      AttendanceRecordModel(id: 'r13', sessionId: 'sess1', studentId: '4', status: 'absent'),
      AttendanceRecordModel(id: 'r14', sessionId: 'sess2', studentId: '4', status: 'present'),
      AttendanceRecordModel(id: 'r15', sessionId: 'sess3', studentId: '4', status: 'absent'),
      AttendanceRecordModel(id: 'r16', sessionId: 'sess4', studentId: '4', status: 'absent'),

      // Priya Verma 105 (4/4 = 100%)
      AttendanceRecordModel(id: 'r17', sessionId: 'sess1', studentId: '5', status: 'present'),
      AttendanceRecordModel(id: 'r18', sessionId: 'sess2', studentId: '5', status: 'present'),
      AttendanceRecordModel(id: 'r19', sessionId: 'sess3', studentId: '5', status: 'present'),
      AttendanceRecordModel(id: 'r20', sessionId: 'sess4', studentId: '5', status: 'present'),
    ];

    _report = _reportGenerator.generateReport(
      classSubject: classSubject,
      sessions: sessions,
      enrollments: enrollments,
      allRecords: records,
    );
  }

  void _exportExcel() {
    final bytes = _excelService.generateCumulativeAttendanceExcel(_report);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cumulative Excel Report generated successfully (${bytes.length} bytes)!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cumulative Attendance Matrix'),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Export PDF',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PDF Report generated successfully!')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Export Excel',
            onPressed: _exportExcel,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _report.classSubject.subjectDetails?.subjectName ?? 'Subject',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                        Text('Class: ${_report.classSubject.classDetails?.className ?? "Class"}'),
                        Text('Total Lectures Conducted: ${_report.sessions.length}'),
                      ],
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Export Excel'),
                      onPressed: _exportExcel,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Cumulative Matrix Table View (Section 15 Rule 10)
            const Text('Cumulative Attendance Grid', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.primary.withOpacity(0.1)),
                columns: [
                  const DataColumn(label: Text('PRN', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
                  ..._report.sessions.map((s) => DataColumn(
                    label: Text('${s.lectureDate.day}/${s.lectureDate.month}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  )),
                  const DataColumn(label: Text('Attended', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('Conducted', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('%', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _report.studentRows.map((row) {
                  bool isLow = row.isBelowThreshold(75.0);
                  return DataRow(
                    color: isLow ? WidgetStateProperty.all(AppColors.error.withOpacity(0.05)) : null,
                    cells: [
                      DataCell(Text(row.student.prn, style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text(row.student.studentName)),
                      ..._report.sessions.map((s) {
                        String status = row.sessionStatusMap[s.id] ?? '-';
                        Color color = status == 'P' ? AppColors.success : (status == 'A' ? AppColors.error : Colors.grey);
                        return DataCell(Text(
                          status,
                          style: TextStyle(fontWeight: FontWeight.bold, color: color),
                        ));
                      }),
                      DataCell(Text('${row.attendedCount}')),
                      DataCell(Text('${row.eligibleConductedCount}')),
                      DataCell(
                        Chip(
                          label: Text('${row.percentage}%'),
                          backgroundColor: isLow ? AppColors.error.withOpacity(0.15) : AppColors.success.withOpacity(0.15),
                          labelStyle: TextStyle(
                            color: isLow ? AppColors.error : AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
