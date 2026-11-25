import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { signOut } from "@/app/auth/actions";
import { getSettings } from "@/lib/studio";
import { formatDateLong, formatPrice, formatTime, dateKey } from "@/lib/format";

export const dynamic = "force-dynamic";
export const metadata = { title: "Studio admin" };

type Cal = {
  booking_id: string; reference: string; booking_status: string; payment_status: string; party_size: number;
  price_cents: number; starts_at: string; ends_at: string; service_name: string; client_name: string;
  client_email: string; client_phone: string | null;
};
type Pay = { id: string; amount_cents: number; kind: string; method: string; provider: string | null; note: string | null; paid_at: string };

const STATUS: Record<string, string> = {
  confirmed: "bg-success/15 text-success",
  pending: "bg-warning/15 text-warning",
  cancelled: "bg-danger/10 text-danger",
  completed: "bg-sand text-muted",
};

export default async function AdminHome() {
  const { supabase, user } = await requireAdmin();
  const s = await getSettings();
  const now = new Date();
  const in14 = new Date(now.getTime() + 14 * 86400_000);

  const [{ data: upcoming }, { data: recent }, { data: payments }, { count: clients }, { data: emails }] = await Promise.all([
    supabase.from("admin_calendar").select("*").gte("starts_at", now.toISOString()).lte("starts_at", in14.toISOString())
      .in("booking_status", ["confirmed", "pending"]).order("starts_at").limit(200),
    supabase.from("bookings").select("reference, status, created_at, clients(full_name), sessions(starts_at, services(name))")
      .order("created_at", { ascending: false }).limit(8),
    supabase.from("payments").select("id, amount_cents, kind, method, provider, note, paid_at").order("paid_at", { ascending: false }).limit(10),
    supabase.from("clients").select("id", { count: "exact", head: true }),
    supabase.from("notifications").select("status").gte("created_at", new Date(now.getTime() - 7 * 86400_000).toISOString()),
  ]);

  const list = (upcoming ?? []) as Cal[];
  const today = dateKey(now, s.timezone);
  const todays = list.filter((b) => dateKey(b.starts_at, s.timezone) === today);
  const revenue = ((payments ?? []) as Pay[]).reduce((n, p) => n + (p.kind === "refund" ? -p.amount_cents : p.amount_cents), 0);
  const emailStats = ((emails ?? []) as { status: string }[]).reduce<Record<string, number>>((m, e) => ((m[e.status] = (m[e.status] ?? 0) + 1), m), {});
  const byDay = new Map<string, Cal[]>();
  for (const b of list) {
    const k = dateKey(b.starts_at, s.timezone);
    byDay.set(k, [...(byDay.get(k) ?? []), b]);
  }

  return (
    <main className="mx-auto max-w-5xl px-5 py-8 pb-[max(2rem,env(safe-area-inset-bottom))]">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-xs uppercase tracking-[0.2em] text-clay">Studio admin</p>
          <h1 className="font-serif text-4xl">{s.studio_name}</h1>
          <p className="mt-1 text-sm text-muted">{user.email}</p>
        </div>
        <div className="flex gap-2">
          <Link href="/" className="rounded-full border border-sand px-4 py-2.5 text-sm">View site</Link>
          <form action={signOut}><button className="rounded-full border border-sand px-4 py-2.5 text-sm">Sign out</button></form>
        </div>
      </div>

      <dl className="mt-6 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="Today" value={String(todays.length)} />
        <Stat label="Next 14 days" value={String(list.length)} />
        <Stat label="Clients" value={String(clients ?? 0)} />
        <Stat label="Recent payments" value={formatPrice(revenue, s.currency)} />
      </dl>

      <section className="mt-6 rounded-[var(--radius-card)] bg-cream p-4 text-sm">
        <h2 className="font-medium">Emails (last 7 days)</h2>
        <p className="mt-1 text-muted">
          Sent {emailStats.sent ?? 0} · Waiting {emailStats.pending ?? 0} · Failed {emailStats.failed ?? 0}
          {(emailStats.pending ?? 0) > 0 && " — waiting emails go out once the email setup is complete."}
        </p>
      </section>

      <div className="mt-8 grid gap-8 lg:grid-cols-[2fr_1fr]">
        <section>
          <h2 className="font-serif text-2xl">Upcoming bookings</h2>
          {list.length === 0 && <p className="mt-3 text-muted">No bookings in the next 14 days.</p>}
          {[...byDay.entries()].map(([k, rows]) => (
            <div key={k} className="mt-5">
              <h3 className="text-sm font-medium text-muted">{formatDateLong(rows[0].starts_at, s.timezone)}</h3>
              <ul className="mt-2 space-y-2">
                {rows.map((b) => (
                  <li key={b.booking_id} className="rounded-2xl bg-white p-4 shadow-[0_8px_24px_-18px_rgba(47,42,36,.3)]">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="font-medium">{formatTime(b.starts_at, s.timezone)} · {b.service_name}</p>
                        <p className="text-sm">{b.client_name}{b.party_size > 1 ? ` (+${b.party_size - 1})` : ""}</p>
                        <p className="text-xs text-muted">
                          {b.client_email}{b.client_phone ? ` · ${b.client_phone}` : ""} · {b.reference}
                        </p>
                      </div>
                      <div className="flex shrink-0 flex-col items-end gap-1">
                        <span className={`rounded-full px-2.5 py-0.5 text-xs capitalize ${STATUS[b.booking_status] ?? "bg-sand"}`}>{b.booking_status}</span>
                        <span className="text-xs text-muted">{formatPrice(b.price_cents, s.currency)} · {b.payment_status}</span>
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </section>

        <aside className="space-y-8">
          <section>
            <h2 className="font-serif text-2xl">Latest activity</h2>
            <ul className="mt-3 space-y-2 text-sm">
              {((recent ?? []) as any[]).map((r) => (
                <li key={r.reference} className="rounded-xl bg-white px-4 py-3">
                  <p>{r.clients?.full_name ?? "Client"} · {r.sessions?.services?.name ?? "Session"}</p>
                  <p className="text-xs text-muted">
                    {r.reference} · <span className="capitalize">{r.status}</span> · booked{" "}
                    {new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: s.timezone }).format(new Date(r.created_at))}
                  </p>
                </li>
              ))}
            </ul>
          </section>
          <section>
            <h2 className="font-serif text-2xl">Payments</h2>
            <ul className="mt-3 space-y-2 text-sm">
              {((payments ?? []) as Pay[]).length === 0 && <li className="text-muted">No payments yet.</li>}
              {((payments ?? []) as Pay[]).map((p) => (
                <li key={p.id} className="flex items-center justify-between gap-3 rounded-xl bg-white px-4 py-3">
                  <span>
                    {p.kind === "refund" ? "Refund" : "Payment"}
                    {p.provider === "demo" && <span className="ml-2 rounded bg-warning/15 px-1.5 py-0.5 text-[11px] text-warning">DEMO</span>}
                    <span className="block text-xs text-muted">{p.note ?? p.method}</span>
                  </span>
                  <span className={p.kind === "refund" ? "text-danger" : ""}>{p.kind === "refund" ? "−" : ""}{formatPrice(p.amount_cents, s.currency)}</span>
                </li>
              ))}
            </ul>
          </section>
        </aside>
      </div>

      <p className="mt-10 text-xs text-muted">Timetable editor, calendar views, clients and settings are coming next.</p>
    </main>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl bg-white p-4 shadow-[0_8px_24px_-18px_rgba(47,42,36,.3)]">
      <dd className="font-serif text-2xl">{value}</dd>
      <dt className="text-xs text-muted">{label}</dt>
    </div>
  );
}
