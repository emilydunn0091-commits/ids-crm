// Vercel serverless function: lets a Team Lead (or Admin) create a member login.
// Vercel > Settings > Environment Variables must contain SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.
// The service-role key stays on the server; it is never sent to the browser.
module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Use POST' });
  const U = (process.env.SUPABASE_URL || '').replace(/\/$/, ''), K = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!U || !K) return res.status(500).json({ error: 'Server not configured: add SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in Vercel, then redeploy.' });
  const H = { apikey: K, Authorization: 'Bearer ' + K, 'Content-Type': 'application/json' };
  try {
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    if (!token) return res.status(401).json({ error: 'Not signed in' });
    const ur = await fetch(U + '/auth/v1/user', { headers: { apikey: K, Authorization: 'Bearer ' + token } });
    if (!ur.ok) return res.status(401).json({ error: 'Session expired. Please sign in again.' });
    const caller = await ur.json();
    const pr = await (await fetch(`${U}/rest/v1/profiles?id=eq.${caller.id}&select=role,active`, { headers: H })).json();
    if (!Array.isArray(pr) || !pr[0] || !pr[0].active || !['team_lead', 'admin'].includes(pr[0].role))
      return res.status(403).json({ error: 'Not allowed' });
    const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
    const name = String(body.name || '').trim(), email = String(body.email || '').trim().toLowerCase(), password = String(body.password || '');
    if (!name || name.length > 100) return res.status(400).json({ error: 'Enter a valid name' });
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return res.status(400).json({ error: 'Enter a valid email' });
    if (password.length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters' });
    const cr = await fetch(U + '/auth/v1/admin/users', { method: 'POST', headers: H,
      body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { full_name: name } }) });
    const cu = await cr.json();
    if (!cr.ok) return res.status(400).json({ error: cu.msg || cu.message || cu.error_description || 'Could not create user' });
    const up = await fetch(`${U}/rest/v1/profiles?id=eq.${cu.id}`, { method: 'PATCH', headers: { ...H, Prefer: 'return=representation' },
      body: JSON.stringify({ role: 'member', lead_id: caller.id, active: true, full_name: name }) });
    const rows = up.ok ? await up.json() : [];
    if (!rows.length) {
      await fetch(`${U}/auth/v1/admin/users/${cu.id}`, { method: 'DELETE', headers: H });
      return res.status(500).json({ error: 'Could not set up the member profile. Run migration-members.sql in Supabase first.' });
    }
    return res.status(200).json({ ok: true, id: cu.id });
  } catch (e) {
    return res.status(500).json({ error: 'Server error: ' + e.message });
  }
};
