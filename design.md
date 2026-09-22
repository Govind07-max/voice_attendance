# Smart Attendance Ubiquitous System — Overall Design

## 1. Project Identity

**Project name:** Smart Attendance Ubiquitous System

**Project type:** Teacher-centric voice-assisted attendance and attendance-monitoring system.

**Primary platforms:**
- Android mobile app — final target
- Responsive web app — initial development and testing target

**Core principle:** Build one simple Flutter application that runs on Android and web, backed by one shared database. Use AI as a development and reasoning partner, not as an excuse to add unnecessary features or complexity.

---

## 2. What This Project Actually Is

This project helps a teacher take attendance quickly for multiple classes and subjects.

The teacher does not need to speak the names of absent students. At the beginning of a lecture, all enrolled students are considered absent. As the teacher speaks the names of present students, the system identifies them and changes their status to present.

The system must:

1. Let a teacher create a profile.
2. Let one teacher manage multiple classes.
3. Let a class have multiple subjects.
4. Let the teacher upload an Excel student list for a selected class/subject.
5. Identify students using spoken names.
6. Handle identical/similar names safely by asking the teacher to select the correct PRN.
7. Prevent a student from being marked present twice in the same lecture.
8. Let the teacher manually edit attendance mistakes.
9. Store attendance lecture-by-lecture and day-by-day.
10. Keep cumulative subject-wise attendance instead of generating a new attendance history file every day.
11. Generate the complete attendance report whenever the teacher requests it.
12. Calculate subject-wise attendance percentage.
13. Detect students below the configured 75% attendance threshold.
14. Send configurable scheduled low-attendance emails.
15. Include the Google Form link configured for that class + subject in the email.
16. Store teacher free/available meeting slots for the communication workflow.
17. Leave actual meeting scheduling outside the current scope.

---

## 3. Why We Are Building It

The problem is not simply “manual attendance is slow.” The larger problem is that attendance work is fragmented:

- teachers handle multiple classes and subjects;
- student lists already exist in spreadsheets;
- attendance is repeatedly collected for the same enrolled students;
- manual name searching is slow;
- identical student names create ambiguity;
- mistakes need correction;
- attendance percentage has to be maintained over time;
- low-attendance students need follow-up.

The system creates one simple workflow:

> **Select class + subject → speak present students → review/correct → save lecture → cumulative attendance updates → scheduled low-attendance monitoring.**

The project is “ubiquitous” because the system should reduce interaction effort and allow the teacher to interact naturally through voice while the application handles data storage, identification, calculations, reports, and follow-up in the background.

---

# 4. Product Scope

## 4.1 In Scope

### Teacher
- Sign up / login
- Create and edit profile
- Add free/available meeting slots
- Create/manage classes
- Create/manage subjects
- Connect subjects to classes
- Configure Google Form link per class + subject
- Configure attendance threshold
- Configure alert schedule
- Upload student Excel files
- Validate and import student data
- Start attendance session
- Speak student names
- Resolve duplicate/similar names
- Handle unknown names
- Prevent duplicate attendance
- Review attendance
- Edit attendance
- Finish/finalize lecture
- View cumulative attendance
- Export Excel
- Export PDF
- View low-attendance students
- View alert history

### Automation
- Scheduled low-attendance check
- Detect students below threshold
- Avoid repeated/spam alerts using alert history
- Send email containing attendance details and the correct Google Form link

## 4.2 Explicitly Out of Scope for the First Version

Do **not** build these unless requirements change:

- Student login
- Student mobile app
- Face recognition
- Speaker identity recognition
- GPS/geofencing attendance
- Fingerprint/biometric attendance
- QR attendance
- Actual meeting booking/calendar integration
- Chat system
- College ERP integration
- Payment/subscription system
- Complex admin portal
- AI chatbot for teachers/students
- Microservice architecture
- Offline sync unless it becomes necessary
- Native Android and separate React/web applications

The system should remain small, understandable, and demonstrable.

---

# 5. Key Product Rules

These are business rules, not implementation suggestions. Agents must preserve them.

## Rule 1 — Teacher is the main user

Only the teacher operates the application in the current scope.

## Rule 2 — PRN identifies a student

Student names are not unique identifiers.

A database may contain:

```text
PRN 101 — Rahul Patil
PRN 104 — Rahul Patil
```

These are two different students.

## Rule 3 — Present students are spoken

The teacher speaks the names of students who are present.

The teacher does **not** need to speak absent students.

## Rule 4 — Default attendance state

At the beginning of a lecture:

```text
All enrolled students → Absent
```

Each successfully identified student becomes:

```text
Absent → Present
```

## Rule 5 — Ambiguous names require teacher confirmation

If multiple students match the spoken name, do not guess.

Show the matching students and PRNs and ask the teacher to select one.

## Rule 6 — Unknown names are not marked

If no reliable student match exists, ask the teacher to retry. Never silently assign a student.

## Rule 7 — Duplicate attendance is blocked

A student can have only one attendance record for a single attendance session.

## Rule 8 — Teacher can edit

The teacher has final control over the attendance for the lecture and can correct mistakes before/after finalization according to the UI rules.

## Rule 9 — Attendance is subject-wise

Attendance percentage is calculated separately for each class + subject combination.

Example:

```text
Ubiquitous Computing → 72%
DBMS                 → 91%
Cloud Computing      → 68%
```

## Rule 10 — The attendance history is cumulative

Do not create a new “master attendance file” for every day.

The database is the source of truth. Reports are generated from the database whenever needed.

The exported report should look like one continuous sheet with dates/lectures as columns.

## Rule 11 — Attendance is lecture-based

The system tracks actual attendance sessions, not merely calendar days.

Multiple lectures on the same day must be possible.

## Rule 12 — 75% threshold

Default threshold:

```text
75%
```

Low attendance means:

```text
attendance_percentage < configured_threshold
```

Therefore:

```text
75.00% → not below threshold
74.99% → below threshold
```

## Rule 13 — Alerts are configurable

Do not hard-code a single email schedule.

The teacher should be able to configure the low-attendance check frequency, enabled/disabled state, threshold, and related reminder settings.

## Rule 14 — Avoid repeated emails

Maintain alert history and do not send the same low-attendance email repeatedly without respecting the configured reminder policy.

## Rule 15 — Google Form belongs to the class + subject

A teacher may use different forms for different class/subject combinations.

Example:

```text
BE-A + Ubiquitous Computing → Form A
BE-B + Ubiquitous Computing → Form B
TE-A + DBMS                 → Form C
```

The low-attendance email must use the correct link.

## Rule 16 — Meeting management is not part of MVP

Teacher availability is stored so the information can be communicated. The application does not schedule or host the meeting yet.

