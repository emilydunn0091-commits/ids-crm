# ID Management CRM Portal
Static HTML/CSS/JS front end + Supabase (Auth, Postgres, RLS). Deploys on Vercel.

## 1. Supabase
1. Create a project at supabase.com.
2. SQL Editor > New query > paste `supabase/schema.sql` > Run.
3. Authentication > Providers > Email: keep enabled. Turn **off** "Allow new users to sign up" (Authentication > Sign In / Providers) so only accounts you create can log in.
4. Project Settings > API: copy the **Project URL** and the **anon / publishable key**. Never use the service_role key in this project.

## 2. First Admin (secure)
1. Authentication > Users > Add user > enter email + password (tick Auto Confirm).
2. SQL Editor, run:
   `update public.profiles set role='admin', full_name='Your Name' where email='you@example.com';`
   Admin can only be granted this way (the app and API cannot self-promote).

## 3. Team Lead accounts
Create each in Authentication > Users > Add user. They are Team Leads by default. Admin can rename/deactivate them from the Team Leads page (set full name in Supabase user metadata `full_name`, or via SQL: `update public.profiles set full_name='Ali' where email='...';`).

## 4. Run locally
Edit `public/config.js` with your URL + anon key, then serve `public/` (e.g. `npx serve public`).

## 5. Deploy on Vercel
1. Push this folder to GitHub, import it in Vercel.
2. Environment Variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
3. Deploy. `build.js` generates `public/config.js` from those variables (framework preset: Other).

## Security notes
- All permissions are enforced by Postgres RLS; the UI only mirrors them.
- ID passwords are stored as plain text because the spec requires showing them. Anyone with Supabase dashboard / DB access can read them. Keep the dashboard locked down with MFA, and consider column encryption (Supabase Vault) if requirements change.
- Every change to UID, password, reason or remarks is logged in `id_update_history` (old + new values, user, time).
- "Explicit cross-Team-Lead authorization" is not implemented: Team Leads see only their own files; Admin sees all.
