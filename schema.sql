-- ============================================================================
-- THE ANUBHAV MODEL — Live Program Database Schema
-- Run this once, in full, in your Supabase project's SQL Editor
-- (Supabase dashboard → SQL Editor → New query → paste all of this → Run)
-- ============================================================================

-- ---------- Extensions ----------
create extension if not exists "pgcrypto"; -- for gen_random_uuid()

-- ============================================================================
-- TABLES
-- ============================================================================

-- Cohorts: one row per school / cluster of schools running the program
create table public.cohorts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tier text not null check (tier in ('foundation', 'enhanced')) default 'foundation',
  current_cycle int not null default 1 check (current_cycle between 1 and 8),
  created_at timestamptz not null default now()
);

-- Profiles: one row per person, linked 1:1 to Supabase's built-in auth.users
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  school text,
  role text not null check (role in ('teacher', 'facilitator', 'admin')) default 'teacher',
  cohort_id uuid references public.cohorts(id),
  created_at timestamptz not null default now()
);

-- Cycles: the 8 fixed micro-cycles of the Year 1 arc (seeded below, rarely edited)
create table public.cycles (
  id int primary key check (id between 1 and 8),
  title text not null,
  subtitle text not null,
  weeks text not null,
  strand text not null,
  goals jsonb not null default '[]'::jsonb,
  seed_problems jsonb not null default '[]'::jsonb,
  briefing text not null
);

-- Problem Ledger: live problems teachers bring into a cycle
create table public.problem_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  cohort_id uuid not null references public.cohorts(id),
  teacher_id uuid not null references public.profiles(id),
  cycle_id int not null references public.cycles(id),
  problem_text text not null,
  status text not null check (status in ('open', 'clustered', 'carried_forward', 'resolved')) default 'open',
  created_at timestamptz not null default now()
);

-- Practice Cards: the Module Mint output — draft, reviewed, then published to the library
create table public.practice_cards (
  id uuid primary key default gen_random_uuid(),
  cohort_id uuid not null references public.cohorts(id),
  cycle_id int not null references public.cycles(id),
  author_id uuid not null references public.profiles(id),
  problem_statement text not null,
  context text not null,
  tried text not null,
  happened text not null,
  tags text,
  lineage text,
  status text not null check (status in ('draft', 'in_review', 'published', 'rejected')) default 'draft',
  reviewer_id uuid references public.profiles(id),
  review_notes text,
  created_at timestamptz not null default now(),
  published_at timestamptz
);

-- ============================================================================
-- HELPER FUNCTIONS (security definer — used inside RLS policies below,
-- written this way specifically to avoid recursive-policy errors on profiles)
-- ============================================================================

create or replace function public.my_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.my_cohort()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select cohort_id from public.profiles where id = auth.uid();
$$;

-- Auto-create a profile row whenever someone signs up.
-- Expects full_name, school, role, cohort_id to be passed as signup metadata (see auth.js).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, school, role, cohort_id)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'New Teacher'),
    new.raw_user_meta_data->>'school',
    coalesce(new.raw_user_meta_data->>'role', 'teacher'),
    nullif(new.raw_user_meta_data->>'cohort_id', '')::uuid
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

alter table public.cohorts enable row level security;
alter table public.profiles enable row level security;
alter table public.cycles enable row level security;
alter table public.problem_ledger_entries enable row level security;
alter table public.practice_cards enable row level security;

