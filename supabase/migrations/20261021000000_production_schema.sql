-- Smart Attendance Ubiquitous System — Production Schema (v2)
-- Target: Supabase (Postgres 15+), free tier
-- Apply via: Supabase Dashboard > SQL Editor > New query > Run
--
-- Changes vs v1 (20260923000000_initial_schema.sql):
--   * auto-updating updated_at on profiles / students
--   * UNIQUE (class_subject_id, lecture_date, period_number) on attendance_sessions
--     -> prevents accidental duplicate lectures on a double tap (Rule 11 still allows
--        multiple lectures per day via different period_number)
--   * UNIQUE (teacher_id, subject_code) on subjects
--   * UNIQUE (teacher_id, class_name, academic_year) on classes
--   * extra indexes for the reports/percentage queries
--   * explicit WITH CHECK on every RLS policy (defence in depth)

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------
-- 0. updated_at helper
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------------
-- 1. profiles (teacher)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
    id                UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name         TEXT NOT NULL,
    faculty_id        TEXT DEFAULT '',
    email             TEXT NOT NULL,
    department        TEXT DEFAULT '',
    phone             TEXT DEFAULT '',
    timezone          TEXT DEFAULT 'Asia/Kolkata',
    default_threshold NUMERIC DEFAULT 75.00,
    created_at        TIMESTAMPTZ DEFAULT NOW(),
    updated_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------
-- 2. teacher_availability (meeting slots)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.teacher_availability (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    day_of_week  INTEGER NOT NULL CHECK (day_of_week BETWEEN 1 AND 7), -- 1=Mon .. 7=Sun
    start_time   TIME NOT NULL,
    end_time     TIME NOT NULL,
    active       BOOLEAN DEFAULT TRUE,
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------
-- 3. classes
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.classes (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    class_name    TEXT NOT NULL,
    academic_year TEXT NOT NULL,
    semester      TEXT NOT NULL,
    section       TEXT DEFAULT '',
    active        BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_teacher_class UNIQUE (teacher_id, class_name, academic_year)
);

-- ------------------------------------------------------------------
-- 4. subjects
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subjects (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    subject_code TEXT NOT NULL,
    subject_name TEXT NOT NULL,
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_teacher_subject UNIQUE (teacher_id, subject_code)
);

-- ------------------------------------------------------------------
-- 5. class_subjects (class + subject context & settings)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.class_subjects (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id          UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    class_id            UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    subject_id          UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
    google_form_url     TEXT DEFAULT '',
    threshold_percent   NUMERIC DEFAULT 75.00,
    alert_enabled       BOOLEAN DEFAULT TRUE,
    alert_frequency     TEXT DEFAULT 'weekly',
    alert_time          TIME DEFAULT '09:00:00',
    weekly_day          INTEGER DEFAULT 1,
    interval_days       INTEGER DEFAULT 7,
    reminder_days       INTEGER DEFAULT 7,
    active              BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_class_subject UNIQUE (class_id, subject_id)
);

-- ------------------------------------------------------------------
-- 6. students (master identity — PRN is the identifier, not the name)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.students (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    prn          TEXT NOT NULL,
    student_name TEXT NOT NULL,
    email        TEXT DEFAULT '',
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    updated_at   TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_teacher_prn UNIQUE (teacher_id, prn)
);

-- ------------------------------------------------------------------
-- 7. enrollments (student <-> class+subject)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.enrollments (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_subject_id UUID NOT NULL REFERENCES public.class_subjects(id) ON DELETE CASCADE,
    student_id       UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    enrolled_from    DATE NOT NULL DEFAULT CURRENT_DATE,
    enrolled_to      DATE NULL,
    active           BOOLEAN DEFAULT TRUE,
    created_at       TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_class_subject_student UNIQUE (class_subject_id, student_id)
);

-- ------------------------------------------------------------------
-- 8. attendance_sessions (one lecture)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance_sessions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_subject_id UUID NOT NULL REFERENCES public.class_subjects(id) ON DELETE CASCADE,
    lecture_date     DATE NOT NULL DEFAULT CURRENT_DATE,
    period_number    INTEGER DEFAULT 1,
    started_at       TIMESTAMPTZ DEFAULT NOW(),
    ended_at         TIMESTAMPTZ NULL,
    status           TEXT DEFAULT 'draft' CHECK (status IN ('draft','active','completed','cancelled')),
    created_at       TIMESTAMPTZ DEFAULT NOW(),
    -- one session per class+subject+date+period
    CONSTRAINT unique_lecture UNIQUE (class_subject_id, lecture_date, period_number)
);

-- ------------------------------------------------------------------
-- 9. attendance_records (one student result in one lecture)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance_records (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    status     TEXT NOT NULL DEFAULT 'absent' CHECK (status IN ('present','absent')),
    source     TEXT NOT NULL DEFAULT 'default' CHECK (source IN ('voice','manual','default')),
    marked_at  TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_session_student UNIQUE (session_id, student_id)   -- Rule 7
);