## Rule 17 — Enrollment matters

If a student joins a class later, lectures before the enrollment date must not reduce that student's attendance percentage.

---

# 6. Recommended Tech Stack

Keep the stack deliberately small.

## Frontend

**Flutter + Dart**

Why:
- one codebase for Android and web;
- fast UI development;
- good fit for a student project;
- Android APK generation is straightforward;
- web can be used for early testing.

## Backend / Database / Authentication

**Supabase**

Use:
- Supabase Auth for teacher authentication;
- PostgreSQL for application data;
- Supabase Row Level Security for data isolation;
- optional Supabase Storage only where file storage is actually needed.

Do not introduce a custom Node/Express backend unless a real requirement appears.

## State Management

**Riverpod**

Use it only for application state that genuinely needs shared/reactive management.

Do not build an elaborate state-management architecture.

## Speech Recognition

**speech_to_text** or another maintained Flutter speech-recognition package suitable for Android and web.

Important design constraint: recognition is a short utterance workflow such as one student name at a time, not unrestricted continuous dictation.

## Excel

**file_picker** + maintained XLSX package such as **excel_community**.

Use Excel for:
- importing student lists;
- exporting attendance reports.

Do not use Excel as the primary database.

## PDF

A maintained Flutter/Dart PDF package such as **pdf**.

## External Form

**Google Forms**

The teacher manually provides the form URL for each class + subject.

## Email + Scheduling

**Google Apps Script + Gmail/MailApp** for the first free-cost implementation.

Use Apps Script for scheduled checking and email delivery rather than exposing email credentials to the Flutter app.

Free-service quotas can change, so verify current limits before a real deployment.

## Source Control

**GitHub**

Use Git for version history and AI-agent collaboration.

## Initial Web Hosting

During development:

```text
flutter run -d chrome
```

For a public academic demo, a free static hosting option such as GitHub Pages can be used, subject to its current plan/feature rules.

## Android Distribution

Generate and install an APK directly for project testing/demonstration. Play Store publication is not required for the MVP.

---

# 7. Architecture

```text
                    ┌───────────────────────┐
                    │       TEACHER         │
                    │ Android / Web         │
                    └──────────┬────────────┘
                               │
                         Flutter App
                               │
            ┌──────────────────┼──────────────────┐
            │                  │                  │
            ▼                  ▼                  ▼
      Speech Service     Excel Service       UI / State
            │                  │                  │
            └────────────┬─────┴──────────────────┘
                         │
                         ▼
                   Supabase Client
                         │
                         ▼
                ┌──────────────────┐
                │    Supabase      │
                │                  │
                │ Auth             │
                │ PostgreSQL       │
                │ RLS              │
                └────────┬─────────┘
                         │
          ┌──────────────┼──────────────────┐
          │              │                  │
          ▼              ▼                  ▼
      Attendance       Reports          Alert Data
          │                                  │
          │                                  ▼
          │                         Google Apps Script
          │                                  │
          │                                  ▼
          │                                Gmail
          │                                  │
          ▼                                  ▼
     Cumulative                    Low-attendance
       History                         student
                                          │
                                          ▼
                                    Google Form
```

---

# 8. Why This Architecture

Keep the system to one client, one database, and one automation layer.

Do not create:

```text
Flutter + React + Node + Python API + separate ML server + message queue + microservices
```

That is unnecessary for the project.

Instead:

```text
Flutter
  ↓
Supabase
  ↓
Google Apps Script automation
```

The only external system in the first version is Google Forms/Gmail-related automation.

---

# 9. Database Design

The database should be normalized enough to avoid duplicated business data, but not so complicated that students cannot understand it.

## 9.1 profiles

Purpose: teacher profile.

```text
profiles
-------------------------------
id                UUID PK
full_name         TEXT
faculty_id        TEXT
email             TEXT
department        TEXT
phone             TEXT
timezone          TEXT
default_threshold NUMERIC
created_at        TIMESTAMP
updated_at        TIMESTAMP
```

## 9.2 teacher_availability

Purpose: teacher free slots.

```text
teacher_availability
-------------------------------
id             UUID PK
teacher_id     UUID FK
 day_of_week   INTEGER
start_time     TIME
end_time       TIME
active         BOOLEAN
```

## 9.3 classes

Purpose: teacher's class groups.

```text
classes
-------------------------------
id             UUID PK
teacher_id     UUID FK
class_name     TEXT
academic_year  TEXT
semester       TEXT
section        TEXT
active         BOOLEAN
created_at     TIMESTAMP
```

## 9.4 subjects

Purpose: subjects managed by a teacher.

```text
subjects
-------------------------------
id             UUID PK
teacher_id     UUID FK
subject_code   TEXT
subject_name   TEXT
created_at     TIMESTAMP
```

## 9.5 class_subjects

Purpose: map a subject to a particular class and hold class-subject settings.

```text
class_subjects
-------------------------------
id                  UUID PK
teacher_id          UUID FK
class_id            UUID FK
subject_id          UUID FK
google_form_url     TEXT
threshold_percent  NUMERIC
alert_enabled       BOOLEAN
alert_frequency     TEXT
alert_time          TIME
weekly_day          INTEGER
interval_days       INTEGER
reminder_days       INTEGER
active              BOOLEAN
created_at          TIMESTAMP
```

This is one of the most important tables.

A class + subject is the main attendance context.

## 9.6 students

Purpose: master student identity.

```text
students
-------------------------------
id             UUID PK
teacher_id     UUID FK
prn            TEXT
student_name   TEXT
email          TEXT
created_at     TIMESTAMP
updated_at     TIMESTAMP
```

Recommended constraint:

```text
UNIQUE(teacher_id, prn)
```

Names are not unique.

## 9.7 enrollments

Purpose: connect a student to a particular class + subject.

```text
enrollments
-------------------------------
id                  UUID PK
class_subject_id    UUID FK
student_id          UUID FK
enrolled_from       DATE
enrolled_to         DATE NULL
active              BOOLEAN
```

Recommended unique rule:

```text
UNIQUE(class_subject_id, student_id)
```

## 9.8 attendance_sessions

Purpose: one actual lecture/attendance event.

```text
attendance_sessions
-------------------------------
id                  UUID PK
class_subject_id    UUID FK
lecture_date        DATE
period_number       INTEGER
started_at          TIMESTAMP
ended_at            TIMESTAMP
status              TEXT
created_at          TIMESTAMP
```

Possible status:

```text
draft
active
completed
cancelled
```

## 9.9 attendance_records

Purpose: one student's result within one lecture.

```text
attendance_records
-------------------------------
id             UUID PK
session_id     UUID FK
student_id     UUID FK
status         TEXT
source         TEXT
marked_at      TIMESTAMP
```