-- Cohorts: readable by anyone signed in (needed to populate the signup form's cohort picker)
create policy "cohorts_select_authenticated" on public.cohorts
  for select using (auth.role() = 'authenticated');

-- Cycles: publicly readable, including anonymous visitors (the public library page needs this)
create policy "cycles_select_all" on public.cycles
  for select using (true);

-- Profiles: everyone can see their own row; facilitators/admins can see everyone in their cohort
create policy "profiles_select_own" on public.profiles
  for select using (id = auth.uid());

create policy "profiles_select_cohort_staff" on public.profiles
  for select using (
    public.my_role() in ('facilitator', 'admin') and cohort_id = public.my_cohort()
  );

create policy "profiles_update_own" on public.profiles
  for update using (id = auth.uid());

-- Problem Ledger: teachers manage their own entries; cohort staff see everything in their cohort
create policy "ledger_insert_own" on public.problem_ledger_entries
  for insert with check (teacher_id = auth.uid());

create policy "ledger_select_own" on public.problem_ledger_entries
  for select using (teacher_id = auth.uid());

create policy "ledger_select_cohort_staff" on public.problem_ledger_entries
  for select using (
    public.my_role() in ('facilitator', 'admin') and cohort_id = public.my_cohort()
  );

create policy "ledger_update_cohort_staff" on public.problem_ledger_entries
  for update using (
    public.my_role() in ('facilitator', 'admin') and cohort_id = public.my_cohort()
  );

-- Practice Cards: authors manage their own drafts; cohort staff review; PUBLISHED cards are public
create policy "cards_insert_own" on public.practice_cards
  for insert with check (author_id = auth.uid());

create policy "cards_select_own" on public.practice_cards
  for select using (author_id = auth.uid());

create policy "cards_select_cohort_staff" on public.practice_cards
  for select using (
    public.my_role() in ('facilitator', 'admin') and cohort_id = public.my_cohort()
  );

create policy "cards_select_published_public" on public.practice_cards
  for select using (status = 'published');

create policy "cards_update_own_draft" on public.practice_cards
  for update using (author_id = auth.uid() and status = 'draft');

create policy "cards_update_cohort_staff" on public.practice_cards
  for update using (
    public.my_role() in ('facilitator', 'admin') and cohort_id = public.my_cohort()
  );

-- ============================================================================
-- SEED DATA — the 8 cycles (safe to re-run: upserts on primary key)
-- ============================================================================

insert into public.cycles (id, title, subtitle, weeks, strand, goals, seed_problems, briefing) values
(1, 'Foundations', 'Building the Room: Culture, Trust, and the Loop Itself', 'Weeks 1–6', 'Collaborative Co-Researcher',
 '["Establish the psychological-safety norms the whole program depends on.","Practice the four phases of the Anubhav Loop once, on a low-stakes problem, before real problems enter the Ledger.","Form buddy pairs and review groups that will stay together for the year."]',
 '["A new class doesn''t yet know how to disagree with each other productively during discussion.","Teachers don''t know their students'' names and starting points well enough by week 3."]',
 'Every professional-learning system depends on psychological safety before it depends on technique. Cycle 1 runs the full Loop once on a low-stakes problem so teachers experience Name, Try, Capture, and Return before anything they care deeply about is on the table.'),
(2, 'Engagement & Motivation', 'Reaching Reluctant and Disengaged Learners', 'Weeks 7–12', 'Adaptive Problem-Solver',
 '["Diagnose disengagement as a solvable design problem rather than a fixed trait of a student.","Trial at least one choice-based or peer-structured engagement change.","Practice noticing and naming small wins in student participation."]',
 '["Six students refuse to read aloud, and two are meaningfully behind grade level.","A capable student does the bare minimum and disengages the moment work gets easy."]',
 'Active learning is one of Darling-Hammond''s seven features of effective professional development, and the same logic drives student engagement. Choice-based reading and near-peer tutoring both hand students a small piece of control back.'),
(3, 'Core Pedagogy', 'Active Learning in Mixed-Ability Classrooms', 'Weeks 13–18', 'Reflective Practitioner',
 '["Move at least one routine from whole-class lecture toward active, structured practice.","Design a station or rotation model that keeps fast finishers and strugglers both productively occupied.","Use one piece of real classroom data to inform grouping."]',
 '["A single teacher with 40 mixed-ability students has fast finishers bored and strugglers left behind, with no assistant support.","A lecture-heavy routine leaves the back third of the room visibly checked out by the 20-minute mark."]',
 'Lesson study treats the real, observable lesson as the object of collective improvement. Station rotation differentiates instruction without requiring extra staff, and a light use of exit-ticket data keeps grouping current.'),
(4, 'Assessment & Feedback', 'Feedback That Actually Moves Learning', 'Weeks 19–24', 'Reflective Practitioner',
 '["Replace at least one piece of vague or grade-only feedback with task-, process-, or self-regulation-level feedback.","Build a lightweight formative check into an existing routine, not as extra work.","Notice the difference between feedback students act on and feedback they ignore."]',
 '["Students glance at the grade on returned work and never read the comments underneath it.","A teacher can''t tell, in the moment, which half of the class actually understood today''s lesson."]',
 'Feedback only moves learning when it is timely, specific, and tied to a clear standard the student understands (Hattie & Timperley). Most classroom feedback never leaves the task level; this cycle shifts toward process and self-regulation feedback.'),
(5, 'Sustaining the Teacher', 'Wellbeing and Workload at the Mid-Year Point', 'Weeks 25–30', 'Grounded & Well',
 '["Name workload and energy honestly, without it being treated as a complaint.","Trial one concrete change to a personally unsustainable routine, not just a mindset shift.","Reconnect with why the work matters, deliberately, at the point of the year fatigue is highest."]',
 '["A teacher is answering parent messages late into the evening and can''t find where to draw a line.","Preparation time has quietly expanded to fill every free period, leaving no recovery time in the working day."]',
 'Structural change — autonomy, collaboration, a supportive environment — is the load-bearing factor in teacher wellbeing, not coping techniques layered on top of an unchanged workload. This cycle points the Loop at the teacher''s own routine.'),
(6, 'Technology & AI', 'Used Well, Not Just Used', 'Weeks 31–36', 'Digital & AI-Fluent Educator',
 '["Distinguish AI use that supports learning from AI use that replaces it.","Trial one classroom policy or routine that makes student thinking visible again.","Practice explaining an AI-related decision to students in plain, non-punitive language."]',
 '["Students are submitting AI-generated essays and the teacher is unsure how to respond pedagogically rather than punitively.","A teacher wants to use an AI tool for lesson planning but isn''t sure where to draw the line on relying on it."]',
 'Detection of AI-generated text is unreliable and often punitive in effect. This cycle redesigns tasks so student thinking has to happen visibly, in the room, regardless of what tools exist outside it.'),
(7, 'Inclusion & Differentiation', 'Designing for Variability From the Start', 'Weeks 37–42', 'Adaptive Problem-Solver',
 '["Redesign one task using a Universal Design for Learning lens, rather than reacting case-by-case.","Distinguish anticipating learner variability (UDL) from reacting to it after the fact.","Trial a change that helps more than one student at once, not a single individualised fix."]',
 '["A teacher is making one-off accommodations for individual students reactively, and it''s becoming unsustainable.","A student with limited English proficiency and a student with a reading difficulty both struggle with the same worksheet, for different reasons."]',
 'UDL anticipates learner variability across an entire class and builds multiple means of engagement, representation, and expression into a task from the start, rather than reacting to individual needs one at a time.'),
(8, 'Harvest', 'Consolidation, Showcase, and Next Year''s Design', 'Weeks 43–48', 'Collaborative Co-Researcher',
 '["Review the year''s Practice Card library as a body of work, not scattered artifacts.","Publicly showcase the cycle each teacher is proudest of.","Nominate facilitators for next year from among this year''s most active contributors."]',
 '["A strong Practice Card from Cycle 2 was never picked up or tried by anyone outside its original author''s classroom.","The Problem Ledger has three recurring, unresolved problems that no single cycle fully solved this year."]',
 'A module library goes stale without deliberate re-circulation. This cycle runs a showcase structure borrowed from Japan''s public research lessons, and names succession into the facilitator pipeline structurally.')
on conflict (id) do update set
  title = excluded.title, subtitle = excluded.subtitle, weeks = excluded.weeks, strand = excluded.strand,
  goals = excluded.goals, seed_problems = excluded.seed_problems, briefing = excluded.briefing;

-- ============================================================================
-- OPTIONAL: a starter cohort so you can test signup immediately.
-- Rename it, or add more cohorts, from the Supabase Table Editor any time.
-- ============================================================================
insert into public.cohorts (name, tier, current_cycle)
values ('Pilot Cohort', 'foundation', 1)
on conflict do nothing;
