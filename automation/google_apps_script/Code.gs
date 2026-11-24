/**
 * Smart Attendance Ubiquitous System - Low-Attendance Email Automation
 * File: Code.gs
 *
 * Production setup
 * ----------------
 * 1. Open Google Apps Script (https://script.google.com) and paste this file.
 * 2. Add the script properties (Project Settings > Script Properties):
 *      SUPABASE_URL              = https://<project-ref>.supabase.co
 *      SUPABASE_SERVICE_ROLE_KEY = <service-role key>
 *      TEST_EMAIL                = optional address for sendTestLowAttendanceEmail()
 *
 *    The service-role key bypasses RLS. It must live only in Apps Script,
 *    never in the Flutter app and never in git.
 *  
 * 3. Run installLowAttendanceTrigger() once and authorize the script. This
 *    creates a 15-minute time-driven trigger for checkAndSendLowAttendanceAlerts().
 *    The script itself decides whether each class + subject is due, so a
 *    frequent trigger does not mean frequent emails.
 *
 * 4. Run sendTestLowAttendanceEmail() to verify MailApp delivery. Then run
 *    previewLowAttendanceAlerts() to see what the scheduler would send without
 *    writing or emailing anything.
 *
 * Schedule semantics
 * ------------------
 * - Times are evaluated in the teacher's profile timezone.
 * - daily    : once per local day, at or after alert_time.
 * - weekly   : once on weekly_day (1=Monday ... 7=Sunday), at or after alert_time.
 * - biweekly : once every interval_days (minimum 14), at or after alert_time.
 * - reminder_days prevents re-emailing a student too soon.
 * - The last successful schedule run is stored in Script Properties. Email
 *   history in attendance_alerts remains the source of truth for anti-spam.
 *
 * All email attempts are recorded as pending -> sent/failed in attendance_alerts,
 * so the Flutter app's Email History screen shows real delivery outcomes.
 */

var FUNCTION_NAME = 'checkAndSendLowAttendanceAlerts';
var SCHEDULE_PROPERTY_PREFIX = 'low_attendance_schedule_';
var DEFAULT_TIMEZONE = 'Asia/Kolkata';
var DEFAULT_ALERT_TIME = '09:00:00';
var DEFAULT_THRESHOLD = 75;
var DEFAULT_REMINDER_DAYS = 7;
var EMAIL_SENDER_NAME = 'Smart Attendance';
var LOCK_WAIT_MS = 30000;
var RUN_BUDGET_MS = 4.5 * 60 * 1000;
var DAY_NAMES = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

/**
 * Scheduled entry point. Safe to run frequently: each class + subject is only
 * processed when its configured schedule is due.
 */
function checkAndSendLowAttendanceAlerts() {
  return runLowAttendanceCheck_({ now: new Date(), dryRun: false, force: false });
}

/**
 * Manual "run now" entry point. This still respects per-student anti-spam
 * history, but ignores the class-level frequency/time gate.
 */
function runLowAttendanceCheckNow() {
  var result = runLowAttendanceCheck_({ now: new Date(), dryRun: false, force: true });
  Logger.log('Manual low-attendance run finished: ' + JSON.stringify(result));
  return result;
}

/**
 * Dry run: no emails are sent and no rows are written. Useful before enabling
 * alerts for a real class.
 */
function previewLowAttendanceAlerts() {
  var result = runLowAttendanceCheck_({ now: new Date(), dryRun: true, force: true });
  Logger.log('Low-attendance preview: ' + JSON.stringify(result));
  return result;
}

/**
 * Creates exactly one 15-minute trigger for the scheduled check. Running this
 * again is safe; existing triggers for the same handler are replaced.
 */
function installLowAttendanceTrigger() {
  var existing = ScriptApp.getProjectTriggers();
  var removed = 0;
  for (var i = 0; i < existing.length; i++) {
    if (existing[i].getHandlerFunction() === FUNCTION_NAME) {
      ScriptApp.deleteTrigger(existing[i]);
      removed++;
    }
  }

  ScriptApp.newTrigger(FUNCTION_NAME)
    .timeBased()
    .everyMinutes(15)
    .create();

  Logger.log(
    'Low-attendance trigger installed (replaced ' + removed +
    ' existing trigger(s)). Checks run every 15 minutes and the script only ' +
    'emails classes whose configured schedule is due.'
  );
}

