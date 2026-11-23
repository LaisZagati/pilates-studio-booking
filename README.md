# Pilates Studio — Booking & Management System

Your own booking platform: public website, client booking and accounts, and a private
owner dashboard at `/admin`. Built with **Next.js 15 · React 19 · TypeScript · Tailwind CSS 4 ·
Supabase (PostgreSQL + Auth)**, deployable on **Vercel**. No third-party booking platform.

The booking engine (availability, reformer allocation, capacity, locking, cancellations,
rescheduling, payments, email queue) lives in the database as tested PostgreSQL functions,
so the website, the installed PWA and future iOS/Android apps all share one engine and one database.

---

## Project structure

```
src/
  app/
    (site)/            Public website + client area
      page.tsx           Home
      services/          Classes list + class detail
      book/              Booking flow (server actions in actions.ts)
      manage/            Guest booking management (reference + private link)
      account/           Client dashboard (signed-in clients)
      login/ signup/     Client authentication pages
    admin/             Owner dashboard (/admin) — protected
      login/             Owner sign-in
      (protected)/       Every page here requires an administrator
    auth/              Auth server actions + email-link callback
    .well-known/       Android Digital Asset Links / Apple Universal Links
    manifest.ts        PWA manifest (/manifest.webmanifest)
    layout.tsx         Root HTML, fonts, Apple/PWA meta tags
    globals.css        Tailwind + studio colour palette (styles)
  components/          UI components (site, booking, auth, icons)
  lib/
    supabase/          Supabase clients (server, browser, public, service-role)
    auth.ts            requireUser / requireAdmin guards
    booking-errors.ts  Booking engine error codes → friendly messages
    studio.ts          Settings, services, opening hours
    native.ts          Web/PWA/iOS bridge (share, deep links, external links)
  middleware.ts        Session refresh + route protection
public/                Icons, service worker (sw.js), offline page
assets/                Brand mark, app-store icons, splash sources
supabase/
  migrations/          Database schema + booking engine (run in order)
  seed.sql             Initial studio data (services, reformers, hours)
  config.toml          Supabase CLI config
tests/db/              Database tests + simultaneous-booking race tests
docs/ARCHITECTURE.md   Design and phase plan
```

---

## Run it on your Mac (VS Code)

**You need:** [Node.js 20 or 22 LTS](https://nodejs.org), [VS Code](https://code.visualstudio.com), and (optional) [Git](https://git-scm.com).

1. Unzip the project (or clone it from GitHub) and open the folder in VS Code:
   **File → Open Folder… → `pilates-studio`**.
2. Open the terminal in VS Code: **Terminal → New Terminal**.
3. Create your local settings file:
   ```bash
   cp .env.example .env.local
   ```
   Open `.env.local` and fill in at least `NEXT_PUBLIC_SUPABASE_URL` and
   `NEXT_PUBLIC_SUPABASE_ANON_KEY` (see the table below). Keep
   `NEXT_PUBLIC_APP_URL=http://localhost:3000`.
4. Install and start:
   ```bash
   npm install
   npm run dev
   ```
5. Open **http://localhost:3000** in your browser. The owner dashboard is at
   **http://localhost:3000/admin**.

Other commands: `npm run build` (production build), `npm run start` (run the build),
`npm run typecheck`, `npm run lint`.

---

## Environment variables

| Variable | Where to get it | Local (`.env.local`) | Vercel | Secret? |
|---|---|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase → Project Settings → API → Project URL | ✅ | ✅ | No |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase → Project Settings → API Keys → **Publishable** key | ✅ | ✅ | No (RLS protects data) |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase → API Keys → **Secret** key | only to test emails | ✅ (Production) | **Yes — server only** |
| `NEXT_PUBLIC_APP_URL` | Your site address | `http://localhost:3000` | `https://your-domain.com` | No |
| `RESEND_API_KEY` | resend.com → API Keys (Phase 6) | optional | ✅ | **Yes** |
| `EMAIL_FROM` | A sender on your verified domain | optional | ✅ | No |
| `CRON_SECRET` | Any long random string (Phase 6) | optional | ✅ | **Yes** |
| `ANDROID_PACKAGE_NAME`, `ANDROID_SHA256_CERT_FINGERPRINTS` | Google Play Console (when publishing) | — | ✅ | No |
| `APPLE_TEAM_ID`, `IOS_BUNDLE_ID` | Apple Developer account (when publishing) | — | ✅ | No |

- **Locally:** put them in `.env.local` (git-ignored, never uploaded).
- **On Vercel:** Project → **Settings → Environment Variables**, add each name and value,
  tick **Production** (and **Preview** if you use preview deployments), then **redeploy**.
- Only variables starting with `NEXT_PUBLIC_` are visible in the browser. Nothing else is.

---

## Database (Supabase)

The live project is already set up (schema, booking engine, seed data). To recreate it
in another Supabase project, run in the **SQL Editor**, in order:

1. `supabase/migrations/20261123000001_init_schema.sql`
2. `supabase/migrations/20261123000002_public_site.sql`
3. `supabase/seed.sql`

Or with the Supabase CLI: `supabase link --project-ref <ref>` then `supabase db push`.

**Auth settings** (Supabase → Authentication → URL Configuration):
- Site URL: your production URL (e.g. `https://your-domain.com`)
- Redirect URLs: `http://localhost:3000/auth/callback` and `https://your-domain.com/auth/callback`

**Make yourself the owner:** sign up on the site, confirm your email, then run
`scripts/make-admin.sql` (with your email) in the SQL Editor.

**Database tests** (needs a local PostgreSQL 15+): `PGHOST=localhost PGUSER=postgres npm run db:test`

---

## Put it on GitHub

`.gitignore` already excludes `node_modules`, `.next`, `.env*` files and other build output.

**Using the terminal in VS Code:**
```bash
git init
git add .
git commit -m "Pilates studio booking system"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/pilates-studio-booking.git
git push -u origin main
```
(Create the empty repository on github.com first: **New repository** → name → **Create**, without a README.)

**Or without commands:** use [GitHub Desktop](https://desktop.github.com) → *Add existing repository* → *Publish*.

---

## Deploy on Vercel

1. vercel.com → **Add New… → Project** → import the GitHub repository.
2. Framework preset: **Next.js** (detected automatically). Leave build settings as default.
3. Add the environment variables from the table above (`NEXT_PUBLIC_APP_URL` = your Vercel or custom domain).
4. **Deploy.** Every push to `main` redeploys automatically.
5. Custom domain: Project → **Settings → Domains** → add your domain and follow the DNS
   instructions. HTTPS is automatic. Then update `NEXT_PUBLIC_APP_URL` and the Supabase
   Auth URLs to the new domain and redeploy.

> Vercel's free Hobby plan is for non-commercial use. For a business site Vercel asks for
> the Pro plan; the app itself doesn't depend on Vercel and runs on any Next.js host.

---

## Status

| Phase | State |
|---|---|
| 1. Architecture, database, booking engine, auth | ✅ Tested (73 database tests + race tests), live on Supabase |
| 2. Public website | ✅ Built — awaiting first full build check |
| 3. Booking flow + guest management | ✅ Built — awaiting first full build check |
| 4. Owner dashboard | ⏳ Next |
| 5. Client account area | Partial (bookings list) |
| 6. Email notifications + payment recording UI | Planned |
| 7. Mobile polish | Ongoing |
| 8. PWA | ✅ Manifest, icons, Apple tags, safe service worker, offline page |
| 9. Final security/performance testing | Planned |
| App Store / Google Play packaging | Prepared after the web app is complete |
