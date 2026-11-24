const test = require('node:test');
const assert = require('node:assert/strict');

const { createHarness, baseData } = require('./gas_harness');

const WED_10AM_IST = '2026-11-18T04:30:00Z';

function scheduleProperty(harness, lastRunAt) {
  harness.properties.set(
    'low_attendance_schedule_cs1',
    JSON.stringify({ lastRunAt, version: 1 }),
  );
}

test('sends an email to a below-threshold student and logs it as sent', () => {
  const harness = createHarness({ now: WED_10AM_IST, data: baseData() });

  const result = harness.automation.checkAndSendLowAttendanceAlerts();

  assert.equal(result.sent, 1);
  assert.equal(result.failed, 0);
  assert.equal(harness.sentEmails.length, 1);

  const email = harness.sentEmails[0];
  assert.equal(email.to, 'govindsr051@gmail.com');
  assert.match(email.subject, /Ubiquitous Computing/);
  assert.match(email.body, /50%/);
  assert.match(email.body, /https:\/\/forms\.gle\/class-form/);
  assert.match(email.body, /Prof\. Patil/);
  assert.match(email.body, /Monday: 10:00 AM - 11:00 AM/);
  assert.match(email.htmlBody, /Open Attendance Form/);
  assert.match(email.htmlBody, /BE Computer A/);

  assert.equal(harness.data.alerts.length, 1);
  assert.equal(harness.data.alerts[0].status, 'sent');
  assert.equal(harness.data.alerts[0].alert_type, 'initial');
  assert.equal(harness.data.alerts[0].attendance_percent, 50);
  assert.ok(harness.properties.get('low_attendance_schedule_cs1'));
});

test('sends a low-attendance email to govindsr051@gmail.com and logs it', () => {
  const harness = createHarness({ now: WED_10AM_IST, data: baseData() });

  const result = harness.automation.checkAndSendLowAttendanceAlerts();

  assert.equal(result.sent, 1);
  assert.equal(harness.sentEmails.length, 1);
  const email = harness.sentEmails[0];
  assert.equal(email.to, 'govindsr051@gmail.com');
  assert.match(email.subject, /Low attendance alert/);
  assert.match(email.subject, /50%/);
  assert.match(email.body, /50%/);
  assert.equal(harness.data.alerts.length, 1);
  assert.equal(harness.data.alerts[0].status, 'sent');
  assert.equal(harness.data.alerts[0].student_id, 'stu-1');
});

test('sendTestLowAttendanceEmail sends to the configured TEST_EMAIL', () => {
  const harness = createHarness({ now: WED_10AM_IST, data: baseData() });
  harness.properties.set('TEST_EMAIL', 'govindsr051@gmail.com');

  harness.automation.sendTestLowAttendanceEmail();

  assert.equal(harness.sentEmails.length, 1);
  const email = harness.sentEmails[0];
  assert.equal(email.to, 'govindsr051@gmail.com');
  assert.match(email.subject, /^\[TEST\] Low attendance alert/);
  assert.match(email.body, /Test Student/);
  assert.match(email.body, /62\.5%/);
  // The manual test email must not create an alert-history row.
  assert.equal(harness.data.alerts.length, 0);
});

test('daily schedule sends only once per local day', () => {
  const harness = createHarness({ now: WED_10AM_IST, data: baseData() });

  harness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(harness.sentEmails.length, 1);

  harness.setNow('2026-11-18T04:45:00Z');
  const second = harness.automation.checkAndSendLowAttendanceAlerts();

  assert.equal(second.due, 0);
  assert.equal(second.sent, 0);
  assert.equal(harness.sentEmails.length, 1);
  assert.equal(harness.data.alerts.length, 1);
});

test('does not send before the configured local alert time', () => {
  const harness = createHarness({
    now: '2026-11-18T03:00:00Z', // 08:30 IST
    data: baseData(),
  });

  const before = harness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(before.sent, 0);
  assert.equal(harness.sentEmails.length, 0);

  harness.setNow('2026-11-18T03:31:00Z'); // 09:01 IST
  const after = harness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(after.sent, 1);
  assert.equal(harness.sentEmails.length, 1);
});

test('weekly schedule waits for the configured weekday', () => {
  const data = baseData();
  data.classSubjects[0].alert_frequency = 'weekly';
  data.classSubjects[0].weekly_day = 1; // Monday
  const harness = createHarness({ now: WED_10AM_IST, data });

  const wednesday = harness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(wednesday.due, 0);
  assert.equal(harness.sentEmails.length, 0);

  harness.setNow('2026-11-23T04:30:00Z'); // Monday 10:00 IST
  const monday = harness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(monday.sent, 1);
  assert.equal(harness.sentEmails.length, 1);
});

