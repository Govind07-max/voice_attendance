-- Smart Attendance Ubiquitous System Initial Database Schema
-- Migration File: 20260923000000_initial_schema.sql

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Profiles Table (Teacher Profiles)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    faculty_id TEXT DEFAULT '',
    email TEXT NOT NULL,
    department TEXT DEFAULT '',
    phone TEXT DEFAULT '',
    timezone TEXT DEFAULT 'UTC',
    default_threshold NUMERIC DEFAULT 75.00,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Teacher Availability Table (Meeting slots)
CREATE TABLE IF NOT EXISTS public.teacher_availability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 1 AND 7), -- 1 = Monday, 7 = Sunday
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Classes Table
CREATE TABLE IF NOT EXISTS public.classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    class_name TEXT NOT NULL,
    academic_year TEXT NOT NULL,
    semester TEXT NOT NULL,
    section TEXT DEFAULT '',
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Subjects Table
CREATE TABLE IF NOT EXISTS public.subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    subject_code TEXT NOT NULL,
    subject_name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Class Subjects Table (Connecting Classes & Subjects + Settings)
CREATE TABLE IF NOT EXISTS public.class_subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
    google_form_url TEXT DEFAULT '',
    threshold_percent NUMERIC DEFAULT 75.00,
    alert_enabled BOOLEAN DEFAULT TRUE,
    alert_frequency TEXT DEFAULT 'weekly',
    alert_time TIME DEFAULT '09:00:00',
    weekly_day INTEGER DEFAULT 1,
    interval_days INTEGER DEFAULT 7,
    reminder_days INTEGER DEFAULT 7,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_class_subject UNIQUE (class_id, subject_id)
);

-- 6. Students Master Table
CREATE TABLE IF NOT EXISTS public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    prn TEXT NOT NULL,
    student_name TEXT NOT NULL,
    email TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_teacher_prn UNIQUE (teacher_id, prn)
);

-- 7. Enrollments Table
CREATE TABLE IF NOT EXISTS public.enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_subject_id UUID NOT NULL REFERENCES public.class_subjects(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    enrolled_from DATE NOT NULL DEFAULT CURRENT_DATE,
    enrolled_to DATE NULL,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_class_subject_student UNIQUE (class_subject_id, student_id)
);

-- 8. Attendance Sessions Table
CREATE TABLE IF NOT EXISTS public.attendance_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_subject_id UUID NOT NULL REFERENCES public.class_subjects(id) ON DELETE CASCADE,
    lecture_date DATE NOT NULL DEFAULT CURRENT_DATE,
    period_number INTEGER DEFAULT 1,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ NULL,
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Attendance Records Table
CREATE TABLE IF NOT EXISTS public.attendance_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'absent' CHECK (status IN ('present', 'absent')),
    source TEXT NOT NULL DEFAULT 'default' CHECK (source IN ('voice', 'manual', 'default')),
    marked_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_session_student UNIQUE (session_id, student_id)
);

-- 10. Attendance Alerts Table
CREATE TABLE IF NOT EXISTS public.attendance_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_subject_id UUID NOT NULL REFERENCES public.class_subjects(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    attendance_percent NUMERIC NOT NULL,
    attended_count INTEGER NOT NULL,
    conducted_count INTEGER NOT NULL,
    alert_type TEXT DEFAULT 'initial' CHECK (alert_type IN ('initial', 'reminder')),
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    status TEXT DEFAULT 'sent' CHECK (status IN ('sent', 'failed', 'pending')),
    error_message TEXT NULL
);

-- Indexes for fast query performance
CREATE INDEX IF NOT EXISTS idx_classes_teacher ON public.classes(teacher_id);
CREATE INDEX IF NOT EXISTS idx_subjects_teacher ON public.subjects(teacher_id);
CREATE INDEX IF NOT EXISTS idx_class_subjects_teacher ON public.class_subjects(teacher_id);
CREATE INDEX IF NOT EXISTS idx_students_teacher ON public.students(teacher_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_cs ON public.enrollments(class_subject_id);
CREATE INDEX IF NOT EXISTS idx_sessions_cs ON public.attendance_sessions(class_subject_id);
CREATE INDEX IF NOT EXISTS idx_records_session ON public.attendance_records(session_id);
CREATE INDEX IF NOT EXISTS idx_alerts_cs_student ON public.attendance_alerts(class_subject_id, student_id);

-- Enable Row Level Security (RLS) on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teacher_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_alerts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for Profiles
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- RLS Policies for Teacher Availability
CREATE POLICY "Teachers can manage availability" ON public.teacher_availability FOR ALL USING (auth.uid() = teacher_id);

-- RLS Policies for Classes
CREATE POLICY "Teachers can manage classes" ON public.classes FOR ALL USING (auth.uid() = teacher_id);

-- RLS Policies for Subjects
CREATE POLICY "Teachers can manage subjects" ON public.subjects FOR ALL USING (auth.uid() = teacher_id);

-- RLS Policies for Class Subjects
CREATE POLICY "Teachers can manage class_subjects" ON public.class_subjects FOR ALL USING (auth.uid() = teacher_id);

-- RLS Policies for Students
CREATE POLICY "Teachers can manage students" ON public.students FOR ALL USING (auth.uid() = teacher_id);

-- RLS Policies for Enrollments
CREATE POLICY "Teachers can manage enrollments" ON public.enrollments FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.class_subjects cs
        WHERE cs.id = enrollments.class_subject_id AND cs.teacher_id = auth.uid()
    )
);

-- RLS Policies for Attendance Sessions
CREATE POLICY "Teachers can manage sessions" ON public.attendance_sessions FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.class_subjects cs
        WHERE cs.id = attendance_sessions.class_subject_id AND cs.teacher_id = auth.uid()
    )
);

-- RLS Policies for Attendance Records
CREATE POLICY "Teachers can manage records" ON public.attendance_records FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.attendance_sessions s
        JOIN public.class_subjects cs ON cs.id = s.class_subject_id
        WHERE s.id = attendance_records.session_id AND cs.teacher_id = auth.uid()
    )
);

-- RLS Policies for Attendance Alerts
CREATE POLICY "Teachers can view alerts" ON public.attendance_alerts FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.class_subjects cs
        WHERE cs.id = attendance_alerts.class_subject_id AND cs.teacher_id = auth.uid()
    )
);

-- Automatic Profile Creation Trigger on Auth Sign-Up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, email)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', SPLIT_PART(NEW.email, '@', 1)),
        NEW.email
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