Status:

```text
present
absent
```

Source:

```text
voice
manual
default
```

Critical constraint:

```text
UNIQUE(session_id, student_id)
```

## 9.10 attendance_alerts

Purpose: email history and anti-spam control.

```text
attendance_alerts
-------------------------------
id                   UUID PK
class_subject_id     UUID FK
student_id           UUID FK
attendance_percent   NUMERIC
attended_count       INTEGER
conducted_count      INTEGER
alert_type           TEXT
sent_at              TIMESTAMP
status               TEXT
error_message        TEXT NULL
```

Possible alert types:

```text
initial
reminder
```

---

# 10. Relationship Model

```text
Teacher
  │
  ├── Classes
  │
  ├── Subjects
  │
  ├── Availability
  │
  └── Class-Subjects
           │
           ├── Google Form
           ├── Attendance Settings
           │
           ├── Enrollments
           │       │
           │       └── Students
           │
           └── Attendance Sessions
                     │
                     └── Attendance Records
                               │
                               └── Students
```

---

# 11. Excel Import Design

## Expected minimum input columns

```text
PRN | Student Name | Email
```

Optional future columns can be added only if actually needed.

## Import flow

```text
Upload XLSX
    ↓
Read file
    ↓
Validate headers
    ↓
Validate rows
    ↓
Show preview
    ↓
Teacher confirms
    ↓
Import students
    ↓
Create/update enrollments
```

## Validation rules

Reject or clearly report:

- missing required column;
- blank PRN;
- blank student name;
- invalid email where email is required;
- duplicate PRN within the teacher's student master;
- duplicate student enrollment in the selected class-subject;
- malformed spreadsheet rows.

Never partially import silently.

---

# 12. Attendance Session Workflow

## Start

Teacher selects:

```text
Class → Subject → Start Attendance
```

System creates an `attendance_session`.

All currently eligible/enrolled students receive an `absent` record for that session.

## Voice

```text
Tap microphone
    ↓
Teacher speaks one name
    ↓
Speech-to-text
    ↓
Normalize recognized text
    ↓
Find candidates
    ↓
One candidate?
    │
    ├── Yes → mark present
    │
    └── No
          │
          ├── Multiple → teacher selects PRN
          │
          └── None → retry
```

## Finish

```text
Teacher Review
    ↓
Edit mistakes
    ↓
Save / Finish Lecture
    ↓
Mark session completed
```

---

# 13. Name Matching Design

The matching system should be simple and predictable.

## Step 1 — Normalize

Normalize:
- lower/upper case;
- repeated spaces;
- basic punctuation.

Example:

```text
"rahul  patil"
"Rahul Patil"
```

should normalize to the same comparison form.

## Step 2 — Exact matching

Try exact normalized name matching first.

## Step 3 — Safe fuzzy matching

If exact matching fails, allow a conservative similarity check for common speech-to-text variations.

Do not automatically mark a student merely because a fuzzy score exists.

## Step 4 — Ambiguity

If multiple students are plausible, ask the teacher.

## Step 5 — No match

If no sufficiently reliable match exists, ask the teacher to retry.

### Important

PRN selection is always explicit when names are ambiguous.

---

# 14. Attendance Editing

The teacher must be able to search a student and change status.

Example:

```text
PRN 104
Rahul Patil
Present → Absent
```

The system should record the change in a simple audit mechanism when implemented.

Do not build a large audit platform. A small audit record is enough.

---

# 15. Cumulative Reporting

The database remains the source of truth.

When the teacher requests a report:

```text
Selected Class + Subject
        ↓
Completed Sessions
        ↓
Attendance Records
        ↓
Build Student × Session matrix
        ↓
Calculate totals
        ↓
Calculate percentage
        ↓
Display report
        ↓
Export XLSX/PDF
```

The report should conceptually look like:

| PRN | Student Name | 21-Sep | 22-Sep | 24-Sep | 26-Sep | Attended | Conducted | % |
|---|---|---|---|---|---|---:|---:|---:|
| 101 | Rahul Patil | P | P | A | P | 3 | 4 | 75% |
| 102 | Sneha Sharma | A | P | P | P | 3 | 4 | 75% |

The actual database should **not** create a new database column for each date.

The date columns exist only in the generated report view.

---

# 16. Attendance Percentage

Formula:

```text
attendance_percentage =
    (present_sessions / eligible_conducted_sessions) * 100
```

The denominator must consider the student's enrollment period.

Example:

```text
Student enrolled after 5 previous lectures.

Previous 5 lectures → not counted
Next 10 lectures     → counted
Present in 8         → 80%
```

---

# 17. Low Attendance Automation

The alert process should be separate from attendance-taking.

```text
Scheduled job
     ↓
Read active class-subject settings
     ↓
Find eligible students
     ↓
Calculate current percentage
     ↓
percentage < threshold?
     ↓
Check alert history
     ↓
Should alert be sent according to configuration?
     ↓
Yes
     ↓
Build email
     ↓
Insert class-subject Google Form link
     ↓
Insert teacher information / availability
     ↓
Send email
     ↓
Record alert history
```

The mobile app does not need to remain open for this automation.

---

# 18. Email Contents

A low-attendance email should communicate:

- student's name;
- class;
- subject;
- current attendance percentage;
- attended lectures;
- total eligible/conducted lectures;
- the fact that attendance is below the configured 75% criterion by default;
- the Google Form link for that class + subject;
- relevant teacher information;
- teacher's available meeting slots, where appropriate.

The student handles the actual reason submission and future meeting process through the provided workflow.

The application does not schedule the meeting in the MVP.

---

# 19. Alert State Logic

Avoid email spam.

A simple lifecycle:

```text
Above threshold
      ↓
Below threshold
      ↓
Initial alert sent
      ↓
Remain below threshold
      ↓
Wait for configured reminder interval
      ↓
Reminder eligible
      ↓
Reminder sent
```

If the student recovers:

```text
Below threshold
      ↓
Attendance >= threshold
      ↓
Alert state resolved
```

If the student later falls below the threshold again, a new alert cycle can begin.

---

# 20. Teacher UI Structure

## Navigation

### Mobile

Use a simple bottom navigation:

```text
Home | Classes | Attendance | Reports | Profile
```

Alerts can be accessible from Home or Reports rather than creating unnecessary navigation.

### Web

Use a left sidebar:

```text
Dashboard
Classes
Attendance
Reports
Alerts
Profile
```

Same features, responsive layout.

---

# 21. Screen List

## 21.1 Splash

```text
Smart Attendance
Loading...
```

## 21.2 Login

- Email
- Password
- Login
- Create profile/account