test('biweekly schedule honors interval_days', () => {
  const data = baseData();
  data.classSubjects[0].alert_frequency = 'biweekly';
  data.classSubjects[0].interval_days = 14;
  const harness = createHarness({ now: WED_10AM_IST, data });

  scheduleProperty(harness, '2026-11-08T04:30:00Z'); // 10 days ago
  const tooEarly = harness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(tooEarly.due, 0);
  assert.equal(harness.sentEmails.length, 0);

  scheduleProperty(harness, '2026-11-03T04:30:00Z'); // 15 days ago
  const due = harness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(due.sent, 1);
  assert.equal(harness.sentEmails.length, 1);
});

test('respects reminder_days anti-spam and sends a reminder after it elapses', () => {
  const absentRecords = [
    { session_id: 'sess-1', student_id: 'stu-1', status: 'absent' },
    { session_id: 'sess-2', student_id: 'stu-1', status: 'absent' },
  ];
  const recent = baseData({
    records: absentRecords,
    alerts: [
      {
        id: 'old-alert',
        class_subject_id: 'cs1',
        student_id: 'stu-1',
        attendance_percent: 0,
        attended_count: 0,
        conducted_count: 2,
        alert_type: 'initial',
        status: 'sent',
        sent_at: '2026-11-17T04:30:00Z', // 1 day ago
      },
    ],
  });
  const harness = createHarness({ now: WED_10AM_IST, data: recent });

  harness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(harness.sentEmails.length, 0);

  const old = baseData({
    records: absentRecords,
    alerts: [
      {
        id: 'old-alert',
        class_subject_id: 'cs1',
        student_id: 'stu-1',
        attendance_percent: 0,
        attended_count: 0,
        conducted_count: 2,
        alert_type: 'initial',
        status: 'sent',
        sent_at: '2026-11-08T04:30:00Z', // 10 days ago
      },
    ],
  });
  const reminderHarness = createHarness({ now: WED_10AM_IST, data: old });

  const result = reminderHarness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(result.sent, 1);
  assert.equal(reminderHarness.data.alerts.length, 2);
  const latest = reminderHarness.data.alerts.find((a) => a.id !== 'old-alert');
  assert.equal(latest.alert_type, 'reminder');
  assert.equal(latest.status, 'sent');
});

test('a recovery followed by a new drop starts a fresh initial alert cycle', () => {
  const data = baseData({
    sessions: [
      {
        id: 'sess-1',
        class_subject_id: 'cs1',
        lecture_date: '2026-11-10',
        period_number: 1,
        status: 'completed',
      },
      {
        id: 'sess-2',
        class_subject_id: 'cs1',
        lecture_date: '2026-11-11',
        period_number: 1,
        status: 'completed',
      },
      {
        id: 'sess-3',
        class_subject_id: 'cs1',
        lecture_date: '2026-11-12',
        period_number: 1,
        status: 'completed',
      },
      {
        id: 'sess-4',
        class_subject_id: 'cs1',
        lecture_date: '2026-11-13',
        period_number: 1,
        status: 'completed',
      },
      {
        id: 'sess-5',
        class_subject_id: 'cs1',
        lecture_date: '2026-11-14',
        period_number: 1,
        status: 'completed',
      },
    ],
    records: [
      { session_id: 'sess-1', student_id: 'stu-1', status: 'absent' },
      { session_id: 'sess-2', student_id: 'stu-1', status: 'present' },
      { session_id: 'sess-3', student_id: 'stu-1', status: 'present' },
      { session_id: 'sess-4', student_id: 'stu-1', status: 'present' },
      { session_id: 'sess-5', student_id: 'stu-1', status: 'absent' },
    ],
    alerts: [
      {
        id: 'old-alert',
        class_subject_id: 'cs1',
        student_id: 'stu-1',
        attendance_percent: 0,
        attended_count: 0,
        conducted_count: 1,
        alert_type: 'initial',
        status: 'sent',
        sent_at: '2026-11-10T12:00:00Z',
      },
    ],
  });
  data.classSubjects[0].reminder_days = 30;

  const harness = createHarness({ now: WED_10AM_IST, data });
  const result = harness.automation.checkAndSendLowAttendanceAlerts();

  assert.equal(result.sent, 1);
  assert.equal(harness.sentEmails.length, 1);
  assert.equal(harness.data.alerts[1].alert_type, 'initial');
  assert.equal(harness.data.alerts[1].attendance_percent, 60);
});

