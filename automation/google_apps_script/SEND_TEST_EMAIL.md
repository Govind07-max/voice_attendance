# Send a real low-attendance email to `govindsr051@gmail.com`

This uses the real student-alert path (not the sample `TEST_EMAIL` message). The recipient is the
student record's email.

## 1. Create the low-attendance student

In the Flutter app:

1. Open **Classes** → the class + subject you want to test with.
2. Open the **Students** roster and tap **+** (Manual Add).
3. Enter:
   - PRN: `TEST-GOVIND`
   - Name: `Test Low Attendance Student`
   - Email: `govindsr051@gmail.com`
4. Take and finalize two lectures for that class:
   - Lecture 1: mark the student **present**
   - Lecture 2: mark the student **absent**
5. Final attendance = **50%**, which is below the default 75% threshold.

Make sure the class + subject has:

- **Send Alerts** enabled
- Threshold `75`
- Frequency **daily**
- Alert time at or before the current local time
- Reminder interval small enough that a previous test alert does not suppress this one

## 2. Configure Google Apps Script

1. Open your Apps Script project and paste the current `Code.gs`.
2. **Project Settings → Script Properties**:

   | Property | Value |
   |---|---|
   | `SUPABASE_URL` | your project URL |
   | `SUPABASE_SERVICE_ROLE_KEY` | service-role key |
   | `TEST_EMAIL` | `govindsr051@gmail.com` (optional; only for `sendTestLowAttendanceEmail`) |

3. Run `installLowAttendanceTrigger` once and complete Google's authorization prompt.

## 3. Send

1. Run `previewLowAttendanceAlerts` first. In **Executions**, confirm the student with
   `govindsr051@gmail.com` is listed as a would-send recipient.
2. Run `runLowAttendanceCheckNow`.
3. Check the student's inbox and spam folder.
4. In the Flutter app, open **Alerts → Email History**. A `SENT` row should appear for
   `Test Low Attendance Student` with attendance `50%`.

## If no email arrives

- Run `logLowAttendanceAutomationStatus` and confirm the class is **DUE**.
- Confirm the student's email is exactly `govindsr051@gmail.com` (no spaces).
- Confirm a recent `attendance_alerts` row is not suppressing it via `reminder_days`.
- Delete the class's `low_attendance_schedule_<class-subject-id>` script property, then run
  `runLowAttendanceCheckNow` again.
- Check Apps Script **Executions** for quota or authorization errors.