## 21.3 Teacher Profile

- Name
- Faculty ID
- Department
- Email
- Phone
- Default threshold
- Availability slots
- Alert defaults

## 21.4 Dashboard

Show:

- today's classes;
- quick attendance button;
- attendance summary;
- count of students below threshold;
- recent alerts.

## 21.5 Classes

- list classes;
- add class;
- select class;
- see subjects.

## 21.6 Class + Subject Setup

- subject name/code;
- Google Form URL;
- attendance threshold;
- alert settings;
- student list.

## 21.7 Student Import

- upload Excel;
- preview;
- validation errors;
- confirm import.

## 21.8 Attendance

Large microphone button.

Show:

- class;
- subject;
- date;
- present count;
- absent count;
- last recognized student;
- recently marked list;
- review/finish buttons.

## 21.9 Duplicate Match

Show:

```text
Multiple students found

1. Rahul Patil — PRN 101
2. Rahul Patil — PRN 104
```

Teacher explicitly selects one.

## 21.10 Review Attendance

- search/filter;
- present/absent list;
- edit status;
- finish lecture.

## 21.11 Reports

- select class;
- select subject;
- select optional date range;
- view cumulative report;
- export Excel;
- export PDF.

## 21.12 Low Attendance

Show:

- student;
- PRN;
- subject;
- percentage;
- last alert;
- alert state.

## 21.13 Profile / Settings

- teacher information;
- meeting slots;
- default attendance threshold;
- alert configuration.

---

# 22. Flutter Project Structure

Keep folders feature-oriented but lightweight.

```text
smart_attendance/
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── app.dart
│   │   ├── router.dart
│   │   └── theme.dart
│   │
│   ├── core/
│   │   ├── constants.dart
│   │   ├── validators.dart
│   │   └── utils.dart
│   │
│   ├── models/
│   │   ├── profile.dart
│   │   ├── class_model.dart
│   │   ├── subject.dart
│   │   ├── student.dart
│   │   ├── enrollment.dart
│   │   ├── attendance_session.dart
│   │   ├── attendance_record.dart
│   │   └── attendance_alert.dart
│   │
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── database_service.dart
│   │   ├── speech_service.dart
│   │   ├── matching_service.dart
│   │   ├── excel_service.dart
│   │   └── report_service.dart
│   │
│   ├── features/
│   │   ├── auth/
│   │   ├── dashboard/
│   │   ├── profile/
│   │   ├── classes/
│   │   ├── students/
│   │   ├── attendance/
│   │   ├── reports/
│   │   └── alerts/
│   │
│   └── providers/
│       ├── auth_provider.dart
│       ├── class_provider.dart
│       ├── attendance_provider.dart
│       └── report_provider.dart
│
├── automation/
│   └── google_apps_script/
│       └── Code.gs
│
├── test/
├── pubspec.yaml
└── README.md
```

Do not create a file/folder merely because a conventional architecture says it should exist. Add structure when it reduces real complexity.

---

# 23. AI-Native Development Principles

This project should be developed as an **AI-native software project**.

That means AI agents are expected to understand product intent, preserve the design rules, and minimize implementation effort.

## Principle 1 — `design.md` is the source of truth

Every coding agent must read this file before changing architecture or implementing a new feature.

## Principle 2 — Understand before coding

Before changing code, the agent should identify:

1. the user goal;
2. the business rule involved;
3. the smallest existing code path that solves it;
4. whether an existing service/component can be reused.

Do not immediately add code.

## Principle 3 — Minimum necessary code

Prefer:

```text
one function over two
one service over multiple layers
one reusable widget over duplicated widgets
one database query over unnecessary data pipelines
```

Do not over-abstract.

## Principle 4 — No speculative features

Do not implement future ideas merely because they might be useful later.

Examples:

```text
No face recognition
No AI chatbot
No recommendation engine
No complex event bus
No microservices
```

## Principle 5 — Business logic belongs in one place

Examples:

- attendance percentage → one attendance calculation service/query;
- name matching → one matching service;
- report generation → one report service;
- alert eligibility → one alert logic path.

Do not duplicate the same formula in multiple screens.

## Principle 6 — AI must preserve human control

The system may assist with speech recognition and candidate matching, but the teacher remains the final authority when a name is ambiguous or an attendance value needs correction.

## Principle 7 — Prefer deterministic behavior

Attendance operations should be predictable.

AI/speech output can be uncertain; database updates should not be.

## Principle 8 — Never hide uncertainty

If recognition is uncertain:

```text
ask teacher
```

Do not guess silently.

## Principle 9 — Reuse before introducing dependencies

Before adding a package, ask:

```text
Can the current Flutter/Supabase stack already solve this?
```

Only add a dependency when it meaningfully reduces complexity or is required for a platform capability.

## Principle 10 — Keep the application understandable

A student developer should be able to explain every major file and data flow during a viva.

---

# 24. AI Agent Operating Contract

Any coding agent working on this repository should follow this sequence.

### Step A — Read context

Read:

```text
design.md
README.md
relevant source files
relevant tests
```

### Step B — State the task internally

Identify:

```text
What user problem am I solving?
What business rule applies?
What is the smallest change required?
```

### Step C — Inspect before creating

Search the repository for existing:

- services;
- models;
- providers;
- widgets;
- SQL functions;
- validation helpers.

Reuse them when appropriate.

### Step D — Implement the smallest complete change

Do not partially duplicate an existing feature.

### Step E — Test the changed behavior

At minimum:

```text
build/analyze
relevant unit/widget tests
manual smoke test if needed
```

### Step F — Update documentation only when behavior changed

Do not rewrite `design.md` for cosmetic changes.

### Step G — Report exactly what changed

The agent should summarize:

- files changed;
- behavior added/fixed;
- tests run;
- remaining issue, if any.

---

# 25. Agent Rules for Database Changes

Database changes are high-impact.

An agent must not casually modify:

- table relationships;
- unique constraints;
- attendance calculation rules;
- RLS policies;
- session semantics.

Before changing the schema, verify whether the requirement can be satisfied in the current schema.

Every schema change should include:

1. migration SQL;
2. reason for change;
3. affected application code;
4. affected tests.

Never put service-role credentials in Flutter code.

---

# 26. Agent Rules for Attendance Logic

Attendance is the core business domain.

Agents must preserve these invariants:

```text
A student has at most one attendance record per session.

A student not marked present remains absent.

A name is not a student identity; PRN/student ID is.

Ambiguous names require teacher selection.

Unknown names do not create attendance automatically.

Attendance percentage is subject-wise.

Historical attendance is never silently overwritten by a later lecture.
```

---

# 27. Agent Rules for UI

