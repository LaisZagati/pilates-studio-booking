# Architecture & Implementation Plan

## Stack
| Layer | Choice |
|---|---|
| App | Next.js 15 (App Router), React 19, TypeScript, Tailwind CSS 4 |
| Data | Supabase PostgreSQL with Row Level Security |
| Auth | Supabase Auth (email + password, email confirmation, password reset) |
| Server logic | Postgres functions (booking engine) called via Server Actions / Route Handlers |
| Email | Resend, driven by a `notifications` outbox table (Phase 6) |
| Hosting | Vercel (+ Vercel Cron for reminders and auto-complete) |

```
Browser (client site / /admin PWA)
   │  Server Actions & Route Handlers (Next.js on Vercel)
   ▼
Supabase  ── Auth (sessions in HTTP-only cookies)
          ── Postgres: tables + RLS + booking-engine functions
          ── Realtime: bookings / sessions / blocked_slots → admin calendar
Vercel Cron ─► /api/cron/notifications  ─► Resend
```

## Booking engine (the important part)

**Equipment is modelled as rows, not as numbers.** `resources` holds *Reformer 1*,
*Reformer 2* and *Mat studio*. Each `session` claims specific resources in
`session_resources`, whose time range includes the buffer.

An **exclusion constraint** on `session_resources (resource_id WITH =, during WITH &&)`
means the database itself rejects any second claim on the same reformer for an
overlapping time — whatever code path tries it, and however many people click at
once. With two reformer rows, *more than two reformers in use* is physically
impossible to store.

| Service | Reformers claimed | Seats | Who shares |
|---|---|---|---|
| Private Reformer | 1 | 1 | nobody — one booking = whole session |
| Duet Reformer | 2 | 2 | one booking for 1–2 people takes the whole session |
| Mat Pilates | 0 (claims *Mat studio*) | 4 | separate clients join the same session |

Consequences: two Privates can run side by side (one reformer each); a Duet
blocks every other reformer booking; a Private blocks a Duet; Mat is independent of
reformers; two Mat classes can't overlap (one mat room). Adding a third reformer
later is one `insert into resources`.

**Concurrency.** Every write (`book_session`, `cancel_booking`, `reschedule_booking`,
admin functions) runs in a single transaction that first takes a studio-wide
advisory lock, then re-checks availability against committed data. Mat seat counts
are checked under that lock; reformers are additionally guaranteed by the
constraint. Duplicate submissions are absorbed by an `idempotency_key`.

**Availability** is computed by `get_available_slots(service, from, to)` from opening
hours (`availability_rules`), the minimum notice and maximum window, the buffer,
whole-studio or per-reformer blocks, holidays, and live equipment/seat usage. It
returns only times and free spots — never who booked — so it's safe for anonymous
visitors.

**Owner override** skips opening hours, notice periods, blocks and Mat capacity
(a reason is required and the booking is flagged) but **never** the equipment limit.

## Security
- RLS on every table. Clients see only their own client row, bookings, sessions
  and payments; private notes live in `client_notes` (admin only).
- Booking tables have **no direct write grants**; all changes go through
  `SECURITY DEFINER` functions that validate inputs and check `is_admin()` /
  ownership. Column grants stop clients editing anything but their name and phone.
- Guests manage a booking with its reference + a random token emailed to them
  (stored only as a SHA-256 hash).
- `/admin` is gated three times: middleware, the admin layout (`requireAdmin`), and
  the database (`is_admin()` in RLS and functions).
- The service role key is server-only (`server-only` import makes leaking it a
  build error). Private pages send `Cache-Control: private, no-store`; the service
  worker (Phase 8) will never cache `/admin`, `/account` or API/Supabase requests.

## Data model
`business_settings`, `notification_settings`, `profiles`, `admins`, `clients`,
`client_notes`, `instructors`, `instructor_availability`, `services`, `resources`,
`availability_rules`, `blocked_slots` (block / holiday / private appointment),
`recurring_series`, `sessions`, `session_resources`, `bookings`,
`reschedule_requests`, `payments` (ledger → `payment_status` paid/partial/unpaid/refunded),
`notifications` (outbox). View: `admin_calendar` (security-invoker).

## Phases
1. **Architecture, schema, auth** ✅
2. Public website & service pages
3. Booking flow UI (service → date → time → details → confirmation)
4. Owner dashboard: stats, day/week/month calendar, manual bookings, blocks, services, clients, instructors, settings
5. Client account: upcoming/history, cancel, reschedule request, profile
6. Email notifications (Resend) + payment recording UI
7. Mobile-first polish (bottom nav, agenda calendar on phones, 320–430px checks)
8. PWA: manifest, icons, Apple meta tags, safe areas, secure service worker
9. Security, performance & end-to-end testing
