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
  static const String tableAttendanceEdits = 'attendance_edits';
}

class AppColors {
  // Maytech Warm Orange & Amber Palette
  static const Color primary = Color(0xFFF97316);      // Warm Maytech / Shadcn Orange
  static const Color primaryDark = Color(0xFFEA580C);  // Deep Amber Orange
  static const Color primaryLight = Color(0xFFFFEDD5); // Soft Peach Tint
  static const Color accent = Color(0xFFFB923C);       // Vibrant Bright Orange
  
  static const Color background = Color(0xFFF8FAFC);   // Crisp Light Slate Canvas
  static const Color cardBackground = Colors.white;
  static const Color darkBackground = Color(0xFF0F172A); // Deep Slate Dark
  static const Color darkCardBackground = Color(0xFF1E293B);
  static const Color darkDockBackground = Color(0xFF18181B); // Floating Dark Dock

  static const Color success = Color(0xFF10B981); // Emerald Green
  static const Color warning = Color(0xFFF59E0B); // Amber Yellow
  static const Color error = Color(0xFFEF4444);   // Coral Red
  static const Color info = Color(0xFF3B82F6);    // Sky Indigo

  static const Color textPrimary = Color(0xFF0F172A);   // Slate 900 Text
  static const Color textSecondary = Color(0xFF64748B); // Slate 500 Muted Text
  static const Color borderLight = Color(0xFFE2E8F0);   // Subtle Divider / Border
}