The teacher should be able to take attendance quickly.

Therefore:

- the microphone control must be prominent;
- the number of taps should be minimized;
- important information should be visible immediately;
- duplicate-name resolution must be obvious;
- error messages must tell the teacher what to do next;
- desktop/web layout must not dictate a bad mobile experience.

Do not add animations or decorative UI that slows down attendance taking.

---

# 28. Development Plan

Build the system in the following order.

## Phase 0 — Repository foundation

Deliver:

```text
Flutter project
Git repository
basic README
basic design.md
basic theme/routing
```

No advanced features.

## Phase 1 — Supabase foundation

Deliver:

```text
Supabase project
Auth
profiles
classes
subjects
class_subjects
students
enrollments
attendance_sessions
attendance_records
attendance_alerts
```

Add essential indexes, foreign keys, unique constraints, and RLS.

## Phase 2 — Authentication + teacher profile

Deliver:

```text
Login
Create account/profile
Edit profile
Availability slots
```

Acceptance criteria:

- teacher can log in;
- teacher sees only their own data;
- profile persists after refresh/re-login.

## Phase 3 — Classes + subjects

Deliver:

```text
Create class
Create subject
Map subject to class
Configure Google Form
Configure threshold/alert settings
```

Acceptance criteria:

- teacher can manage multiple classes;
- same subject can be attached to multiple classes;
- each class + subject has its own Google Form URL.

## Phase 4 — Student Excel import

Deliver:

```text
Pick XLSX
Validate
Preview
Import
```

Acceptance criteria:

- valid file imports;
- invalid file gives actionable errors;
- imported student count is correct;
- PRNs are handled correctly;
- duplicate PRNs are prevented.

## Phase 5 — Manual attendance core

This phase comes **before voice**.

Deliver:

```text
Start session
All eligible students default absent
Tap student → present
Review
Edit
Finish session
```

Acceptance criteria:

- one session is created per lecture;
- each student gets exactly one record per session;
- cumulative history survives multiple lectures;
- editing works.

## Phase 6 — Cumulative reports

Deliver:

```text
View full history
Attendance totals
Attendance percentage
Excel export
PDF export
```

Acceptance criteria:

- old lectures remain visible;
- a new lecture adds to history;
- reports use the full stored history;
- percentage is correct.

## Phase 7 — Voice attendance

Deliver:

```text
Microphone
Speech-to-text
Exact matching
Safe fuzzy matching
Duplicate-name selection
Unknown-name retry
Duplicate attendance protection
```

Acceptance criteria:

- speaking a unique name marks the correct student;
- duplicate names require selection;
- unknown names do not mark anyone;
- repeated names do not duplicate attendance.

## Phase 8 — Review/edit + audit

Improve:

```text
Search/filter
Edit attendance
Simple audit trail
```

Acceptance criteria:

- teacher can correct wrong marks quickly;
- edits do not create duplicate records.

## Phase 9 — Low-attendance calculation

Deliver:

```text
Low-attendance list
Configurable threshold
Subject-wise percentage
```

Acceptance criteria:

- 75% default works;
- threshold is configurable;
- enrollment dates are respected.

## Phase 10 — Email automation

Deliver:

```text
Google Apps Script
Scheduled check
Alert history
Email generation
Google Form link injection
Teacher availability information
```

Acceptance criteria:

- students below threshold are found;
- students at/above threshold are not emailed;
- repeated emails respect reminder rules;
- correct class-subject form link is used;
- alert history is recorded.

## Phase 11 — Dashboard + polish

Deliver:

```text
Today summary
Classes
Average/subject attendance overview
Below-threshold count
Recent alerts
Responsive layouts
Error states
Loading states
```

Do not add new business features in this phase.

## Phase 12 — Android + web release testing

Deliver:

```text
Web build
Android APK
final test data
project demonstration flow
```

---

# 29. Development Strategy: Build the Core Before the Smart Layer

This is mandatory for keeping the project manageable.

### First prove:

```text
Database
 ↓
Student list
 ↓
Manual attendance
 ↓
Cumulative report
```

### Then add:

```text
Voice
 ↓
Matching
 ↓
Automation
 ↓
Email
```

Voice is only an input method. It should not be responsible for core attendance storage logic.

---

# 30. Testing Strategy

## Unit tests

Test:

- attendance percentage;
- threshold comparison;
- name normalization;
- name matching;
- duplicate detection;
- enrollment eligibility;
- alert eligibility.

## Database tests / SQL checks

Test:

- duplicate attendance constraint;
- teacher data isolation;
- class-subject relationships;
- student enrollment.

## Widget tests

Test:

- login state;
- attendance screen;
- duplicate-name dialog;
- review/edit screen.

## End-to-end smoke test

Use a small fake class:

```text
5–10 students
2 duplicate names
3 lectures
2 low-attendance cases
```

Then test the entire workflow.

---

# 31. Demonstration Scenario

For the final project demonstration, use a controlled dataset.

Example:

```text
Class: BE Computer A
Subject: Ubiquitous Computing
Students: 10
```

Include two students with the same name:

```text
PRN 101 — Rahul Patil
PRN 104 — Rahul Patil
```

### Demo flow

1. Teacher logs in.
2. Teacher opens BE-A.
3. Teacher selects Ubiquitous Computing.
4. Teacher starts attendance.
5. Teacher speaks unique student name.
6. System marks present.
7. Teacher speaks Rahul Patil.
8. System shows two Rahul Patil students.
9. Teacher selects the correct PRN.
10. Teacher accidentally repeats a name.
11. System says the student is already present.
12. Teacher finishes attendance.
13. Teacher edits one mistaken attendance entry.
14. Next lecture is started.
15. Previous lecture remains in history.
16. Teacher opens cumulative report.
17. Report shows all lectures.
18. A student's percentage falls below 75%.
19. Scheduled alert check identifies the student.
20. Email contains attendance details and the class-specific Google Form.

This demonstrates the complete product idea without needing artificial complexity.

---

# 32. Definition of Done for MVP

The MVP is complete when all of the following are true:

```text
[ ] Teacher authentication works
[ ] Teacher profile works
[ ] Multiple classes work
[ ] Multiple subjects work
[ ] Class + subject mapping works
[ ] Google Form can be configured per class + subject
[ ] Excel student import works
[ ] Duplicate PRN validation works
[ ] Attendance session creation works
[ ] Everyone defaults to absent
[ ] Manual present marking works
[ ] Voice name recognition works
[ ] Duplicate/similar names require selection
[ ] Unknown names are handled safely
[ ] Duplicate attendance is prevented
[ ] Teacher can edit attendance
[ ] Attendance history is cumulative
[ ] Subject-wise percentage works
[ ] Enrollment date is respected
[ ] Cumulative Excel report works
[ ] PDF report works
[ ] Low-attendance threshold works
[ ] Alert schedule is configurable
[ ] Alert history prevents unwanted spam
[ ] Email automation works
[ ] Correct Google Form is sent
[ ] Teacher availability is stored
[ ] Android APK works
[ ] Web version works
[ ] Teacher data is isolated through RLS
```

