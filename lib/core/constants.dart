import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'Smart Attendance System';
  static const double defaultThresholdPercent = 75.0;

  // Supabase Table Names
  static const String tableProfiles = 'profiles';
  static const String tableTeacherAvailability = 'teacher_availability';
  static const String tableClasses = 'classes';
  static const String tableSubjects = 'subjects';
  static const String tableClassSubjects = 'class_subjects';
  static const String tableStudents = 'students';
  static const String tableEnrollments = 'enrollments';
  static const String tableAttendanceSessions = 'attendance_sessions';
  static const String tableAttendanceRecords = 'attendance_records';
  static const String tableAttendanceAlerts = 'attendance_alerts';
}

class AppColors {
  static const Color primary = Color(0xFF1E88E5);
  static const Color primaryDark = Color(0xFF1565C0);
  static const Color accent = Color(0xFF00ACC1);
  
  static const Color background = Color(0xFFF8F9FA);
  static const Color cardBackground = Colors.white;
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkCardBackground = Color(0xFF1E1E1E);

  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
}
