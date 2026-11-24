const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const CODE_PATH = path.join(
  __dirname,
  '..',
  '..',
  'automation',
  'google_apps_script',
  'Code.gs',
);
const SOURCE = fs.readFileSync(CODE_PATH, 'utf8');

const EXPORTS = `
globalThis.__automation = {
  checkAndSendLowAttendanceAlerts: checkAndSendLowAttendanceAlerts,
  runLowAttendanceCheckNow: runLowAttendanceCheckNow,
  previewLowAttendanceAlerts: previewLowAttendanceAlerts,
  installLowAttendanceTrigger: installLowAttendanceTrigger,
  sendTestLowAttendanceEmail: sendTestLowAttendanceEmail,
  buildLowAttendanceEmail_: buildLowAttendanceEmail_,
  evaluateAlertSchedule_: evaluateAlertSchedule_,
  calculateAttendance_: calculateAttendance_,
  hasRecoveredSinceLastAlert_: hasRecoveredSinceLastAlert_,
  formatNumber_: formatNumber_,
  formatTime12h_: formatTime12h_,
  isValidEmail_: isValidEmail_
};
`;

function createFakeSupabase(initialData) {
  const state = {
    classSubjects: clone(initialData.classSubjects || []),
    sessions: clone(initialData.sessions || []),
    enrollments: clone(initialData.enrollments || []),
    records: clone(initialData.records || []),
    alerts: clone(initialData.alerts || []),
    availability: clone(initialData.availability || []),
  };
  const requests = [];
  let alertSequence = state.alerts.length;

  function fetch(url, options) {
    const method = String((options && options.method) || 'GET').toUpperCase();
    const parsed = new URL(url);
    const table = parsed.pathname.replace(/^\/rest\/v1\//, '');
    const params = parsed.searchParams;
    requests.push({ method, url, table, params, options });

    if (method === 'GET') {
      if (table === 'class_subjects') {
        let rows = state.classSubjects.filter(
          (cs) => cs.alert_enabled !== false && cs.active !== false,
        );
        rows = rows.sort((a, b) =>
          String(a.created_at).localeCompare(String(b.created_at)),
        );
        return response(200, rows);
      }

      if (table === 'attendance_sessions') {
        const classSubjectId = eqValue(params.get('class_subject_id'));
        const status = eqValue(params.get('status'));
        const rows = state.sessions
          .filter(
            (s) =>
              s.class_subject_id === classSubjectId &&
              (!status || s.status === status),
          )
          .sort((a, b) => {
            const byDate = String(a.lecture_date).localeCompare(
              String(b.lecture_date),
            );
            return byDate !== 0
              ? byDate
              : Number(a.period_number) - Number(b.period_number);
          });
        return response(200, rows);
      }

      if (table === 'enrollments') {
        const classSubjectId = eqValue(params.get('class_subject_id'));
        const rows = state.enrollments.filter(
          (e) =>
            e.class_subject_id === classSubjectId && e.active !== false,
        );
        return response(200, rows);
      }

      if (table === 'attendance_records') {
        const ids = inValue(params.get('session_id'));
        const rows = state.records.filter((r) => ids.includes(r.session_id));
        return response(200, rows);
      }

      if (table === 'attendance_alerts') {
        let rows = state.alerts.slice();
        const classSubjectId = eqValue(params.get('class_subject_id'));
        const studentId = eqValue(params.get('student_id'));
        if (classSubjectId) {
          rows = rows.filter((a) => a.class_subject_id === classSubjectId);
        }
        if (studentId) {
          rows = rows.filter((a) => a.student_id === studentId);
        }
        rows.sort((a, b) => String(b.sent_at).localeCompare(String(a.sent_at)));
        const limit = Number(params.get('limit'));
        if (Number.isFinite(limit) && limit > 0) rows = rows.slice(0, limit);
        return response(200, rows);
      }

      if (table === 'teacher_availability') {
        const teacherId = eqValue(params.get('teacher_id'));
        const rows = state.availability
          .filter(
            (slot) => slot.teacher_id === teacherId && slot.active !== false,
          )
          .sort((a, b) => {
            const byDay = Number(a.day_of_week) - Number(b.day_of_week);
            return byDay !== 0
              ? byDay
              : String(a.start_time).localeCompare(String(b.start_time));
          });
        return response(200, rows);
      }

      return response(404, { message: `Unknown table ${table}` });
    }

    if (method === 'POST' && table === 'attendance_alerts') {
      const payload = JSON.parse(options.payload);
      const row = {
        id: `alert-${++alertSequence}`,
        sent_at: new Date(state.now || Date.now()).toISOString(),
        ...payload,
      };
      state.alerts.push(row);
      return response(201, [row]);
    }

    if (method === 'PATCH' && table === 'attendance_alerts') {
      const id = eqValue(params.get('id'));
      const payload = JSON.parse(options.payload);
      const row = state.alerts.find((a) => a.id === id);
      if (!row) return response(404, { message: `Alert ${id} not found` });
      Object.assign(row, payload);
      return response(204, null);
    }

    return response(405, { message: `Unsupported ${method} ${table}` });
  }

  return { fetch, state, requests };
}

function createHarness(options) {
  const opts = options || {};
  const fixedNow = new Date(opts.now || '2026-11-18T04:30:00Z').getTime();
  const clock = { now: fixedNow };

  class FixedDate extends Date {
    constructor(...args) {
      if (args.length === 0) {
        super(clock.now);
      } else {
        super(...args);
      }
    }

    static now() {
      return clock.now;
    }
  }

  const properties = new Map();
  properties.set('SUPABASE_URL', opts.supabaseUrl || 'https://test.supabase.co');
  properties.set(
    'SUPABASE_SERVICE_ROLE_KEY',
    opts.serviceRoleKey || 'test-service-role-key',
  );
  properties.set('TEST_EMAIL', opts.testEmail || 'govindsr051@gmail.com');
  const logs = [];
  const sentEmails = [];
  let mailError = null;
  let lockAvailable = true;
  const triggers = [];
  const fakeSupabase = createFakeSupabase(opts.data || {});
  fakeSupabase.state.now = clock.now;

  const sandbox = {
    Date: FixedDate,
    URL: URL,
    Utilities: {
      formatDate(date, timeZone, pattern) {
        const parts = new Intl.DateTimeFormat('en-US', {
          timeZone,
          year: 'numeric',
          month: '2-digit',
          day: '2-digit',
          hour: '2-digit',
          minute: '2-digit',
          hourCycle: 'h23',
          weekday: 'short',
        })
          .formatToParts(new Date(date.getTime()))
          .reduce((acc, part) => {
            if (part.type !== 'literal') acc[part.type] = part.value;
            return acc;
          }, {});

        if (pattern === 'yyyy-MM-dd') {
          return `${parts.year}-${parts.month}-${parts.day}`;
        }
        if (pattern === 'HH:mm') return `${parts.hour}:${parts.minute}`;
        if (pattern === 'EEE') return parts.weekday;
        throw new Error(`Unsupported formatDate pattern: ${pattern}`);
      },
    },
    Session: {
      getScriptTimeZone: () => 'Asia/Kolkata',
    },
    PropertiesService: {
      getScriptProperties: () => ({
        getProperty: (key) => (properties.has(key) ? properties.get(key) : null),
        setProperty: (key, value) => properties.set(key, String(value)),
      }),
    },
    LockService: {
      getScriptLock: () => ({
        tryLock: () => lockAvailable,
        releaseLock: () => {},
      }),
    },
    ScriptApp: {
      getProjectTriggers: () => triggers.slice(),
      deleteTrigger: (trigger) => {
        const index = triggers.indexOf(trigger);
        if (index >= 0) triggers.splice(index, 1);
      },
      newTrigger: (handler) => {
        const builder = {
          timeBased() {
            return builder;
          },
          everyMinutes(minutes) {
            builder.minutes = minutes;
            return builder;
          },
          create() {
            const trigger = {
              getHandlerFunction: () => handler,
              getUniqueId: () => `trigger-${triggers.length + 1}`,
              minutes: builder.minutes,
            };
            triggers.push(trigger);
            return trigger;
          },
        };
        return builder;
      },
    },
    MailApp: {
      sendEmail: (email) => {
        if (mailError) throw new Error(mailError);
        sentEmails.push(email);
      },
    },
    UrlFetchApp: {
      fetch: fakeSupabase.fetch,
    },
    Logger: {
      log: (message) => logs.push(String(message)),
    },
  };

  const context = vm.createContext(sandbox);
  vm.runInContext(`${SOURCE}\n${EXPORTS}`, context, { filename: CODE_PATH });

  return {
    automation: sandbox.__automation,
    data: fakeSupabase.state,
    requests: fakeSupabase.requests,
    properties,
    logs,
    sentEmails,
    triggers,
    setNow(iso) {
      clock.now = new Date(iso).getTime();
      fakeSupabase.state.now = clock.now;
    },
    setMailError(message) {
      mailError = message;
    },
    setLockAvailable(value) {
      lockAvailable = value;
    },
  };
}

function response(code, payload) {
  const text = payload === null || payload === undefined
    ? ''
    : JSON.stringify(payload);
  return {
    getResponseCode: () => code,
    getContentText: () => text,
    getHeaders: () => ({}),
  };
}

function eqValue(value) {
  if (!value) return null;
  return String(value).startsWith('eq.') ? String(value).substring(3) : null;
}

function inValue(value) {
  const match = /^in\.\((.*)\)$/.exec(String(value || ''));
  return match && match[1] ? match[1].split(',') : [];
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function baseData(overrides) {
  const data = {
    classSubjects: [
      {
        id: 'cs1',
        teacher_id: 't1',
        class_id: 'c1',
        subject_id: 's1',
        google_form_url: 'https://forms.gle/class-form',
        threshold_percent: 75,
        alert_enabled: true,
        alert_frequency: 'daily',
        alert_time: '09:00:00',
        weekly_day: 1,
        interval_days: 7,
        reminder_days: 7,
        active: true,
        created_at: '2026-01-01T00:00:00Z',
        classes: { class_name: 'BE Computer A' },
        subjects: { subject_name: 'Ubiquitous Computing' },
        profiles: {
          full_name: 'Prof. Patil',
          email: 'patil@example.edu',
          department: 'Computer Engineering',
          phone: '',
          timezone: 'Asia/Kolkata',
        },
      },
    ],
    sessions: [
      {
        id: 'sess-1',
        class_subject_id: 'cs1',
        lecture_date: '2026-11-16',
        period_number: 1,
        status: 'completed',
      },
      {
        id: 'sess-2',
        class_subject_id: 'cs1',
        lecture_date: '2026-11-17',
        period_number: 1,
        status: 'completed',
      },
    ],
    enrollments: [
      {
        id: 'enr-1',
        class_subject_id: 'cs1',
        student_id: 'stu-1',
        enrolled_from: '2026-01-01',
        active: true,
        students: {
          id: 'stu-1',
          prn: '101',
          student_name: 'Aarav Sharma',
          email: 'govindsr051@gmail.com',
        },
      },
    ],
    records: [
      { session_id: 'sess-1', student_id: 'stu-1', status: 'present' },
      { session_id: 'sess-2', student_id: 'stu-1', status: 'absent' },
    ],
    alerts: [],
    availability: [
      {
        teacher_id: 't1',
        day_of_week: 1,
        start_time: '10:00:00',
        end_time: '11:00:00',
        active: true,
      },
    ],
  };

  return mergeDeep(data, overrides || {});
}

function mergeDeep(target, source) {
  for (const [key, value] of Object.entries(source)) {
    if (
      value &&
      typeof value === 'object' &&
      !Array.isArray(value) &&
      target[key] &&
      typeof target[key] === 'object' &&
      !Array.isArray(target[key])
    ) {
      mergeDeep(target[key], value);
    } else {
      target[key] = clone(value);
    }
  }
  return target;
}

module.exports = {
  createHarness,
  baseData,
};