---

# 33. What We Should NOT Do

Do not:

- build separate Android and web codebases;
- use Excel as the primary database;
- create a new attendance database/table for each date;
- make student names unique;
- automatically choose between duplicate names;
- let voice recognition write directly to the database without a safe matching step;
- put secret keys/passwords in Flutter;
- create a custom email server;
- build meeting scheduling now;
- create a large ML model when speech-to-text + matching is sufficient;
- add packages without checking whether existing tools are enough;
- create microservices;
- over-engineer state management;
- make the teacher navigate through many screens during attendance.

---

# 34. Simplicity Rules for Future Changes

When a new feature request arrives, ask:

### Question 1
Does this solve an actual teacher workflow problem?

### Question 2
Is it required for the project scope?

### Question 3
Can it be implemented using the existing architecture?

### Question 4
Can we reuse existing code?

### Question 5
Does the feature increase maintenance significantly?

If a feature is not clearly required, defer it.

---

# 35. Final Mental Model for Any AI Agent

An AI agent working on this project should be able to understand the entire system in one sentence:

> **This is a teacher-only attendance system where each class + subject has a student roster, the teacher speaks present student names, the system safely resolves those names to PRNs, stores each lecture's attendance cumulatively, calculates subject-wise attendance, generates complete reports, and periodically contacts students below the configured 75% threshold with the correct Google Form and teacher information.**

The most important engineering idea is:

```text
Student master
      +
Class/subject enrollment
      +
Lecture sessions
      +
Attendance records
      ↓
Single source of truth
      ↓
Reports + percentages + alerts
```

And the most important AI-development idea is:

```text
Understand → Reuse → Implement minimally → Test → Document
```

Not:

```text
Imagine → Over-engineer → Add dependencies → Write lots of code
```

---

# 36. Source-of-Truth Status

This document represents the current agreed design as of **2026-09-23**.

When requirements change, update this document first, then update implementation.

The implementation must follow the latest approved business rules in this document.

For current package versions, service quotas, and hosting rules, verify official documentation at implementation time because those details can change independently of the project design.

---

# 37. Loose Coupling Is a Core Requirement

This project must be designed so that **one component can be replaced or changed without forcing changes across the whole application**.

This is not just a coding preference. It is a project requirement.

Examples:

```text
Change speech recognition provider
        ↓
Only speech-related code should change

Change Excel package
        ↓
Only Excel adapter should change

Change email provider
        ↓
Only email/automation adapter should change

Change report format
        ↓
Only report generator should change

Change Supabase later
        ↓
Only data-access implementation should change
```

The teacher-facing screens should not know how these systems work internally.

---

# 38. Component Boundaries

Keep the application divided into small modules with clear responsibilities.

```text
                    Flutter UI
                       │
                       ▼
                Feature / Controller
                       │
            ┌──────────┼──────────┐
            │          │          │
            ▼          ▼          ▼
       Attendance   Students   Reports
          Logic       Logic      Logic
            │          │          │
            └──────────┼──────────┘
                       │
                       ▼
                 Small Interfaces
                       │
          ┌────────────┼────────────┐
          │            │            │
          ▼            ▼            ▼
      Data Store    Speech      File/Report
      Interface     Interface     Interface
          │            │            │
          ▼            ▼            ▼
      Supabase    speech_to_text   XLSX/PDF
```

The key idea is:

> **Feature logic depends on an interface, not on a concrete external package.**

---

# 39. Dependency Direction

Dependencies should flow inward toward application logic.

Preferred:

```text
UI
 ↓
Feature Logic
 ↓
Domain/Application Interfaces
 ↓
Infrastructure Adapters
 ↓
External Package / Service
```

Avoid:

```text
UI
 ↓
Supabase directly
 ↓
Speech package directly
 ↓
Excel package directly
 ↓
Google API directly
```

The UI should not become a place where database queries, speech recognition, matching, email rules, and report formatting are mixed together.

---

# 40. Small Interfaces / Adapters

Use simple interfaces where replacement is likely.

## 32.1 StudentRepository

Purpose:

```text
Load students
Create/update students
Find students by class/subject
```

Possible interface:

```dart
abstract class StudentRepository {
  Future<List<Student>> getStudentsForClassSubject(String classSubjectId);
  Future<void> importStudents(List<Student> students);
}
```

Supabase implementation:

```text
SupabaseStudentRepository
```

If storage changes later:

```text
FirebaseStudentRepository
LocalStudentRepository
```

The attendance feature should not need to change.

---

# 41. AttendanceRepository

Purpose:

```text
Create session
Get session
Mark present
Edit status
Complete session
Load attendance history
```

Example:

```dart
abstract class AttendanceRepository {
  Future<AttendanceSession> startSession(String classSubjectId);
  Future<void> markPresent(String sessionId, String studentId, String source);
  Future<void> updateStatus(String sessionId, String studentId, AttendanceStatus status);
  Future<void> completeSession(String sessionId);
}
```

The UI never writes SQL directly.

---

# 42. SpeechService

Speech should be replaceable.

```dart
abstract class SpeechService {
  Future<void> startListening();
  Future<void> stopListening();
  Stream<String> get recognizedText;
  bool get isAvailable;
}
```

Current implementation:

```text
FlutterSpeechService
```

Future implementation could be:

```text
OtherSpeechService
CloudSpeechService
MockSpeechService
```

The matching and attendance modules should not care which speech provider is used.

---

# 43. NameMatcher

Matching is separate from speech recognition.

```dart
abstract class NameMatcher {
  MatchResult match(String recognizedText, List<Student> candidates);
}
```

Possible result types:

```text
SingleMatch
MultipleMatches
NoMatch
```

The matching algorithm can therefore be improved without changing the microphone UI.

---

# 44. ReportGenerator

Reports should be independent from the attendance database.

```dart
abstract class ReportGenerator {
  Future<ReportFile> generateExcel(AttendanceReport report);
  Future<ReportFile> generatePdf(AttendanceReport report);
}
```

The application first creates a neutral `AttendanceReport` model.

Then:

```text
AttendanceReport
      │
      ├── ExcelReportGenerator
      │
      └── PdfReportGenerator
```

Adding another report format should not require changes to attendance logic.

---

# 45. Notification / Email Interface

Email delivery must be isolated.

