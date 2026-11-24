# Smart Attendance Ubiquitous System

A teacher-centric voice-assisted attendance and attendance-monitoring application built with
Flutter & Dart, backed by Supabase PostgreSQL database, Row Level Security (RLS), and Google
Apps Script email automation.

---

## 🚀 Key Features

1. **Teacher Auth & Isolation**: Supabase email/password auth with Row Level Security — every
   teacher sees only their own classes, students, sessions and records.
2. **Multi-Class & Subject Management**: Create classes, subjects, connect subjects to classes,
   set custom thresholds, and configure class-specific Google Form URLs.
3. **Student Roster Import (Excel XLSX)**: Parse `.xlsx` files with automatic column detection
   (`PRN`, `Student Name`, `Email`), header validation, error reporting, and duplicate PRN
   prevention. Imported in 2 requests regardless of roster size.
4. **Voice Attendance Engine**: Speak present student names using microphone input. Runs exact
   matching, normalized speech text, and safe Levenshtein fuzzy matching (`NameMatcher`).
4a. **Voice status commands**: say *"Aayush Nagras present"* to mark present, *"Aayush Nagras absent"*
   to mark absent. A name without the word "present" is only ever marked absent — a student is
   marked present **only** when the teacher actually says "present".
4b. **Mark by PRN (last 3 digits)**: say *"501"* or *"five zero one"* and the student whose PRN
   ends with `501` is found. Full PRNs work too; a shared suffix asks the teacher to choose.
4c. **Continuous listening**: the microphone stays open (dictation mode) so the teacher can call out
   one student after another, and the roster names are fed to the recogniser as contextual
   phrases for better accuracy on Indian names. Recognisers that only emit interim results
   (e.g. the web build) are supported: a settled partial phrase containing a complete
   instruction is applied, while a bare name fragment never marks anyone.
5. **Rule 5 Ambiguity Handling**: If a spoken name matches multiple students (e.g. duplicate names
   like "Aarav Sharma"), the system displays a selection dialog asking the teacher to choose the
   correct PRN.
6. **Rule 4 & Rule 7 Protection**: All enrolled students default to `absent` when a lecture
   session starts. Duplicate present marks for the same student in a single session are
   automatically blocked by a DB unique constraint.
7. **Cumulative Attendance Reporting**: Calculates subject-wise attendance percentage while
   strictly respecting student enrollment dates. Supports exporting to XLSX and PDF.
7a. **Period-aware lectures**: each lecture belongs to a period (1–8) of the day, so a teacher can
   take several lectures a day without a duplicate-lecture clash.
8. **Dated Excel Export**: Every finalized lecture exports as
   `Attendance_<CLASS>_<YYYY-MM-DD>.xlsx` and can be shared straight from the phone.
8a. **Finalized lectures stay read-only**: after a lecture is finalized its roster can still be
   reviewed, but no late voice result or stray tap can change it and it cannot be finalized
   twice. A **New** action starts the next lecture (in the next free period) from the same
   screen.
9. **Low-Attendance Email Automation**: Out-of-band Google Apps Script (`Code.gs`) that checks for
   students below the configured threshold on a per-class daily/weekly/bi-weekly schedule, evaluates
   times in the teacher's timezone, respects anti-spam reminder intervals, and emails them with their
   attendance stats, the class-specific Google Form link, and teacher availability slots. Every
   attempt is recorded as pending → sent/failed in the app's Email History.
10. **Offline-safe marks & batched writes**: a mark shows on screen instantly, is written in a
    single batched upsert per lecture, and survives a dropped connection — pending marks are kept
    on the device and replayed automatically, with an on-screen "Offline — N mark(s) saved" banner.
    Finalizing a lecture waits until every queued mark has reached Postgres.

---

## 🛠 Project Structure

```text
voice_attendance/
├── lib/
│   ├── main.dart                      # Entry point: env check + Supabase init
│   ├── app/                           # Theme, auth gate, configuration screen
│   ├── core/                          # Constants & Levenshtein / Date utils
│   ├── models/                        # Profile, Class, Subject, Student, Session, Record, Alert
│   ├── providers/                     # Riverpod: auth, database, classes, attendance controller
│   ├── services/                      # Auth, Database, Matching, Excel, Report, Speech
│   ├── features/                      # Auth, Dashboard, Classes, Students, Attendance, Reports, Alerts, Profile
│   └── providers/attendance_controller.dart  # Live lecture session state (DB-backed)
├── test/
│   ├── services/                      # Unit tests: matching + report formulas
│   └── integration/                   # Live Supabase integration tests
├── tool/seed/                         # Demo data seeding (run explicitly)
├── supabase/migrations/               # Production schema, RLS policies, triggers
├── automation/google_apps_script/     # Low-attendance email automation
├── pubspec.yaml
└── design.md                          # Source-of-truth project specification
```

---

## ⚡ Setup & Running

### 1. Database Setup (Supabase — free tier)

