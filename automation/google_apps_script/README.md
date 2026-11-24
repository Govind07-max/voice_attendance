# Low-Attendance Email Automation

To send a real low-attendance email to `govindsr051@gmail.com`, follow
[`SEND_TEST_EMAIL.md`](SEND_TEST_EMAIL.md).

This folder contains the scheduled email sender for the Smart Attendance app. It runs entirely in
Google Apps Script, so the Flutter app does not need to be open. Delivery results are written to
Supabase and appear in **Alerts → Email History**.

## Prerequisites

- The production schema from `supabase/migrations/` is applied.
- Students have valid email addresses.
- Each class + subject has a Google Form URL, threshold, and alert schedule configured.
- You have the Supabase **service-role key**. Keep it only in Apps Script Script Properties; never
  put it in the Flutter app, `.env`, git, or screenshots.

## Deploy

1. Open <https://script.google.com> and create a standalone project.
2. Replace the contents of `Code.gs` with this folder's `Code.gs`.
3. Open **Project Settings → Script Properties** and add:

   | Property | Value |
   |---|---|
   | `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
   | `SUPABASE_SERVICE_ROLE_KEY` | Supabase service-role key |
   | `TEST_EMAIL` | Optional. Receives only `sendTestLowAttendanceEmail()` (use `govindsr051@gmail.com` for the test run) |

4. In the Apps Script editor, select and run:

   ```text
   installLowAttendanceTrigger
   ```

   Authorize the script when Google prompts. This installs one time-driven trigger that runs
   `checkAndSendLowAttendanceAlerts` every 15 minutes.

5. Verify delivery:

   ```text
   sendTestLowAttendanceEmail
   ```

   Confirm the test message arrives, including in spam.

6. Preview real recipients without sending:

   ```text
   previewLowAttendanceAlerts
   ```

   Review **Executions** logs. Nothing is emailed and no history row is written; the log lists the
   students who would receive an alert.

7. To run a real check immediately without waiting for the schedule:

   ```text
   runLowAttendanceCheckNow
   ```

   This still respects per-student reminder anti-spam.

> Upgrading an older deployment? Paste the current `Code.gs`, then run
> `installLowAttendanceTrigger` again. It removes any old daily trigger and installs the current
> 15-minute trigger.

## Schedule behavior

The script runs frequently but only processes a class + subject when its configured schedule is due:

| Setting | Behavior |
|---|---|
| `alert_frequency = daily` | Once per local day at/after `alert_time` |
| `alert_frequency = weekly` | Once on `weekly_day` (1 = Monday) at/after `alert_time` |
| `alert_frequency = biweekly` | Once every `interval_days` (minimum 14) at/after `alert_time` |
| `reminder_days` | Prevents re-emailing the same below-threshold student too soon |
| Teacher timezone | All schedule times use `profiles.timezone` |
| Alert toggle | `alert_enabled = false` skips the class + subject entirely |
| Active flag | `active = false` skips the class + subject entirely |

If a student recovers to at/above the threshold and later falls below it again, the next message is
treated as a fresh **initial** alert rather than being suppressed as a reminder.

The last successful schedule run per class + subject is stored in Apps Script **Script Properties**
under `low_attendance_schedule_<class-subject-id>`. Email anti-spam history remains in the
`attendance_alerts` table.

## Delivery history

Each attempt is written before sending:

1. `pending` row created.
2. Email sent through `MailApp`.
3. Row updated to `sent`, or `failed` with `error_message`.

Because the pending row is created first, a crash after sending does not cause repeated emails on
the next run. Teachers can see `PENDING`, `SENT`, or `FAILED` in the app's Email History tab.

## Quotas and sender identity

- `MailApp` sends from the Google account that owns the Apps Script project.
- Consumer Gmail and Google Workspace accounts have daily email quotas. Check Google's current
  Apps Script quotas before a large rollout.
- Invalid student email addresses are skipped. The app marks those students in **At Risk Now**.
- The first run must be authorized manually; a trigger cannot grant OAuth consent.

## Troubleshooting

| Symptom | Check |
|---|---|
| `Set the SUPABASE_URL...` | Script Properties missing or still placeholders |
| No emails at all | Run `logLowAttendanceAutomationStatus`; confirm the trigger exists and the class is DUE |
| `Authorization is required` | Run any function manually and complete Google's consent screen |
| Emails in spam | Add the sender to contacts and review the test email |
| `FAILED` rows | Open the row in the app to read `error_message`; check Gmail quota and student addresses |
| Wrong send time | Confirm the teacher profile timezone and the class `alert_time` |
| Weekly email did not arrive | Confirm `weekly_day` uses 1 = Monday through 7 = Sunday |

To force a class to be considered on its next trigger, delete its
`low_attendance_schedule_<class-subject-id>` script property, or run
`runLowAttendanceCheckNow`.

## Local automated tests

No Google account is needed for the test suite. It loads `Code.gs` in a sandbox and mocks Supabase,
`MailApp`, triggers, properties, and time:

```bash
node --test test/automation/low_attendance_automation_test.js
```

The tests cover delivery, schedule windows, timezone, weekly/bi-weekly intervals, reminder
anti-spam, recovery cycles, missing emails, failed sends, dry runs, and trigger installation. The
mock harness uses `govindsr051@gmail.com` as the below-threshold student's email and as `TEST_EMAIL`,
and includes a low-attendance delivery assertion to that address. No real Gmail message is sent by
`node --test`; real delivery requires running `runLowAttendanceCheckNow()` in your own authorized
Apps Script project.