```dart
abstract class NotificationService {
  Future<SendResult> sendLowAttendanceAlert(LowAttendanceAlert alert);
}
```

Current implementation may use:

```text
GoogleAppsScriptNotificationService
```

A later provider could be:

```text
SupabaseEmailService
ResendNotificationService
OtherEmailService
```

The low-attendance calculation must not know how email is physically delivered.

---

# 46. AlertPolicy

Alert decisions should be separate from email sending.

```text
Attendance data
      ↓
AlertPolicy
      ↓
Should an alert be sent?
      ↓
Yes
      ↓
NotificationService
```

This separation means the rules can change without touching the mail provider.

For example:

```text
Change daily → weekly
```

should only affect scheduling/policy configuration.

---

# 47. File Import Interface

Excel import should also be isolated.

```dart
abstract class StudentImportService {
  Future<ImportPreview> previewStudentFile(FileData file);
  Future<ImportResult> importStudentFile(FileData file);
}
```

The rest of the application should not care whether the source was:

```text
XLSX
CSV
Google Sheet
Manual entry
```

For MVP, only XLSX is required.

---

# 48. Configuration Over Hard-Coding

Settings that the teacher may reasonably change must come from configuration/data rather than source code.

Examples:

```text
Attendance threshold       → database/config
Alert enabled              → database/config
Alert frequency            → database/config
Alert time                 → database/config
Google Form URL            → database/config
Teacher availability       → database/config
Class/subject relationship → database/config
```

Avoid code such as:

```dart
if (attendance < 75) { ... }
```

when the threshold is supposed to be configurable.

Prefer:

```dart
if (attendance < settings.threshold) { ... }
```

---

# 49. Feature Isolation

Each feature should have a clear boundary.

Recommended feature responsibilities:

```text
Auth
 └── Login/session only

Profile
 └── Teacher details + availability

Classes
 └── Classes + subjects + class-subject setup

Students
 └── Student import + student management

Attendance
 └── Sessions + marking + review/editing

Reports
 └── Historical report presentation/export

Alerts
 └── Thresholds + alert status/history
```

A feature should request work from another feature through its public service/interface rather than importing its internal widgets or private implementation.

---

# 50. No Cross-Feature Database Queries From UI

Avoid code like:

```text
AttendanceScreen
   ↓
raw Supabase query
   ↓
profiles
   ↓
classes
   ↓
students
   ↓
attendance
   ↓
alerts
```

Instead:

```text
AttendanceScreen
       ↓
AttendanceController
       ↓
AttendanceRepository
```

If attendance needs student information, the application/service layer obtains it through a focused dependency.

This makes later schema changes much easier.

---

# 51. Avoid Circular Dependencies

Never allow:

```text
Attendance → Reports → Attendance
```

or:

```text
Classes → Students → Classes
```

Prefer one-way dependencies.

Example:

```text
Students
   ↓
Enrollment
   ↓
Attendance
   ↓
Report
```

The report reads attendance; attendance does not depend on report code.

---

# 52. Shared Models Should Be Small

Use shared models for stable concepts:

```text
Teacher
Class
Subject
Student
Enrollment
AttendanceSession
AttendanceRecord
AttendanceReport
Alert
```

Do not create dozens of tiny models unless they solve a real problem.

A model should represent a meaningful concept or boundary.

---

# 53. Keep External Services Behind Adapters

External technologies must remain at the edge of the application.

```text
              APPLICATION
                   │
       ┌───────────┼───────────┐
       │           │           │
       ▼           ▼           ▼
    Supabase     Speech      Reports
    Adapter      Adapter     Adapter
       │           │           │
       ▼           ▼           ▼
   Supabase     Package     XLSX/PDF
```

This is particularly important because external package APIs may change.

---

# 54. Fast Change Principle

Whenever a component needs to change, the expected change surface should be small.

| Requirement Change | Intended Change Area |
|---|---|
| Change colors/theme | `app/theme.dart` + shared widgets |
| Change speech provider | `speech_service.dart` adapter |
| Change name matching | `matching_service.dart` |
| Change Excel format | `excel_service.dart` |
| Add PDF layout | `report_service.dart` / PDF generator |
| Change attendance threshold | Settings/database |
| Change alert frequency | Alert settings/policy |
| Change email provider | Notification adapter |
| Change Google Form | Class-subject record |
| Change teacher slots | Profile/availability feature |
| Change database provider | Repository implementations |
| Add another platform | Flutter platform layer where necessary |

The goal is that **most changes touch one feature or adapter, not the entire project**.

---

# 55. UI Must Not Know Infrastructure Details

Bad:

```dart
onPressed: () async {
  final response = await Supabase.instance.client
      .from('attendance_records')
      .update(...);
}
```

Better:

```dart
onPressed: () {
  attendanceController.markPresent(studentId);
}
```

The screen describes the user action.

The controller/service decides what needs to happen.

The repository decides how data is stored.

This is the separation we want throughout the project.

---

# 56. Keep Controllers Thin

Controllers/providers should coordinate rather than contain the entire business system.

Example:

```text
AttendanceScreen
      ↓
AttendanceController
      ↓
NameMatcher
      ↓
AttendanceRepository
```

Do not put all of the following into one controller:

```text
speech recognition
fuzzy matching
SQL
report generation
email
UI state
```

If a method becomes difficult to explain in one sentence, it is probably doing too much.

---

# 57. Domain Logic Should Be Testable Without Flutter UI

Important business logic should be runnable using plain unit tests.

Examples:

```text
Name matching
Attendance percentage
Alert eligibility
Duplicate attendance detection
Enrollment-date calculation
Report matrix generation
```

This lets AI agents test logic quickly without running the complete application.

---

# 58. Simple Testing Strategy for Loose Coupling

Each replaceable component should have a small test boundary.

Examples:

```text
NameMatcher
 ├── exact match
 ├── duplicate match
 ├── no match
 └── fuzzy match

AttendancePolicy
 ├── 75% → no alert
 ├── 74% → alert
 └── reminder interval

ReportGenerator
 ├── correct date columns
 ├── correct totals
 └── correct percentages
```

For external services, use mocks/fakes in tests.

Example:

```text
FakeSpeechService
FakeAttendanceRepository
FakeNotificationService
```

This allows the UI and business logic to be tested without a real microphone, database, or email provider.

---

# 59. AI-Native Change Workflow

When an AI agent receives a feature request, it must first identify the smallest change boundary.

Example request:

> “Replace the speech recognition package.”

Agent should reason:

```text
Speech implementation is isolated.
        ↓
Replace SpeechService adapter.
        ↓
Run speech-related tests.
        ↓
Do not modify attendance database/UI unless required.
```

