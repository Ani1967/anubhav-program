# Deploying the Live Anubhav Program

This turns the static site into a real, working tool — teachers can log in, submit Problem Ledger entries, draft and submit Practice Cards, and facilitators can review and publish them to a public library. No server to run; everything below is clicking through free dashboards plus pasting two values into one file.

Total time: about 20 minutes, no coding.

---

## Step 1 — Create a free Supabase project

1. Go to [supabase.com](https://supabase.com) and sign up (free).
2. Click **New Project**. Pick any name (e.g. "anubhav-program"), set a database password (save it somewhere), pick a region close to your teachers, and create it.
3. Wait about two minutes while it provisions.

## Step 2 — Create the database

1. In your new project, open the **SQL Editor** (left sidebar).
2. Click **New query**.
3. Open `schema.sql` (in this package), copy the entire contents, paste it into the editor.
4. Click **Run**. You should see "Success. No rows returned." This creates every table, security rule, and seeds the 8 cycles plus one starter cohort called "Pilot Cohort."

## Step 3 — Connect the app to your database

1. In Supabase, go to **Settings → API**.
2. Copy the **Project URL** and the **anon / public** key. (Not the `service_role` key — never put that one in a public file or repo.)
3. Open `app/config.js` in this package and paste them in:
   ```js
   const SUPABASE_URL = "https://your-project-ref.supabase.co";
   const SUPABASE_ANON_KEY = "your-long-anon-key";
   ```
4. Save the file. That's the entire connection — the anon key is meant to be public; every actual permission is enforced by the Row Level Security rules `schema.sql` already set up.

## Step 4 — Speed up sign-ups for your pilot (optional but recommended)

By default Supabase requires teachers to confirm their email before logging in, using a shared, rate-limited email sender — fine for a handful of sign-ups, slow if 20 teachers sign up in one afternoon. For a fast pilot:

1. Go to **Authentication → Providers → Email**.
2. Turn **off** "Confirm email."
3. Teachers can now log in immediately after signing up. Turn it back on (or set up your own email sender under **Authentication → Emails → SMTP Settings**) once you're past the pilot and want the extra verification step back.

## Step 5 — Put everything on GitHub Pages

1. Create a new **public** repository on GitHub.
2. Upload the entire contents of this package — `site/`, `app/`, `materials/`, `The_Anubhav_Model.docx`, `schema.sql` — keeping the folder structure exactly as it is.
3. Repo → **Settings → Pages** → Source: branch `main`, folder `/ (root)` → Save.
4. After a minute or two:
   - Program overview + downloadable materials: `https://yourusername.github.io/reponame/site/index.html`
   - The live, working app: `https://yourusername.github.io/reponame/app/index.html`

(Want a custom domain on top of this, or the homepage at the clean root URL instead of `/site/`? Both are quick follow-ups — just ask.)

## Step 6 — Make yourself an admin

1. Go to `app/signup.html` on your live site and create your own account. Pick **Facilitator** as your role and the seeded **Pilot Cohort**.
2. Back in Supabase, open **Table Editor → profiles**, find your row, and change `role` from `facilitator` to `admin` if you want full access (admins and facilitators currently have identical permissions in this build — the distinction exists so you can extend one further later, e.g. giving admins the ability to add cohorts from within the app instead of the Supabase dashboard).

## Ongoing light maintenance (no coding)

All of this happens in the Supabase **Table Editor**, which looks and works like a spreadsheet:

- **Add a new cohort** (a new school or cluster): Table Editor → `cohorts` → Insert row. Give it a name and tier.
- **Advance a cohort to the next cycle**: Table Editor → `cohorts` → edit that row's `current_cycle` number. This is what the teacher dashboard reads to know which cycle's Problem Ledger and Practice Card form to show.
- **Promote someone to facilitator/admin**: Table Editor → `profiles` → find their row → edit `role`.
- **Move a teacher to a different cohort**: same table, edit `cohort_id`.

## What's in free tier vs. worth paying for

**Free tier covers**, comfortably, a pilot and quite a bit past it: 500MB database (many thousands of Problem Ledger entries and Practice Cards — these are short text records), 50,000 monthly active logins, 1GB file storage, and the shared email sender for auth (rate-limited, fine for steady sign-ups, not a mass blast).

**One real limitation on free tier**: an inactive project pauses after about a week with no traffic and needs a manual "resume" click in the dashboard. Fine for an active pilot; annoying if a cohort goes quiet over a school holiday and you forget about it.

**Supabase Pro ($25/month)** removes the pausing, adds daily backups, and raises every limit — worth it once you're running this across more than one or two schools, or once teachers are depending on it being always-on without you checking in on it.

## A note on what this version does and doesn't do

This build covers the core loop: submit a problem, draft and submit a Practice Card, facilitator review and publish, public library. It does **not** yet include: the Evaluation Sheet pulse-checks as live forms (still docx, in `materials/`), buddy-pair check-in tracking, or an in-app way to add cohorts/promote roles without touching the Supabase dashboard directly. All of those are straightforward additions to the same schema and pattern when you're ready for them — just ask.
