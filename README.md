# Smart Attendance Ubiquitous System

A teacher-centric voice-assisted attendance and attendance-monitoring application built with Flutter & Dart, backed by Supabase PostgreSQL database, Row Level Security (RLS), and Google Apps Script email automation.

---

## 🚀 Key Features

1. **Teacher Profiles & Availability**: Manage profile details, default attendance threshold (75%), and free meeting availability slots.
2. **Multi-Class & Subject Management**: Create classes, subjects, connect subjects to classes, set custom thresholds, and configure class-specific Google Form URLs.
3. **Student Roster Import (Excel XLSX)**: Parse `.xlsx` files with automatic column detection (`PRN`, `Student Name`, `Email`), header validation, error reporting, and duplicate PRN prevention.
4. **Voice Attendance Engine**: Speak present student names using microphone input. Runs exact matching, normalized speech text, and safe Levenshtein fuzzy matching (`NameMatcher`).
5. **Rule 5 Ambiguity Handling**: If a spoken name matches multiple students (e.g. duplicate names like "Rahul Patil"), the system displays a selection dialog asking the teacher to choose the correct PRN.
6. **Rule 4 & Rule 7 Protection**: All enrolled students default to `absent` when a lecture session starts. Duplicate present marks for the same student in a single session are automatically blocked.
7. **Cumulative Attendance Reporting**: Calculates subject-wise attendance percentage while strictly respecting student enrollment dates:
   $$\text{percentage} = \frac{\text{attended\_sessions}}{\text{eligible\_conducted\_sessions}} \times 100$$
   Supports Exporting to XLSX and PDF formats.
8. **Low-Attendance Email Automation**: Separate out-of-band Google Apps Script (`Code.gs`) that checks for students with $\text{percentage} < \text{threshold}$, respects anti-spam reminder intervals, and emails them with their attendance stats, the class-specific Google Form link, and teacher meeting availability slots.

---

## 🛠 Project Structure

```text
voice_attendance/
├── lib/
│   ├── main.dart                      # Flutter app entry point
│   ├── app/                           # Theme & global app shell
│   ├── core/                          # Constants & Levenshtein / Date utils
│   ├── models/                        # Profile, Class, Subject, Student, Session, Record, Alert models
│   ├── services/                      # AuthService, DatabaseService, MatchingService, ExcelService, ReportService, SpeechService
│   ├── features/                      # UI Screens (Dashboard, Classes, Students, Attendance, Reports, Alerts, Profile)
├── test/
│   ├── services/matching_service_test.dart  # Unit tests for student name matching
│   └── services/report_service_test.dart    # Unit tests for cumulative attendance formulas
├── supabase/
│   └── migrations/20260923000000_initial_schema.sql # Complete database SQL schema & RLS policies
├── automation/
│   └── google_apps_script/Code.gs     # Google Apps Script for low attendance alert automation
├── pubspec.yaml
└── design.md                          # Source-of-truth project specification
```

---

## ⚡ Setup & Running

### 1. Database Setup (Supabase)
Run the migration script `supabase/migrations/20260923000000_initial_schema.sql` in your Supabase SQL Editor to create tables, indexes, foreign keys, unique constraints, RLS policies, and triggers.

### 2. Environment Configuration
Copy `.env` and fill in your Supabase project credentials:
```env
SUPABASE_URL=https://your-supabase-project.supabase.co
SUPABASE_ANON_KEY=your-supabase-anon-key
```

### 3. Run Flutter Application
```bash
# Run web client
flutter run -d chrome

# Run Android build
flutter build apk
```

### 4. Run Automated Unit Tests
```bash
flutter test
```