/** Sends a sample low-attendance email to TEST_EMAIL. Never emails students. */
function sendTestLowAttendanceEmail() {
  var to = getConfig_('TEST_EMAIL', '');
  if (!to) {
    throw new Error('Set the TEST_EMAIL script property before running this function.');
  }
  if (!isValidEmail_(to)) {
    throw new Error('TEST_EMAIL is not a valid email address.');
  }

  var email = buildLowAttendanceEmail_({
    studentName: 'Test Student',
    prn: 'TEST-001',
    className: 'BE Computer A',
    subjectName: 'Ubiquitous Computing',
    percentage: 62.5,
    attendedCount: 5,
    conductedCount: 8,
    threshold: 75,
    formUrl: 'https://forms.gle/example',
    teacherName: 'Faculty Member',
    teacherEmail: 'faculty@example.edu',
    teacherDepartment: 'Computer Engineering',
    availability: ['Monday: 10:00 AM - 11:00 AM']
  });

  MailApp.sendEmail({
    to: to,
    subject: '[TEST] ' + email.subject,
    body: email.body,
    htmlBody: email.htmlBody,
    name: EMAIL_SENDER_NAME
  });

  Logger.log('Test low-attendance email sent to ' + to + '. Check the inbox and spam folder.');
}

/**
 * Logs configuration, trigger, and schedule status. Helpful when deploying.
 */
function logLowAttendanceAutomationStatus() {
  var config = getSupabaseConfig_();
  var triggers = ScriptApp.getProjectTriggers().filter(function (trigger) {
    return trigger.getHandlerFunction() === FUNCTION_NAME;
  });

  Logger.log('Supabase URL configured: ' + (config.url ? 'yes' : 'no'));
  Logger.log('Active ' + FUNCTION_NAME + ' triggers: ' + triggers.length);
  Logger.log('Script timezone: ' + getScriptTimeZone_());

  var classSubjects = fetchClassSubjects_(config);
  for (var i = 0; i < classSubjects.length; i++) {
    var cs = classSubjects[i];
    var profile = firstRelated_(cs.profiles) || {};
    var timezone = safeTimeZone_(profile.timezone || DEFAULT_TIMEZONE);
    var schedule = evaluateAlertSchedule_(
      cs,
      new Date(),
      readScheduleState_(cs.id),
      timezone
    );
    Logger.log(
      (cs.classes ? cs.classes.class_name : cs.class_id) + ' / ' +
      (cs.subjects ? cs.subjects.subject_name : cs.subject_id) +
      ' -> ' + (schedule.due ? 'DUE' : 'waiting') +
      ' (' + schedule.reason + ', ' + schedule.frequency + ')'
    );
  }
}

// ---------------------------------------------------------------------------
// Main scheduler
// ---------------------------------------------------------------------------

function runLowAttendanceCheck_(options) {
  options = options || {};
  var now = options.now || new Date();
  var dryRun = options.dryRun === true;
  var force = options.force === true;
  var config = getSupabaseConfig_();
  var result = {
    startedAt: now.toISOString(),
    dryRun: dryRun,
    forced: force,
    classSubjects: 0,
    due: 0,
    sent: 0,
    failed: 0,
    skipped: 0,
    missingEmail: 0,
    wouldSend: 0,
    wouldSendDetails: [],
    infrastructureFailure: false,
    errors: []
  };

  var lock = null;
  if (!dryRun) {
    lock = LockService.getScriptLock();
    if (!lock.tryLock(LOCK_WAIT_MS)) {
      result.locked = true;
      Logger.log('Low-attendance check skipped: another run is still active.');
      return result;
    }
  }

  try {
    var classSubjects = fetchClassSubjects_(config);
    result.classSubjects = classSubjects.length;

    var deadline = now.getTime() + RUN_BUDGET_MS;
    var availabilityCache = {};

    for (var i = 0; i < classSubjects.length; i++) {
      if (Date.now() > deadline) {
        result.timeBudgetExceeded = true;
        result.errors.push('Stopped before all classes were processed to stay within the Apps Script time limit.');
        break;
      }

      var cs = classSubjects[i];
      var className = cs.classes ? cs.classes.class_name : cs.class_id;
      var subjectName = cs.subjects ? cs.subjects.subject_name : cs.subject_id;
      var label = className + ' / ' + subjectName;
      var profile = firstRelated_(cs.profiles) || {};
      var timezone = safeTimeZone_(profile.timezone || DEFAULT_TIMEZONE);
      var lastRunAt = readScheduleState_(cs.id);

      try {
        var schedule = evaluateAlertSchedule_(cs, now, lastRunAt, timezone);
        if (!force && !schedule.due) {
          result.skipped++;
          continue;
        }

        result.due++;
        var classResult = processClassSubject_(cs, config, {
          now: now,
          dryRun: dryRun,
          deadline: deadline,
          availabilityCache: availabilityCache
        });

        result.sent += classResult.sent;
        result.failed += classResult.failed;
        result.skipped += classResult.skipped;
        result.missingEmail += classResult.missingEmail;
        result.wouldSend += classResult.wouldSend;
        for (var w = 0; w < classResult.wouldSendDetails.length; w++) {
          result.wouldSendDetails.push(classResult.wouldSendDetails[w]);
        }

        for (var e = 0; e < classResult.errors.length; e++) {
          result.errors.push(label + ': ' + classResult.errors[e]);
        }

        if (!dryRun && !classResult.timeBudgetExceeded && !classResult.infrastructureFailure) {
          writeScheduleState_(cs.id, now);
        }
      } catch (error) {
        var message = errorText_(error);
        result.errors.push(label + ': ' + message);
        Logger.log('Low-attendance processing failed for ' + label + ': ' + message);
      }
    }
  } finally {
    if (lock) lock.releaseLock();
  }

  Logger.log(
    'Low-attendance check complete: ' + result.sent + ' sent, ' +
    result.failed + ' failed, ' + result.skipped + ' skipped, ' +
    result.wouldSend + ' would send (dry run).'
  );
  return result;
}

