import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voice_attendance/models/class_model.dart';
import 'package:voice_attendance/models/class_subject.dart';
import 'package:voice_attendance/models/student.dart';
import 'package:voice_attendance/models/subject.dart';
import 'package:voice_attendance/services/auth_service.dart';
import 'package:voice_attendance/services/database_service.dart';

const demoEmail = 'setup.probe.check@gmail.com';
const demoPassword = 'Probe@12345';

/// Seeds a realistic E&TC demo teacher (class, subject, roster, three
/// completed lectures) using the app's own service layer, so the seeded data
/// is byte-for-byte what the app itself writes.
void main() {
  test('seed demo teacher data', () async {
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(fileName: '.env');
    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL'),
      publishableKey: dotenv.get('SUPABASE_ANON_KEY'),
    );

    final auth = SupabaseAuthService();
    final db = SupabaseDatabaseService();
    final client = Supabase.instance.client;

    final res = await auth.signIn(email: demoEmail, password: demoPassword);
    expect(res.user, isNotNull, reason: 'probe sign-in failed');
    final teacherId = res.user!.id;
    // ignore: avoid_print
    print('Signed in as $demoEmail');

    // Clean previous demo data for this teacher.
    await client.from('classes').delete().eq('teacher_id', teacherId);
    await client.from('subjects').delete().eq('teacher_id', teacherId);
    await client.from('students').delete().eq('teacher_id', teacherId);

    await auth.ensureProfile(fullName: 'Prof. Govind Suryawanshi', email: demoEmail);
    await client.from('profiles').update({
      'full_name': 'Prof. Govind Suryawanshi',
      'faculty_id': 'E&TC-2026-09',
      'department': 'Electronics & Telecommunication Engineering',
      'phone': '+91 98765 43210',
      'timezone': 'Asia/Kolkata',
      'default_threshold': 75.0,
    }).eq('id', teacherId);

    Future<ClassSubjectModel> makeClassSubject(
      String className,
      String year,
      String sem,
      String code,
      String subjectName,
      String formUrl,
    ) async {
      final cls = await db.createClass(ClassModel(
        id: '',
        teacherId: teacherId,
        className: className,
        academicYear: year,
        semester: sem,
      ));
      final subject = await db.createSubject(SubjectModel(
        id: '',
        teacherId: teacherId,
        subjectCode: code,
        subjectName: subjectName,
      ));
      return db.createClassSubject(ClassSubjectModel(
        id: '',
        teacherId: teacherId,
        classId: cls.id,
        subjectId: subject.id,
        classDetails: cls,
        subjectDetails: subject,
        googleFormUrl: formUrl,
        thresholdPercent: 75,
      ));
    }

    final beA = await makeClassSubject(
      'BE E&TC A',
      '2026-2027',
      'VIII',
      'EC801',
      'Digital Communication',
      'https://forms.google.com/d/e/demo-be-etc-a',
    );
    final teA = await makeClassSubject(
      'TE E&TC A',
      '2026-2027',
      'VI',
      'EC602',
      'Signals & Systems',
      'https://forms.google.com/d/e/demo-te-etc-a',
    );

    final beStudents = [
      StudentModel(id: '', teacherId: teacherId, prn: '101', studentName: 'Aarav Sharma', email: 'aarav101@univ.edu'),
      StudentModel(id: '', teacherId: teacherId, prn: '102', studentName: 'Diya Patil', email: 'diya@univ.edu'),
      StudentModel(id: '', teacherId: teacherId, prn: '103', studentName: 'Rohan Deshmukh', email: 'rohan@univ.edu'),
      StudentModel(id: '', teacherId: teacherId, prn: '104', studentName: 'Aarav Sharma', email: 'aarav104@univ.edu'),
      StudentModel(id: '', teacherId: teacherId, prn: '105', studentName: 'Ishita Kulkarni', email: 'ishita@univ.edu'),
      StudentModel(id: '', teacherId: teacherId, prn: '106', studentName: 'Kabir Joshi', email: 'kabir@univ.edu'),
      StudentModel(id: '', teacherId: teacherId, prn: '107', studentName: 'Meera Nair', email: 'meera@univ.edu'),
      StudentModel(id: '', teacherId: teacherId, prn: '108', studentName: 'Siddharth Rao', email: 'sid@univ.edu'),
    ];
    final teStudents = [
      StudentModel(id: '', teacherId: teacherId, prn: '201', studentName: 'Neha Pillai', email: 'neha@univ.edu'),
      StudentModel(id: '', teacherId: teacherId, prn: '202', studentName: 'Tarun Bose', email: 'tarun@univ.edu'),
      StudentModel(id: '', teacherId: teacherId, prn: '203', studentName: 'Priya Menon', email: 'priya@univ.edu'),
      StudentModel(id: '', teacherId: teacherId, prn: '204', studentName: 'Arjun Verma', email: 'arjun@univ.edu'),
    ];

    await db.bulkImportStudentsAndEnroll(
        teacherId: teacherId, classSubjectId: beA.id, students: beStudents);
    await db.bulkImportStudentsAndEnroll(
        teacherId: teacherId, classSubjectId: teA.id, students: teStudents);

    final beEnrollments = await db.getEnrollments(beA.id);
    final beByPrn = {
      for (final e in beEnrollments) e.student!.prn: e.student!.id,
    };
    final teEnrollments = await db.getEnrollments(teA.id);
    final teByPrn = {
      for (final e in teEnrollments) e.student!.prn: e.student!.id,
    };

    Future<void> lecture(
      String classSubjectId,
      DateTime date,
      Map<String, String> rosterByPrn,
      Set<String> absentPrns,
    ) async {
      final session = await db.startAttendanceSession(
          classSubjectId: classSubjectId, date: date);
      for (final entry in rosterByPrn.entries) {
        final absent = absentPrns.contains(entry.key);
        await db.markStudentAttendance(
          sessionId: session.id,
          studentId: entry.value,
          status: absent ? 'absent' : 'present',
          source: absent ? 'default' : 'voice',
        );
      }
      await db.completeSession(session.id);
    }

    await lecture(
        beA.id,
        DateTime.now().subtract(const Duration(days: 5)),
        beByPrn,
        {'104', '107'});
    await lecture(
        beA.id,
        DateTime.now().subtract(const Duration(days: 2)),
        beByPrn,
        {'103', '104', '106', '108'});
    await lecture(
        teA.id,
        DateTime.now().subtract(const Duration(days: 3)),
        teByPrn,
        {});

    // ignore: avoid_print
    print('Seeded: 2 classes, ${beStudents.length + teStudents.length} students, 3 lectures');
  });
}