Example request:

> “Change the attendance threshold to 80% for one subject.”

Agent should reason:

```text
Threshold is configuration.
        ↓
Update class_subject setting.
        ↓
Do not change attendance calculation code.
```

Example request:

> “Change Excel column order.”

Agent should reason:

```text
Import/export formatting concern.
        ↓
Change Excel adapter only.
        ↓
Do not touch attendance storage.
```

---

# 60. AI Agent Anti-Patterns

Agents must avoid:

### Giant service classes

```text
EverythingService
```

### Giant widgets

A single screen containing authentication, database queries, business logic, and formatting.

### Duplicate business logic

The same attendance percentage formula implemented in multiple screens.

### Direct external API usage everywhere

Scattering Supabase queries or package calls throughout the UI.

### Premature abstraction

Do not create interfaces for every class just to follow a pattern.

Use abstraction specifically where replacement, testing, or boundary clarity matters.

### Overengineering

Do not introduce:

```text
Redux
BLoC + Riverpod together
multiple API layers
microservices
message brokers
Docker orchestration
Kubernetes
```

unless a future requirement actually demands them.

---

# 61. Practical Modularity Rule

A simple rule for the whole project:

> **One module should have one clear reason to change.**

For example:

```text
speech_service.dart
→ changes when speech behavior/provider changes

matching_service.dart
→ changes when student-name matching changes

attendance_service.dart
→ changes when attendance rules change

report_service.dart
→ changes when report structure changes

notification_service.dart
→ changes when email delivery changes
```

If one file regularly changes for five unrelated reasons, split it.

If splitting two files creates unnecessary complexity, keep them together.

The objective is maintainability, not architectural decoration.

---

# 62. Minimal Integration Points

The whole MVP should have a small number of meaningful integration points:

```text
1. Auth
2. Database
3. Speech input
4. Student matching
5. Attendance logic
6. Report generation
7. Alert automation
8. Email delivery
9. Google Form link
```

Each integration point should be isolated.

This gives the system a small and understandable architecture while keeping future replacement easy.

---

# 63. Updated High-Level Architecture

```text
                           FLUTTER APP
                      Android + Web
                             │
                     ┌───────┴───────┐
                     │   UI Layer   │
                     └───────┬───────┘
                             │
                    Feature Controllers
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
         Attendance       Students        Reports
           Logic            Logic           Logic
              │              │              │
              └──────────────┼──────────────┘
                             │
                    Application Interfaces
                             │
       ┌─────────────┬───────┼───────┬─────────────┐
       │             │       │       │             │
       ▼             ▼       ▼       ▼             ▼
   Repository      Speech  Matcher  Report      Notification
   Interfaces     Service Service  Generator      Service
       │             │       │       │             │
       ▼             ▼       ▼       ▼             ▼
   Supabase       Speech    Name   XLSX/PDF    Apps Script/
   Adapter        Adapter  Logic   Adapters      Gmail
       │
       ▼
   PostgreSQL
```

---

# 64. Implementation Rule: Build Vertically, Not Horizontally

When adding a feature, implement the smallest complete user journey instead of building every layer separately first.

Example:

```text
Upload Excel
   ↓
validate
   ↓
preview
   ↓
import
   ↓
show imported students
```

Then move to the next journey.

For attendance:

```text
Start session
   ↓
Speak name
   ↓
Match
   ↓
Mark present
   ↓
Review
   ↓
Save
```

This lets the AI agent verify working behavior continuously.

---

# 65. Recommended Implementation Sequence — Updated

The project should be developed in small vertical slices.

## Slice 1 — Foundation

```text
Flutter
Supabase
Routing
Theme
Environment configuration
```

## Slice 2 — Teacher

```text
Auth
Profile
Availability
```

## Slice 3 — Class Setup

```text
Class
Subject
Class-subject
Google Form
Threshold/alert settings
```

## Slice 4 — Student Import

```text
XLSX selection
Validation
Preview
Import
Student list
```

## Slice 5 — Manual Attendance

```text
Start session
Default absent
Mark present manually
Review
Finish
```

## Slice 6 — Cumulative History

```text
Multiple sessions
Attendance calculation
History screen
Complete report
```

## Slice 7 — Voice

```text
Speech adapter
Name matching
Duplicate-name selection
No-match handling
Duplicate protection
```

## Slice 8 — Editing + Audit

```text
Manual correction
Audit history
```

## Slice 9 — Reports

```text
Excel export
PDF export
```

## Slice 10 — Alerts

```text
Low-attendance calculation
Alert policy
Alert history
```

## Slice 11 — Email Automation

```text
Google Apps Script
Scheduled trigger
Email template
Google Form link
Teacher availability
```

## Slice 12 — Final UI Polish

```text
Dashboard
Analytics
Responsive web layout
Android layout refinement
```

---

# 66. Definition of Done for Each Feature

A feature is not complete merely because code compiles.

For each feature, AI agents should verify:

```text
✓ User flow works
✓ Business rule is preserved
✓ Error case is handled
✓ No duplicate logic introduced
✓ External dependency is isolated
✓ Relevant test exists
✓ UI works on mobile
✓ UI works on web where supported
```

Do not require every feature to have a huge test suite. Test the business-critical paths.

---

# 67. Environment Configuration

Keep environment-dependent values outside business code.

Examples:

```text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
EMAIL_AUTOMATION_ENDPOINT
APP_ENV
```

Never hard-code private credentials into source files.

Use separate configuration for:

```text
local development
web testing
production/demo
```

where necessary.

---

# 68. Simple Repository Strategy

Use Git with small, understandable commits.

Preferred commit style:

```text
feat: add student Excel import
feat: add attendance sessions
feat: add voice name matching
fix: prevent duplicate attendance
feat: add cumulative report
feat: add low attendance alerts
```

Avoid giant commits containing unrelated changes.

This makes AI-assisted development safer because an agent can understand what changed and revert a focused change when needed.

---

# 69. Final Design Principle

The project should feel like a collection of **small replaceable building blocks**, not one giant application.

```text
                 SMART ATTENDANCE
                        │
       ┌────────────────┼────────────────┐
       │                │                │
   Teacher UI      Attendance Core    Alert Core
       │                │                │
       │                │                │
    Replaceable      Replaceable      Replaceable
       │                │                │
       ▼                ▼                ▼
   UI widgets       Storage adapter   Email adapter
   Web/Android      Speech adapter    Scheduler
                   Matching adapter
                   Report adapter
```

The system should remain useful even when an individual implementation changes.

**Core principle:**

> **Keep business logic stable, keep infrastructure replaceable, keep features independent, and keep each change local.**

That principle should guide every future AI-generated code change in this repository.