1. Create a free project at [supabase.com](https://supabase.com).
2. Run `supabase/migrations/20261021000000_production_schema.sql` in the
   **SQL Editor → New query → Run**. It creates 10 tables, indexes, unique constraints, RLS
   policies, and the auto-profile trigger.
3. Copy your **Project URL** and **publishable (anon) key** from
   **Project Settings → API**.

### 2. Environment Configuration

```bash
cp .env.example .env
```

```env
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_ANON_KEY=sb_publishable_...
```

> Use the **publishable** key only. It is safe to ship in the app because RLS enforces data
> isolation. Never put the service-role key in the app — it belongs in the Apps Script properties.

If `.env` is missing or still contains placeholders, the app shows a "Backend not configured"
screen instead of silently running on empty data.

### 3. Run the Application

```bash
flutter pub get
flutter run -d chrome     # web
flutter run -d android    # Android device
flutter build apk         # release APK
```

### 4. Run Tests

```bash
flutter test                                        # unit + live integration + UI
flutter test test/services/                         # unit tests only
node --test test/automation/low_attendance_automation_test.js  # email automation
flutter test tool/seed/seed_demo_test.dart          # re-seed the demo teacher
```

**Test coverage:**

| File | What it proves |
|---|---|
| `test/services/excel_service_test.dart` | Roster import handles plain sheets, title rows, blank rows, `Admission ID` / `Email ID` headers, numeric PRNs, `Total` footer rows, empty `Sheet1`, any column order, and all validation errors |
| `test/services/voice_command_service_test.dart` | Voice commands: present/absent keywords, mis-heard spellings, filler words, name matching, PRN by the last 3 digits, number words |
| `test/services/matching_service_test.dart` | Name matching (exact / partial / fuzzy / ambiguous) |
| `test/services/report_service_test.dart` | Attendance percentage + enrollment dates |
| `test/integration/backend_integration_test.dart` | The real service layer against the live Supabase project, including RLS isolation |
| `test/integration/voice_attendance_e2e_test.dart` | Create class → import a **formatted** Excel → start session → speak a name → stored as `source='voice'` → finalize → cumulative report, plus two lectures on the same day using different periods |
| `test/integration/speech_pipeline_test.dart` | Mic permission → engine init → platform recognition callback → `onResult` (and that a denied permission never starts listening) |
| `test/integration/attendance_screen_ui_test.dart` | The real screen: pick class → Start → tap mic → a partial result marks nobody → "name present" marks present → "name absent" marks absent → PRN digits mark the right student → interim-only (web) results mark correctly → chip toggles to `manual` → finalized lectures are read-only and **New** starts the next lecture |
| `test/integration/screens_smoke_test.dart` | Every screen renders with no exceptions or overflow, including at a 1.4× system font scale |
| `test/integration/reports_dropdown_test.dart` | The class + subject dropdown survives a provider refetch |
| `test/automation/low_attendance_automation_test.js` | Email automation: daily/weekly/bi-weekly schedule, timezone, alert time, reminder anti-spam, recovery/new cycle, missing emails, send failures, dry run, and trigger installation |

### 5. Demo Account

A seeded demo teacher is available for quick testing:

```text
email:    setup.probe.check@gmail.com
password: Probe@12345
```

It contains 2 classes (BE E&TC A, TE E&TC A), 12 students (including a duplicate name for the
ambiguity demo) and 3 completed lectures with real percentages.

---

## 🔐 Row Level Security

Every table has RLS enabled with teacher-scoped policies:

| Table | Rule |
|---|---|
| `profiles` | a teacher sees only their own row |
| `classes`, `subjects`, `class_subjects`, `students` | `teacher_id = auth.uid()` |
| `enrollments`, `attendance_sessions`, `attendance_records`, `attendance_alerts` | owner resolved through `class_subjects.teacher_id` |

The Google Apps Script uses the service-role key, so it can read across teachers for the
scheduled check while the app itself can never do so.

---

## 📧 Low-Attendance Email Automation

The app stores alert settings and displays delivery history. The actual scheduled check and email
delivery run in Google Apps Script, so the phone does not need to be open.

### One-time setup

1. Open [script.google.com](https://script.google.com) and paste
   `automation/google_apps_script/Code.gs`.
2. Add script properties (**Project Settings → Script Properties**):
   - `SUPABASE_URL` = your project URL
   - `SUPABASE_SERVICE_ROLE_KEY` = your service-role key
   - `TEST_EMAIL` = optional address used only by the test-email function
3. Run `installLowAttendanceTrigger()` once and authorize the script. This installs a single
   15-minute trigger; the script decides which class + subject is actually due.
4. Run `sendTestLowAttendanceEmail()` and confirm the test email arrives.
5. Run `previewLowAttendanceAlerts()` for a dry run. It logs what would be emailed without sending
   or writing alert history.

### How scheduling works

Each class + subject has an alert toggle, threshold, Google Form URL, frequency
(daily / weekly / bi-weekly), send time, weekly day or repeat interval, and anti-spam interval.
Times are evaluated in the teacher profile's timezone.

- **Daily**: once per local day at/after the configured time.
- **Weekly**: once on the selected weekday at/after the configured time.
- **Bi-weekly**: once per configured interval (14/21/28 days).
- **Anti-spam**: a student is not emailed again until their reminder interval has elapsed.
- **Recovery**: if a student recovers above the threshold and later drops below it again, a new
  alert cycle starts.
- **Failures**: each attempt is written as `pending`, then updated to `sent` or `failed` with an
  error message. Failed deliveries are visible in **Alerts → Email History**.

> Gmail/Apps Script quotas apply. The script uses `MailApp`, so emails are sent from the Google
> account that owns the Apps Script project. The first run requires manual Google authorization.

See `automation/google_apps_script/README.md` for the deployment checklist and troubleshooting.
