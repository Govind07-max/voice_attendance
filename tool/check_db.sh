#!/usr/bin/env bash
# Check how much data is stored in your Supabase project.
#
# Usage:
#   ./tool/check_db.sh                 # whole project
#   ./tool/check_db.sh you@email.com   # only one teacher's data
#
# It uses the Supabase connection pooler, because the direct connection
# hostname is IPv6-only and many networks block IPv6.

set -uo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-txymxxcvzbqoqeknwyrz}"
REGION="${SUPABASE_REGION:-ap-northeast-1}"
DB_PASSWORD="${SUPABASE_DB_PASSWORD:-}"
EMAIL_FILTER="${1:-}"

if [ -z "$DB_PASSWORD" ]; then
  # Try the project .env / a local password file if present.
  for f in "$HOME/.supabase_db_password" "$HOME/.config/supabase/db_password"; do
    [ -f "$f" ] && DB_PASSWORD="$(cat "$f")" && break
  done
fi

if [ -z "$DB_PASSWORD" ]; then
  echo "Set the DB password first:"
  echo "  export SUPABASE_DB_PASSWORD='your-supabase-db-password'"
  echo "  (Supabase Dashboard > Settings > Database > DB password)"
  exit 1
fi

CONN="host=aws-0-${REGION}.pooler.supabase.com port=5432 user=postgres.${PROJECT_REF} dbname=postgres sslmode=require"

run() {
  PGPASSWORD="$DB_PASSWORD" psql "$CONN" -At -F' | ' -c "$1"
}

echo "=============================================================="
echo " SUPABASE PROJECT: $PROJECT_REF   (region: $REGION)"
echo "=============================================================="
echo
echo "--- DATABASE SIZE (free tier limit: 500 MB) ---"
run "
select '  total   : ' || pg_size_pretty(pg_database_size(current_database()))
    || '  (' || pg_database_size(current_database()) || ' bytes)';
select '  used    : ' || round(100.0 * pg_database_size(current_database()) / (500*1024*1024)::numeric, 3) || '% of the 500 MB limit';
select '  tables  : ' || (select count(*) from pg_stat_user_tables) || ' user tables';
select '  indexes : ' || (select count(*) from pg_stat_user_indexes) || ' indexes';
"
echo
echo "--- LARGEST TABLES ---"
run "
select '  ' || rpad(s.relname, 24) || ' | ' || pg_size_pretty(pg_total_relation_size(s.relid)) || ' | ' || s.n_live_tup || ' rows'
from pg_stat_user_tables s order by pg_total_relation_size(s.relid) desc limit 12;
"
echo
echo "--- ROW COUNTS ---"
run "
select '  profiles            | ' || (select count(*) from profiles);
select '  classes             | ' || (select count(*) from classes);
select '  subjects            | ' || (select count(*) from subjects);
select '  class_subjects      | ' || (select count(*) from class_subjects);
select '  students            | ' || (select count(*) from students);
select '  enrollments         | ' || (select count(*) from enrollments);
select '  attendance_sessions | ' || (select count(*) from attendance_sessions);
select '  attendance_records  | ' || (select count(*) from attendance_records);
select '  attendance_alerts   | ' || (select count(*) from attendance_alerts);
select '  teacher_availability| ' || (select count(*) from teacher_availability);
select '  auth users          | ' || (select count(*) from auth.users);
"
echo
echo "--- PER TEACHER ---"
run "
select '  ' || u.email
  || ' | classes=' || (select count(*) from classes c where c.teacher_id=u.id)
  || ' students=' || (select count(*) from students s where s.teacher_id=u.id)
  || ' lectures=' || (select count(*) from attendance_sessions a join class_subjects cs on cs.id=a.class_subject_id where cs.teacher_id=u.id)
  || ' records=' || (select count(*) from attendance_records r join students st on st.id=r.student_id where st.teacher_id=u.id)
from auth.users u order by u.created_at;
"

if [ -n "$EMAIL_FILTER" ]; then
  echo
  echo "--- DETAIL FOR $EMAIL_FILTER ---"
  run "
  select '  PROFILE: ' || full_name || ' | ' || coalesce(nullif(department,''),'-') || ' | faculty=' || coalesce(nullif(faculty_id,''),'-')
  from profiles where email='$EMAIL_FILTER';
  select '  CLASSES:';
  select '    ' || c.class_name || ' | ' || c.academic_year || ' | Sem ' || c.semester || ' | ' || s.subject_name || ' (' || s.subject_code || ')'
  from class_subjects cs join classes c on c.id=cs.class_id join subjects s on s.id=cs.subject_id
  join auth.users u on u.id=cs.teacher_id where u.email='$EMAIL_FILTER' order by c.class_name;
  select '  LECTURES:';
  select '    ' || a.lecture_date || ' | period ' || a.period_number || ' | ' || a.status || ' | records=' || (select count(*) from attendance_records r where r.session_id=a.id)
  from attendance_sessions a join class_subjects cs on cs.id=a.class_subject_id
  join auth.users u on u.id=cs.teacher_id where u.email='$EMAIL_FILTER' order by a.lecture_date;
  "
fi

echo
echo "--- FREE TIER QUICK FACTS ---"
run "
select '  Egress this month   : ' || coalesce((select pg_size_pretty(sum(pg_column_size(t.*))::bigint) from public.attendance_records t), '0') || ' of raw record bytes read (limit 5 GB/month)';
select '  Email quota        : ~60 students x 1 alert/month (limit 500 emails/day)';
"
echo
echo "Tip: the Supabase Dashboard > Database > Tables shows the same numbers in a GUI."