-- ------------------------------------------------------------------
-- 10. attendance_alerts (email history / anti-spam)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance_alerts (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_subject_id   UUID NOT NULL REFERENCES public.class_subjects(id) ON DELETE CASCADE,
    student_id         UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    attendance_percent NUMERIC NOT NULL,
    attended_count     INTEGER NOT NULL,
    conducted_count    INTEGER NOT NULL,
    alert_type         TEXT DEFAULT 'initial' CHECK (alert_type IN ('initial','reminder')),
    sent_at            TIMESTAMPTZ DEFAULT NOW(),
    status             TEXT DEFAULT 'sent' CHECK (status IN ('sent','failed','pending')),
    error_message      TEXT NULL
);

-- ------------------------------------------------------------------
-- Indexes
-- ------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_classes_teacher        ON public.classes(teacher_id);
CREATE INDEX IF NOT EXISTS idx_subjects_teacher      ON public.subjects(teacher_id);
CREATE INDEX IF NOT EXISTS idx_class_subjects_teacher ON public.class_subjects(teacher_id);
CREATE INDEX IF NOT EXISTS idx_students_teacher       ON public.students(teacher_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_cs         ON public.enrollments(class_subject_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_student    ON public.enrollments(student_id);
CREATE INDEX IF NOT EXISTS idx_sessions_cs            ON public.attendance_sessions(class_subject_id);
CREATE INDEX IF NOT EXISTS idx_sessions_status        ON public.attendance_sessions(class_subject_id, status);
CREATE INDEX IF NOT EXISTS idx_records_session        ON public.attendance_records(session_id);
CREATE INDEX IF NOT EXISTS idx_records_student        ON public.attendance_records(student_id);
CREATE INDEX IF NOT EXISTS idx_alerts_cs_student      ON public.attendance_alerts(class_subject_id, student_id);

-- ------------------------------------------------------------------
-- auto updated_at
-- ------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_students_updated_at ON public.students;
CREATE TRIGGER trg_students_updated_at BEFORE UPDATE ON public.students
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ------------------------------------------------------------------
-- Row Level Security
-- ------------------------------------------------------------------
ALTER TABLE public.profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teacher_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_subjects       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_sessions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_records   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_alerts    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own profile"    ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile"  ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile"  ON public.profiles;
CREATE POLICY "Users can view own profile"   ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Teachers can manage availability" ON public.teacher_availability;
CREATE POLICY "Teachers can manage availability" ON public.teacher_availability FOR ALL
    USING (auth.uid() = teacher_id) WITH CHECK (auth.uid() = teacher_id);

DROP POLICY IF EXISTS "Teachers can manage classes" ON public.classes;
CREATE POLICY "Teachers can manage classes" ON public.classes FOR ALL
    USING (auth.uid() = teacher_id) WITH CHECK (auth.uid() = teacher_id);

DROP POLICY IF EXISTS "Teachers can manage subjects" ON public.subjects;
CREATE POLICY "Teachers can manage subjects" ON public.subjects FOR ALL
    USING (auth.uid() = teacher_id) WITH CHECK (auth.uid() = teacher_id);

DROP POLICY IF EXISTS "Teachers can manage class_subjects" ON public.class_subjects;
CREATE POLICY "Teachers can manage class_subjects" ON public.class_subjects FOR ALL
    USING (auth.uid() = teacher_id) WITH CHECK (auth.uid() = teacher_id);

DROP POLICY IF EXISTS "Teachers can manage students" ON public.students;
CREATE POLICY "Teachers can manage students" ON public.students FOR ALL
    USING (auth.uid() = teacher_id) WITH CHECK (auth.uid() = teacher_id);

DROP POLICY IF EXISTS "Teachers can manage enrollments" ON public.enrollments;
CREATE POLICY "Teachers can manage enrollments" ON public.enrollments FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.class_subjects cs
            WHERE cs.id = enrollments.class_subject_id AND cs.teacher_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.class_subjects cs
            WHERE cs.id = enrollments.class_subject_id AND cs.teacher_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Teachers can manage sessions" ON public.attendance_sessions;
CREATE POLICY "Teachers can manage sessions" ON public.attendance_sessions FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.class_subjects cs
            WHERE cs.id = attendance_sessions.class_subject_id AND cs.teacher_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.class_subjects cs
            WHERE cs.id = attendance_sessions.class_subject_id AND cs.teacher_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Teachers can manage records" ON public.attendance_records;
CREATE POLICY "Teachers can manage records" ON public.attendance_records FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.attendance_sessions s
            JOIN public.class_subjects cs ON cs.id = s.class_subject_id
            WHERE s.id = attendance_records.session_id AND cs.teacher_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.attendance_sessions s
            JOIN public.class_subjects cs ON cs.id = s.class_subject_id
            WHERE s.id = attendance_records.session_id AND cs.teacher_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Teachers can view alerts" ON public.attendance_alerts;
CREATE POLICY "Teachers can view alerts" ON public.attendance_alerts FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.class_subjects cs
            WHERE cs.id = attendance_alerts.class_subject_id AND cs.teacher_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.class_subjects cs
            WHERE cs.id = attendance_alerts.class_subject_id AND cs.teacher_id = auth.uid()
        )
    );

-- ------------------------------------------------------------------
-- Auto-create teacher profile on signup
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, email)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', SPLIT_PART(NEW.email, '@', 1)),
        NEW.email
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
