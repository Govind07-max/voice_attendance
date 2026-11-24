-- ------------------------------------------------------------------
-- attendance_edits — audit trail for manual attendance corrections
--
-- Voice marks and the initial defaults are not logged (they are already
-- visible as the record's source). Every time a teacher manually flips a
-- student's status, one row is appended here so a disputed percentage can
-- always be explained.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance_edits (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    old_status TEXT,
    new_status TEXT NOT NULL,
    old_source TEXT,
    new_source TEXT NOT NULL DEFAULT 'manual',
    edited_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attendance_edits_session
    ON public.attendance_edits(session_id);
CREATE INDEX IF NOT EXISTS idx_attendance_edits_teacher
    ON public.attendance_edits(teacher_id);

ALTER TABLE public.attendance_edits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Teachers can insert their own edits"
    ON public.attendance_edits;
DROP POLICY IF EXISTS "Teachers can view their own edits"
    ON public.attendance_edits;

CREATE POLICY "Teachers can insert their own edits"
    ON public.attendance_edits FOR INSERT
    WITH CHECK (auth.uid() = teacher_id);

CREATE POLICY "Teachers can view their own edits"
    ON public.attendance_edits FOR SELECT
    USING (auth.uid() = teacher_id);
