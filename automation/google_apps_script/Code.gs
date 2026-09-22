/**
 * Smart Attendance Ubiquitous System — Google Apps Script Email Automation
 * File: Code.gs
 * 
 * Instructions:
 * 1. Open Google Apps Script (script.google.com).
 * 2. Paste this code into Code.gs.
 * 3. Update SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY script properties.
 * 4. Create a Time-driven Trigger (e.g. Daily or Weekly) to run `checkAndSendLowAttendanceAlerts()`.
 */

const SUPABASE_URL = "https://YOUR_SUPABASE_PROJECT.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = "YOUR_SUPABASE_SERVICE_ROLE_KEY";

function checkAndSendLowAttendanceAlerts() {
  Logger.log("Starting Low Attendance Check...");

  // 1. Fetch active class-subjects with alerts enabled
  const classSubjectsUrl = `${SUPABASE_URL}/rest/v1/class_subjects?alert_enabled=eq.true&active=eq.true&select=*,classes(*),subjects(*),profiles(*)`;
  const options = {
    headers: {
      "apikey": SUPABASE_SERVICE_ROLE_KEY,
      "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json"
    }
  };

  const response = UrlFetchApp.fetch(classSubjectsUrl, options);
  const classSubjects = JSON.parse(response.getContentText());

  Logger.log(`Found ${classSubjects.length} active class-subjects with alerts enabled.`);

  for (const cs of classSubjects) {
    processClassSubjectAlerts(cs, options);
  }
}

function processClassSubjectAlerts(cs, options) {
  const classSubjectId = cs.id;
  const threshold = cs.threshold_percent || 75.0;
  const googleFormUrl = cs.google_form_url || "";
  const teacher = cs.profiles || {};
  const className = cs.classes ? cs.classes.class_name : "Class";
  const subjectName = cs.subjects ? cs.subjects.subject_name : "Subject";

  // Fetch completed sessions for this class_subject
  const sessionsUrl = `${SUPABASE_URL}/rest/v1/attendance_sessions?class_subject_id=eq.${classSubjectId}&status=eq.completed&select=id,lecture_date`;
  const sessionsRes = UrlFetchApp.fetch(sessionsUrl, options);
  const sessions = JSON.parse(sessionsRes.getContentText());

  if (sessions.length === 0) return; // No sessions conducted yet

  const sessionIds = sessions.map(s => s.id);

  // Fetch enrollments with student data
  const enrollmentsUrl = `${SUPABASE_URL}/rest/v1/enrollments?class_subject_id=eq.${classSubjectId}&active=eq.true&select=*,students(*)`;
  const enrollmentsRes = UrlFetchApp.fetch(enrollmentsUrl, options);
  const enrollments = JSON.parse(enrollmentsRes.getContentText());

  // Fetch records for these sessions
  const recordsUrl = `${SUPABASE_URL}/rest/v1/attendance_records?session_id=in.(${sessionIds.join(',')})&select=*`;
  const recordsRes = UrlFetchApp.fetch(recordsUrl, options);
  const records = JSON.parse(recordsRes.getContentText());

  // Build record map: "sessionId_studentId" -> status
  const recordMap = {};
  for (const r of records) {
    recordMap[`${r.session_id}_${r.student_id}`] = r.status;
  }

  // Fetch teacher availability slots
  const availabilityUrl = `${SUPABASE_URL}/rest/v1/teacher_availability?teacher_id=eq.${cs.teacher_id}&active=eq.true&select=*`;
  const availRes = UrlFetchApp.fetch(availabilityUrl, options);
  const availabilitySlots = JSON.parse(availRes.getContentText());

  // Format teacher availability for email
  let availabilityText = "Not specified";
  if (availabilitySlots.length > 0) {
    const days = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
    availabilityText = availabilitySlots.map(slot => 
      `${days[slot.day_of_week]}: ${slot.start_time} - ${slot.end_time}`
    ).join("\n");
  }

  // Check each student's attendance percentage
  for (const enrollment of enrollments) {
    const student = enrollment.students;
    if (!student || !student.email) continue;

    let attendedCount = 0;
    let eligibleCount = 0;

    for (const session of sessions) {
      const sessionDate = new Date(session.lecture_date);
      const enrolledDate = new Date(enrollment.enrolled_from);

      if (sessionDate < enrolledDate) continue; // Skip sessions prior to enrollment

      eligibleCount++;
      const status = recordMap[`${session.id}_${student.id}`];
      if (status === 'present') {
        attendedCount++;
      }
    }

    if (eligibleCount === 0) continue;

    const percentage = (attendedCount / eligibleCount) * 100.0;

    // Rule 12: attendance_percentage < threshold
    if (percentage < threshold) {
      // Rule 14: Check recent alert history to avoid spamming
      const alertHistoryUrl = `${SUPABASE_URL}/rest/v1/attendance_alerts?class_subject_id=eq.${classSubjectId}&student_id=eq.${student.id}&order=sent_at.desc&limit=1`;
      const historyRes = UrlFetchApp.fetch(alertHistoryUrl, options);
      const history = JSON.parse(historyRes.getContentText());

      let alertType = "initial";
      if (history.length > 0) {
        const lastSent = new Date(history[0].sent_at);
        const daysSinceLastAlert = (new Date() - lastSent) / (1000 * 60 * 60 * 24);
        
        // Respect configured reminder days interval (e.g. 7 days)
        if (daysSinceLastAlert < (cs.reminder_days || 7)) {
          Logger.log(`Skipping alert for ${student.student_name}: alert sent ${daysSinceLastAlert.toFixed(1)} days ago.`);
          continue;
        }
        alertType = "reminder";
      }

      // Compose and send email
      sendLowAttendanceEmail(
        student,
        className,
        subjectName,
        percentage.toFixed(2),
        attendedCount,
        eligibleCount,
        threshold,
        googleFormUrl,
        teacher.full_name || "Faculty",
        teacher.email || "",
        availabilityText
      );

      // Record alert in attendance_alerts log
      const logUrl = `${SUPABASE_URL}/rest/v1/attendance_alerts`;
      const logBody = {
        class_subject_id: classSubjectId,
        student_id: student.id,
        attendance_percent: percentage,
        attended_count: attendedCount,
        conducted_count: eligibleCount,
        alert_type: alertType,
        status: "sent"
      };

      UrlFetchApp.fetch(logUrl, {
        method: "post",
        headers: options.headers,
        payload: JSON.stringify(logBody)
      });

      Logger.log(`Low attendance email sent to ${student.student_name} (${percentage.toFixed(2)}%)`);
    }
  }
}

function sendLowAttendanceEmail(student, className, subjectName, percentage, attended, total, threshold, formUrl, teacherName, teacherEmail, availability) {
  const subject = `[Low Attendance Alert] ${subjectName} - ${className}`;
  const body = `Dear ${student.student_name} (PRN: ${student.prn}),

Your cumulative attendance for ${subjectName} (${className}) is currently ${percentage}%, which is below the required ${threshold}% threshold criterion.

Attendance Summary:
- Attended Lectures: ${attended}
- Total Conducted Lectures: ${total}
- Current Attendance: ${percentage}%

Please fill out the Attendance Form to report your reason and request a discussion with your faculty:
${formUrl || "Form link not provided"}

Faculty Contact Information:
- Faculty: ${teacherName}
- Email: ${teacherEmail}

Available Meeting Slots:
${availability}

Regards,
Department Attendance Cell`;

  MailApp.sendEmail(student.email, subject, body);
}