function processClassSubject_(cs, config, context) {
  var className = cs.classes ? cs.classes.class_name : 'Class';
  var subjectName = cs.subjects ? cs.subjects.subject_name : 'Subject';
  var teacher = firstRelated_(cs.profiles) || {};
  var timezone = safeTimeZone_(teacher.timezone || DEFAULT_TIMEZONE);
  var threshold = clampNumber_(cs.threshold_percent, DEFAULT_THRESHOLD, 0, 100);
  var reminderDays = Math.max(0, toInteger_(cs.reminder_days, DEFAULT_REMINDER_DAYS));
  var classSubjectId = cs.id;
  var result = {
    sent: 0,
    failed: 0,
    skipped: 0,
    missingEmail: 0,
    wouldSend: 0,
    wouldSendDetails: [],
    infrastructureFailure: false,
    errors: []
  };

  var sessions = fetchCompletedSessions_(config, classSubjectId);
  if (!sessions.length) return result;

  var enrollments = fetchEnrollments_(config, classSubjectId);
  if (!enrollments.length) return result;

  var records = fetchAttendanceRecords_(config, sessions.map(function (session) {
    return session.id;
  }));

  var alertRows = fetchAlertHistory_(config, classSubjectId);
  var availability = fetchTeacherAvailability_(config, cs.teacher_id, context.availabilityCache);

  var recordMap = {};
  for (var r = 0; r < records.length; r++) {
    recordMap[records[r].session_id + '|' + records[r].student_id] = records[r].status;
  }

  var alertsByStudent = {};
  for (var a = 0; a < alertRows.length; a++) {
    var alert = alertRows[a];
    if (!alertsByStudent[alert.student_id]) alertsByStudent[alert.student_id] = [];
    alertsByStudent[alert.student_id].push(alert);
  }

  for (var i = 0; i < enrollments.length; i++) {
    if (Date.now() > context.deadline) {
      result.timeBudgetExceeded = true;
      result.errors.push('Stopped before all students were processed to stay within the Apps Script time limit.');
      break;
    }

    var enrollment = enrollments[i];
    var student = firstRelated_(enrollment.students);
    if (!student) continue;

    var studentEmail = String(student.email || '').trim();
    if (!isValidEmail_(studentEmail)) {
      result.missingEmail++;
      result.skipped++;
      continue;
    }

    var eligibleSessions = eligibleSessionsFor_(sessions, enrollment.enrolled_from);
    if (!eligibleSessions.length) continue;

    var attendance = calculateAttendance_(
      eligibleSessions,
      recordMap,
      student.id
    );
    if (attendance.conducted === 0) continue;

    if (!(attendance.percentage < threshold)) {
      result.skipped++;
      continue;
    }

    var studentAlerts = alertsByStudent[student.id] || [];
    var latestBlocking = latestBlockingAlert_(studentAlerts);
    var recovered = latestBlocking
      ? hasRecoveredSinceLastAlert_(
          latestBlocking,
          eligibleSessions,
          recordMap,
          student.id,
          threshold,
          timezone
        )
      : false;

    var alertType = 'initial';
    if (latestBlocking && !recovered) {
      var sentAt = new Date(latestBlocking.sent_at);
      var daysSince = (context.now.getTime() - sentAt.getTime()) / (1000 * 60 * 60 * 24);
      if (!isFinite(daysSince) || daysSince < reminderDays) {
        result.skipped++;
        continue;
      }
      alertType = 'reminder';
    }

    if (context.dryRun) {
      result.wouldSend++;
      result.wouldSendDetails.push({
        classSubjectId: classSubjectId,
        studentName: student.student_name,
        prn: student.prn,
        email: studentEmail,
        percentage: roundTo_(attendance.percentage, 2),
        alertType: alertType
      });
      continue;
    }

    var pending;
    try {
      pending = insertPendingAlert_(config, {
        classSubjectId: classSubjectId,
        studentId: student.id,
        attendancePercent: attendance.percentage,
        attendedCount: attendance.attended,
        conductedCount: attendance.conducted,
        alertType: alertType
      });
    } catch (pendingError) {
      result.failed++;
      result.infrastructureFailure = true;
      result.errors.push(
        'Could not create alert history for ' + student.student_name + ': ' +
        errorText_(pendingError)
      );
      continue;
    }

    var email = buildLowAttendanceEmail_({
      studentName: student.student_name,
      prn: student.prn,
      className: className,
      subjectName: subjectName,
      percentage: attendance.percentage,
      attendedCount: attendance.attended,
      conductedCount: attendance.conducted,
      threshold: threshold,
      formUrl: cs.google_form_url,
      teacherName: teacher.full_name || 'Faculty',
      teacherEmail: teacher.email || '',
      teacherDepartment: teacher.department || '',
      availability: availability
    });

    try {
      sendLowAttendanceEmail_(studentEmail, email, teacher.email);
      result.sent++;

      try {
        updateAlertStatus_(config, pending.id, 'sent', null);
      } catch (historyError) {
        result.infrastructureFailure = true;
        result.errors.push(
          'Email sent to ' + student.student_name + ' but the history row could not be marked sent: ' +
          errorText_(historyError)
        );
      }
    } catch (sendError) {
      result.failed++;
      var sendMessage = errorText_(sendError);
      result.errors.push('Email to ' + student.student_name + ' failed: ' + sendMessage);

      try {
        updateAlertStatus_(config, pending.id, 'failed', sendMessage);
      } catch (historyError) {
        result.infrastructureFailure = true;
        result.errors.push(
          'Could not record failed delivery for ' + student.student_name + ': ' +
          errorText_(historyError)
        );
      }
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Schedule evaluation
// ---------------------------------------------------------------------------

/**
 * Returns {due, reason, frequency, ...}. The schedule gate is class-level;
 * reminder_days remains the per-student anti-spam gate.
 */
function evaluateAlertSchedule_(cs, now, lastRunAt, timezone) {
  var tz = safeTimeZone_(timezone);
  var local = getZonedParts_(now, tz);
  var alertTime = parseAlertTime_(cs.alert_time);
  var nowMinutes = local.hour * 60 + local.minute;
  var alertMinutes = alertTime.hour * 60 + alertTime.minute;
  var frequency = normalizeFrequency_(cs.alert_frequency);
  var lastLocalDate = lastRunAt ? getZonedParts_(lastRunAt, tz).date : null;
  var result = {
    due: false,
    reason: '',
    frequency: frequency,
    localDate: local.date,
    localTime: local.time,
    dayOfWeek: local.dayOfWeek,
    timezone: tz
  };

  if (nowMinutes < alertMinutes) {
    result.reason = 'waiting for ' + formatTime12h_(cs.alert_time || DEFAULT_ALERT_TIME);
    return result;
  }

  if (frequency === 'daily') {
    result.due = lastLocalDate !== local.date;
    result.reason = result.due ? 'daily schedule is due' : 'already checked today';
    return result;
  }

  if (frequency === 'biweekly') {
    var intervalDays = Math.max(14, toInteger_(cs.interval_days, 14));
    if (!lastRunAt) {
      result.due = true;
      result.reason = 'biweekly schedule has no previous run';
    } else if (lastLocalDate === local.date) {
      result.reason = 'already checked today';
    } else {
      var elapsedDays = daysBetweenDateKeys_(lastLocalDate, local.date);
      result.due = elapsedDays >= intervalDays;
      result.reason = result.due
        ? 'biweekly interval reached (' + elapsedDays + '/' + intervalDays + ' days)'
        : 'waiting for biweekly interval (' + elapsedDays + '/' + intervalDays + ' days)';
    }
    return result;
  }

  var weeklyDay = toInteger_(cs.weekly_day, 1);
  if (weeklyDay < 1 || weeklyDay > 7) weeklyDay = 1;

  if (local.dayOfWeek !== weeklyDay) {
    result.reason = 'waiting for ' + DAY_NAMES[weeklyDay];
    return result;
  }

  result.due = lastLocalDate !== local.date;
  result.reason = result.due ? 'weekly schedule is due' : 'already checked today';
  return result;
}

function getZonedParts_(date, timezone) {
  var tz = safeTimeZone_(timezone);
  var dateKey = Utilities.formatDate(date, tz, 'yyyy-MM-dd');
  var time = Utilities.formatDate(date, tz, 'HH:mm');
  var parts = time.split(':');

  return {
    date: dateKey,
    time: time,
    hour: parseInt(parts[0], 10) || 0,
    minute: parseInt(parts[1], 10) || 0,
    dayOfWeek: dayOfWeekFromDateKey_(dateKey),
    timezone: tz
  };
}

function dayOfWeekFromDateKey_(dateKey) {
  var parts = String(dateKey || '').split('-');
  if (parts.length !== 3) return 1;
  var day = new Date(Date.UTC(
    parseInt(parts[0], 10) || 1970,
    (parseInt(parts[1], 10) || 1) - 1,
    parseInt(parts[2], 10) || 1
  )).getUTCDay();
  return day === 0 ? 7 : day;
}

function parseAlertTime_(value) {
  var match = String(value || DEFAULT_ALERT_TIME).match(/^(\d{1,2}):(\d{2})/);
  if (!match) return { hour: 9, minute: 0 };
  var hour = parseInt(match[1], 10);
  var minute = parseInt(match[2], 10);
  if (!isFinite(hour) || hour < 0 || hour > 23) hour = 9;
  if (!isFinite(minute) || minute < 0 || minute > 59) minute = 0;
  return { hour: hour, minute: minute };
}

function normalizeFrequency_(value) {
  var normalized = String(value || 'weekly').toLowerCase().replace(/[^a-z]/g, '');
  if (normalized === 'daily') return 'daily';
  if (normalized === 'biweekly') return 'biweekly';
  return 'weekly';
}

function daysBetweenDateKeys_(fromDate, toDate) {
  var from = dateKeyToUtcMs_(fromDate);
  var to = dateKeyToUtcMs_(toDate);
  return Math.floor((to - from) / (1000 * 60 * 60 * 24));
}

function dateKeyToUtcMs_(dateKey) {
  var parts = String(dateKey || '').split('-');
  if (parts.length !== 3) return NaN;
  return Date.UTC(
    parseInt(parts[0], 10) || 0,
    (parseInt(parts[1], 10) || 1) - 1,
    parseInt(parts[2], 10) || 1
  );
}

function readScheduleState_(classSubjectId) {
  try {
    var raw = PropertiesService.getScriptProperties().getProperty(
      SCHEDULE_PROPERTY_PREFIX + classSubjectId
    );
    if (!raw) return null;
    var parsed = JSON.parse(raw);
    if (!parsed.lastRunAt) return null;
    var date = new Date(parsed.lastRunAt);
    return isNaN(date.getTime()) ? null : date;
  } catch (error) {
    Logger.log('Could not read schedule state: ' + errorText_(error));
    return null;
  }
}

function writeScheduleState_(classSubjectId, date) {
  try {
    PropertiesService.getScriptProperties().setProperty(
      SCHEDULE_PROPERTY_PREFIX + classSubjectId,
      JSON.stringify({ lastRunAt: date.toISOString(), version: 1 })
    );
  } catch (error) {
    Logger.log('Could not save schedule state: ' + errorText_(error));
  }
}

// ---------------------------------------------------------------------------
// Attendance calculation
// ---------------------------------------------------------------------------

function eligibleSessionsFor_(sessions, enrolledFrom) {
  var start = dateKey_(enrolledFrom);
  return sessions.filter(function (session) {
    return dateKey_(session.lecture_date) >= start;
  });
}

function dateKey_(value) {
  if (!value) return '';
  var match = String(value).match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : '';
}

function calculateAttendance_(sessions, recordMap, studentId) {
  var attended = 0;
  var conducted = 0;

  for (var i = 0; i < sessions.length; i++) {
    conducted++;
    if (recordMap[sessions[i].id + '|' + studentId] === 'present') {
      attended++;
    }
  }

  return {
    attended: attended,
    conducted: conducted,
    percentage: conducted === 0 ? 0 : (attended / conducted) * 100
  };
}

function latestBlockingAlert_(alerts) {
  for (var i = 0; i < alerts.length; i++) {
    var status = String(alerts[i].status || '').toLowerCase();
    if (status === 'sent' || status === 'pending') return alerts[i];
  }
  return null;
}

/**
 * A student can recover and fall below the threshold again. If the attendance
 * percentage reached the threshold at any lecture after the last alert, the
 * next email is a new "initial" alert instead of being suppressed as spam.
 */
function hasRecoveredSinceLastAlert_(
  lastAlert,
  eligibleSessions,
  recordMap,
  studentId,
  threshold,
  timezone
) {
  if (!lastAlert || !lastAlert.sent_at) return false;

  var alertDate = getZonedParts_(new Date(lastAlert.sent_at), timezone).date;
  var attended = 0;
  var conducted = 0;

  for (var i = 0; i < eligibleSessions.length; i++) {
    var session = eligibleSessions[i];
    conducted++;
    if (recordMap[session.id + '|' + studentId] === 'present') {
      attended++;
    }

    if (dateKey_(session.lecture_date) > alertDate && conducted > 0) {
      if ((attended / conducted) * 100 >= threshold) return true;
    }
  }

  return false;
}

// ---------------------------------------------------------------------------
// Supabase requests
// ---------------------------------------------------------------------------

function getSupabaseConfig_() {
  var url = getConfig_('SUPABASE_URL', '').replace(/\/+$/, '');
  var key = getConfig_('SUPABASE_SERVICE_ROLE_KEY', '');

  if (!url || url.indexOf('YOUR_SUPABASE') >= 0) {
    throw new Error('Set the SUPABASE_URL script property first.');
  }
  if (!key || key.indexOf('YOUR_SUPABASE') >= 0) {
    throw new Error('Set the SUPABASE_SERVICE_ROLE_KEY script property first.');
  }

  return { url: url, key: key };
}

function fetchClassSubjects_(config) {
  var query =
    'alert_enabled=eq.true&active=eq.true&order=created_at.asc&select=' +
    encodeURIComponent('*,classes(class_name),subjects(subject_name),profiles(full_name,email,department,phone,timezone)');
  return asArray_(supabaseRequest_(config, 'GET', 'class_subjects', query));
}

function fetchCompletedSessions_(config, classSubjectId) {
  var query =
    'class_subject_id=eq.' + encodeURIComponent(classSubjectId) +
    '&status=eq.completed&order=lecture_date.asc,period_number.asc' +
    '&select=' + encodeURIComponent('id,lecture_date,period_number');
  return asArray_(supabaseRequest_(config, 'GET', 'attendance_sessions', query));
}

function fetchEnrollments_(config, classSubjectId) {
  var query =
    'class_subject_id=eq.' + encodeURIComponent(classSubjectId) +
    '&active=eq.true&select=' +
    encodeURIComponent('id,student_id,enrolled_from,students(id,prn,student_name,email)');
  return asArray_(supabaseRequest_(config, 'GET', 'enrollments', query));
}

function fetchAttendanceRecords_(config, sessionIds) {
  if (!sessionIds.length) return [];

  var result = [];
  var chunkSize = 100;

  for (var i = 0; i < sessionIds.length; i += chunkSize) {
    var chunk = sessionIds.slice(i, i + chunkSize);
    var query =
      'session_id=in.(' + chunk.join(',') + ')&select=' +
      encodeURIComponent('session_id,student_id,status');
    var rows = asArray_(supabaseRequest_(config, 'GET', 'attendance_records', query));
    result = result.concat(rows);
  }

  return result;
}

function fetchAlertHistory_(config, classSubjectId) {
  var query =
    'class_subject_id=eq.' + encodeURIComponent(classSubjectId) +
    '&order=sent_at.desc&limit=1000&select=' +
    encodeURIComponent('id,student_id,alert_type,status,sent_at,attendance_percent');
  return asArray_(supabaseRequest_(config, 'GET', 'attendance_alerts', query));
}

function fetchTeacherAvailability_(config, teacherId, cache) {
  if (cache[teacherId]) return cache[teacherId];

  var query =
    'teacher_id=eq.' + encodeURIComponent(teacherId) +
    '&active=eq.true&order=day_of_week.asc,start_time.asc&select=' +
    encodeURIComponent('day_of_week,start_time,end_time');

  var rows = asArray_(supabaseRequest_(config, 'GET', 'teacher_availability', query));
  var slots = rows.map(function (slot) {
    var day = DAY_NAMES[toInteger_(slot.day_of_week, 1)] || 'Day';
    return day + ': ' + formatTime12h_(slot.start_time) + ' - ' + formatTime12h_(slot.end_time);
  });

  cache[teacherId] = slots;
  return slots;
}

function insertPendingAlert_(config, data) {
  var payload = {
    class_subject_id: data.classSubjectId,
    student_id: data.studentId,
    attendance_percent: roundTo_(data.attendancePercent, 2),
    attended_count: data.attendedCount,
    conducted_count: data.conductedCount,
    alert_type: data.alertType,
    status: 'pending',
    error_message: null
  };

  var response = supabaseRequest_(config, 'POST', 'attendance_alerts', '', payload, {
    'Prefer': 'return=representation'
  });
  var rows = asArray_(response);
  if (!rows.length || !rows[0].id) {
    throw new Error('Supabase did not return the created alert row.');
  }
  return rows[0];
}

function updateAlertStatus_(config, alertId, status, errorMessage) {
  var payload = {
    status: status,
    error_message: errorMessage ? truncate_(errorMessage, 500) : null
  };
  supabaseRequest_(
    config,
    'PATCH',
    'attendance_alerts',
    'id=eq.' + encodeURIComponent(alertId),
    payload,
    { 'Prefer': 'return=minimal' }
  );
}

function supabaseRequest_(config, method, table, query, payload, extraHeaders) {
  var url = config.url + '/rest/v1/' + table + (query ? '?' + query : '');
  var headers = {
    'apikey': config.key,
    'Authorization': 'Bearer ' + config.key,
    'Content-Type': 'application/json'
  };
  if (extraHeaders) {
    for (var key in extraHeaders) {
      if (Object.prototype.hasOwnProperty.call(extraHeaders, key)) {
        headers[key] = extraHeaders[key];
      }
    }
  }

  var options = {
    method: method,
    headers: headers,
    muteHttpExceptions: true
  };
  if (payload !== undefined && payload !== null) {
    options.payload = JSON.stringify(payload);
  }

  var response = UrlFetchApp.fetch(url, options);
  var code = response.getResponseCode ? response.getResponseCode() : 200;
  var text = response.getContentText ? response.getContentText() : '';

  if (code < 200 || code >= 300) {
    throw new Error(
      'Supabase ' + method + ' ' + table + ' failed (' + code + '): ' +
      truncate_(text, 500)
    );
  }

  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (parseError) {
    throw new Error('Supabase returned invalid JSON for ' + table + ': ' + truncate_(text, 200));
  }
}

// ---------------------------------------------------------------------------
// Email
// ---------------------------------------------------------------------------

function sendLowAttendanceEmail_(to, email, teacherEmail) {
  var options = {
    to: to,
    subject: email.subject,
    body: email.body,
    htmlBody: email.htmlBody,
    name: EMAIL_SENDER_NAME
  };

  if (isValidEmail_(teacherEmail)) {
    options.replyTo = teacherEmail;
  }

  MailApp.sendEmail(options);
}

function buildLowAttendanceEmail_(data) {
  var percentage = formatNumber_(data.percentage, 2) + '%';
  var threshold = formatNumber_(data.threshold, 2) + '%';
  var formUrl = normalizeHttpUrl_(data.formUrl);
  var availability = data.availability && data.availability.length
    ? data.availability
    : ['Not specified'];
  var teacherName = data.teacherName || 'Faculty';
  var teacherEmail = data.teacherEmail || '';
  var teacherDepartment = data.teacherDepartment || '';
  var subject = 'Low attendance alert: ' + data.subjectName + ' (' + data.className + ') - ' + percentage;

  var bodyLines = [
    'Dear ' + data.studentName + ' (PRN: ' + data.prn + '),',
    '',
    'Your cumulative attendance for ' + data.subjectName + ' (' + data.className + ') is currently ' +
      percentage + ', which is below the required ' + threshold + ' threshold.',
    '',
    'Attendance summary:',
    '- Attended lectures: ' + data.attendedCount,
    '- Total eligible lectures: ' + data.conductedCount,
    '- Current attendance: ' + percentage,
    '',
    formUrl
      ? 'Please complete the attendance form here:\n' + formUrl
      : 'No attendance form link has been configured. Please contact your faculty.',
    '',
    'Faculty contact:',
    '- Name: ' + teacherName,
    teacherEmail ? '- Email: ' + teacherEmail : null,
    teacherDepartment ? '- Department: ' + teacherDepartment : null,
    '',
    'Available meeting slots:',
    availability.join('\n'),
    '',
    'This is an automated low-attendance notification. If you believe this is a mistake, contact your faculty.',
    '',
    'Regards,',
    'Department Attendance Cell'
  ].filter(function (line) {
    return line !== null;
  });

  var availabilityHtml = availability.map(function (line) {
    return '<li style="margin:0 0 4px 0;">' + escapeHtml_(line) + '</li>';
  }).join('');

  var formHtml = formUrl
    ? '<p style="margin:0 0 18px 0;">Please complete the attendance form to explain your absence and request a discussion with your faculty.</p>' +
      '<p style="margin:0 0 22px 0;">' +
      '<a href="' + escapeHtml_(formUrl) + '" style="display:inline-block;background:#4F46E5;color:#ffffff;text-decoration:none;padding:12px 20px;border-radius:8px;font-weight:bold;">Open Attendance Form</a>' +
      '</p>'
    : '<p style="margin:0 0 18px 0;">No attendance form link has been configured for this class. Please contact your faculty directly.</p>';

  var teacherHtml = [
    '<strong>' + escapeHtml_(teacherName) + '</strong>',
    teacherEmail ? '<br><a href="mailto:' + escapeHtml_(teacherEmail) + '" style="color:#4F46E5;">' + escapeHtml_(teacherEmail) + '</a>' : '',
    teacherDepartment ? '<br>' + escapeHtml_(teacherDepartment) : ''
  ].join('');

  var htmlBody = [
    '<!DOCTYPE html>',
    '<html><head><meta charset="utf-8"></head>',
    '<body style="margin:0;padding:0;background:#F3F4F6;font-family:Arial,Helvetica,sans-serif;color:#111827;">',
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F3F4F6;padding:24px 12px;">',
    '<tr><td align="center">',
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:620px;background:#ffffff;border-radius:14px;overflow:hidden;">',
    '<tr><td style="background:#4F46E5;padding:24px 28px;color:#ffffff;">',
    '<div style="font-size:13px;letter-spacing:1px;text-transform:uppercase;opacity:0.85;">Smart Attendance</div>',
    '<h1 style="margin:8px 0 0 0;font-size:23px;line-height:1.3;">Low attendance alert</h1>',
    '</td></tr>',
    '<tr><td style="padding:28px;">',
    '<p style="margin:0 0 16px 0;font-size:16px;">Dear <strong>' + escapeHtml_(data.studentName) + '</strong> (PRN: ' + escapeHtml_(data.prn) + '),</p>',
    '<p style="margin:0 0 18px 0;line-height:1.6;">Your cumulative attendance for <strong>' +
      escapeHtml_(data.subjectName) + '</strong> (' + escapeHtml_(data.className) +
      ') is below the required attendance threshold.</p>',
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 22px 0;background:#F9FAFB;border:1px solid #E5E7EB;border-radius:10px;">',
    '<tr><td style="padding:16px 18px;">',
    '<div style="font-size:32px;font-weight:bold;color:#DC2626;">' + percentage + '</div>',
    '<div style="margin-top:4px;color:#6B7280;font-size:13px;">Required: ' + threshold + '</div>',
    '<div style="margin-top:10px;font-size:14px;">Attended <strong>' + data.attendedCount + '</strong> of <strong>' +
      data.conductedCount + '</strong> eligible lectures</div>',
    '</td></tr></table>',
    formHtml,
    '<h2 style="margin:0 0 8px 0;font-size:16px;">Faculty contact</h2>',
    '<p style="margin:0 0 20px 0;line-height:1.6;">' + teacherHtml + '</p>',
    '<h2 style="margin:0 0 8px 0;font-size:16px;">Available meeting slots</h2>',
    '<ul style="margin:0 0 22px 0;padding-left:20px;line-height:1.7;">' + availabilityHtml + '</ul>',
    '<p style="margin:0;color:#6B7280;font-size:12px;line-height:1.6;">This is an automated low-attendance notification. If you believe this is a mistake, contact your faculty.</p>',
    '</td></tr>',
    '<tr><td style="background:#F9FAFB;border-top:1px solid #E5E7EB;padding:16px 28px;color:#6B7280;font-size:12px;">Department Attendance Cell</td></tr>',
    '</table>',
    '</td></tr>',
    '</table>',
    '</body></html>'
  ].join('');

  return {
    subject: subject,
    body: bodyLines.join('\n'),
    htmlBody: htmlBody
  };
}

// ---------------------------------------------------------------------------
// Small utilities
// ---------------------------------------------------------------------------

function getConfig_(key, fallback) {
  try {
    var value = PropertiesService.getScriptProperties().getProperty(key);
    if (value === null || value === undefined) return fallback;
    value = String(value).trim();
    return value || fallback;
  } catch (error) {
    return fallback;
  }
}

function getScriptTimeZone_() {
  try {
    return Session.getScriptTimeZone() || 'UTC';
  } catch (error) {
    return 'UTC';
  }
}

function safeTimeZone_(timezone) {
  var candidate = String(timezone || DEFAULT_TIMEZONE).trim();
  if (!candidate) candidate = DEFAULT_TIMEZONE;
  try {
    Utilities.formatDate(new Date(), candidate, 'yyyy-MM-dd');
    return candidate;
  } catch (error) {
    Logger.log('Invalid timezone "' + candidate + '"; falling back to ' + getScriptTimeZone_());
    return getScriptTimeZone_();
  }
}

function firstRelated_(value) {
  if (Array.isArray(value)) return value.length ? value[0] : null;
  return value || null;
}

function asArray_(value) {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}

function clampNumber_(value, fallback, min, max) {
  if (value === null || value === undefined || String(value).trim() === '') {
    return fallback;
  }
  var number = Number(value);
  if (!isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, number));
}

function toInteger_(value, fallback) {
  var number = parseInt(value, 10);
  return isFinite(number) ? number : fallback;
}

function roundTo_(value, digits) {
  var factor = Math.pow(10, digits);
  return Math.round(Number(value) * factor) / factor;
}

function formatNumber_(value, digits) {
  var number = Number(value);
  if (!isFinite(number)) number = 0;
  var text = number.toFixed(digits);
  return text.replace(/\.0+$/, '').replace(/(\.\d*[1-9])0+$/, '$1');
}

function formatTime12h_(value) {
  var parsed = parseAlertTime_(value);
  var hour = parsed.hour;
  var minute = parsed.minute;
  var suffix = hour >= 12 ? 'PM' : 'AM';
  var displayHour = hour % 12;
  if (displayHour === 0) displayHour = 12;
  return displayHour + ':' + String(minute).padStart(2, '0') + ' ' + suffix;
}

function normalizeHttpUrl_(value) {
  var url = String(value || '').trim();
  if (!/^https?:\/\/[^\s]+$/i.test(url)) return '';
  return url;
}

function isValidEmail_(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || '').trim());
}

function escapeHtml_(value) {
  return String(value === null || value === undefined ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function errorText_(error) {
  var message = error && error.message ? error.message : String(error);
  return truncate_(message.replace(/\s+/g, ' ').trim(), 500);
}

function truncate_(value, length) {
  var text = String(value || '');
  return text.length <= length ? text : text.substring(0, length - 1) + '…';
}