test('failed MailApp delivery is recorded as failed with an error message', () => {
  const harness = createHarness({ now: WED_10AM_IST, data: baseData() });
  harness.setMailError('Service invoked too many times: email');

  const result = harness.automation.checkAndSendLowAttendanceAlerts();

  assert.equal(result.sent, 0);
  assert.equal(result.failed, 1);
  assert.equal(harness.data.alerts.length, 1);
  assert.equal(harness.data.alerts[0].status, 'failed');
  assert.match(harness.data.alerts[0].error_message, /too many times/);
  assert.ok(result.errors.some((message) => /failed/.test(message)));
});

test('students without a valid email are skipped without a history row', () => {
  const data = baseData();
  data.enrollments[0].students.email = '';
  const harness = createHarness({ now: WED_10AM_IST, data });

  const result = harness.automation.checkAndSendLowAttendanceAlerts();

  assert.equal(result.sent, 0);
  assert.equal(result.missingEmail, 1);
  assert.equal(harness.sentEmails.length, 0);
  assert.equal(harness.data.alerts.length, 0);
});

test('dry run reports would-send without emailing or writing rows', () => {
  const harness = createHarness({ now: WED_10AM_IST, data: baseData() });

  const result = harness.automation.previewLowAttendanceAlerts();

  assert.equal(result.dryRun, true);
  assert.equal(result.wouldSend, 1);
  assert.equal(result.wouldSendDetails.length, 1);
  assert.equal(result.wouldSendDetails[0].studentName, 'Aarav Sharma');
  assert.equal(result.wouldSendDetails[0].email, 'govindsr051@gmail.com');
  assert.equal(result.sent, 0);
  assert.equal(harness.sentEmails.length, 0);
  assert.equal(harness.data.alerts.length, 0);
  assert.equal(harness.properties.has('low_attendance_schedule_cs1'), false);
});

test('students exactly at the threshold are not emailed', () => {
  const data = baseData();
  data.classSubjects[0].threshold_percent = 50;
  const harness = createHarness({ now: WED_10AM_IST, data });

  const result = harness.automation.checkAndSendLowAttendanceAlerts();

  assert.equal(result.sent, 0);
  assert.equal(harness.sentEmails.length, 0);
  assert.equal(harness.data.alerts.length, 0);
});

test('evaluates alert time in the teacher timezone', () => {
  const data = baseData();
  data.classSubjects[0].profiles.timezone = 'America/New_York';
  const harness = createHarness({
    now: '2026-11-18T13:30:00Z', // 08:30 EST
    data,
  });

  const before = harness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(before.sent, 0);

  harness.setNow('2026-11-18T14:01:00Z'); // 09:01 EST
  const after = harness.automation.checkAndSendLowAttendanceAlerts();
  assert.equal(after.sent, 1);
});

test('disabled alert settings skip the class entirely', () => {
  const data = baseData();
  data.classSubjects[0].alert_enabled = false;
  const harness = createHarness({ now: WED_10AM_IST, data });

  const result = harness.automation.checkAndSendLowAttendanceAlerts();

  assert.equal(result.classSubjects, 0);
  assert.equal(result.sent, 0);
  assert.equal(harness.sentEmails.length, 0);
});

test('installLowAttendanceTrigger replaces duplicates with one 15-minute trigger', () => {
  const harness = createHarness({ now: WED_10AM_IST, data: baseData() });

  harness.automation.installLowAttendanceTrigger();
  harness.automation.installLowAttendanceTrigger();

  assert.equal(harness.triggers.length, 1);
  assert.equal(
    harness.triggers[0].getHandlerFunction(),
    'checkAndSendLowAttendanceAlerts',
  );
  assert.equal(harness.triggers[0].minutes, 15);
});

test('email renderer handles 100 percent formatting and missing form links safely', () => {
  const harness = createHarness({ now: WED_10AM_IST, data: baseData() });
  const email = harness.automation.buildLowAttendanceEmail_({
    studentName: 'Test <Student>',
    prn: '101',
    className: 'BE A',
    subjectName: 'DBMS',
    percentage: 100,
    attendedCount: 10,
    conductedCount: 10,
    threshold: 100,
    formUrl: 'javascript:alert(1)',
    teacherName: 'Prof. Patil',
    teacherEmail: 'patil@example.edu',
    teacherDepartment: 'Computer',
    availability: [],
  });

  assert.match(email.body, /100%/);
  assert.doesNotMatch(email.body, /javascript:/);
  assert.match(email.htmlBody, /Test &lt;Student&gt;/);
  assert.match(email.htmlBody, /No attendance form link/);
  assert.equal(harness.automation.isValidEmail_('not-an-email'), false);
});
