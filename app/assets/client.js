// Shared Supabase client + small helpers used by every page in /app.
// Depends on config.js being loaded first (defines SUPABASE_URL / SUPABASE_ANON_KEY)
// and the Supabase JS CDN script being loaded before this file.

const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

function showMessage(el, text, kind = "info") {
  el.textContent = text;
  el.className = "form-msg " + kind;
  el.style.display = text ? "block" : "none";
}

async function getSessionUser() {
  const { data: { session } } = await sb.auth.getSession();
  return session ? session.user : null;
}

async function getMyProfile() {
  const user = await getSessionUser();
  if (!user) return null;
  const { data, error } = await sb
    .from("profiles")
    .select("*, cohorts(name, tier, current_cycle)")
    .eq("id", user.id)
    .single();
  if (error) { console.error(error); return null; }
  return data;
}

// Redirect to login if not signed in. Returns the profile if signed in.
async function requireAuth() {
  const user = await getSessionUser();
  if (!user) {
    window.location.href = "login.html";
    return null;
  }
  const profile = await getMyProfile();
  return profile;
}

// Redirect to dashboard if signed in but not one of the allowed roles.
async function requireRole(allowedRoles) {
  const profile = await requireAuth();
  if (!profile) return null;
  if (!allowedRoles.includes(profile.role)) {
    window.location.href = "dashboard.html";
    return null;
  }
  return profile;
}

async function signOut() {
  await sb.auth.signOut();
  window.location.href = "login.html";
}

function fmtDate(iso) {
  return new Date(iso).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

function statusBadge(status) {
  const map = {
    open: "badge-grey", clustered: "badge-ice", carried_forward: "badge-gold", resolved: "badge-green",
    draft: "badge-grey", in_review: "badge-gold", published: "badge-green", rejected: "badge-red",
  };
  return `<span class="badge ${map[status] || "badge-grey"}">${status.replace("_", " ")}</span>`;
}

function escapeHtml(str) {
  const d = document.createElement("div");
  d.textContent = str == null ? "" : str;
  return d.innerHTML;
}
