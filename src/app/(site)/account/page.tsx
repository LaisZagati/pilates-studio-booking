import Link from "next/link";
import { requireUser } from "@/lib/auth";
import { signOut } from "@/app/auth/actions";
import { getSettings } from "@/lib/studio";
import { BookingCard, type AccountBooking } from "@/components/account/BookingCard";
import { ProfileForm } from "@/components/account/ProfileForm";

export const dynamic = "force-dynamic";
export const metadata = { title: "My account" };

type Row = {
  id: string; reference: string; status: string; payment_status: string; party_size: number; price_cents: number;
  sessions: { starts_at: string; ends_at: string; services: { name: string } | null } | null;
  reschedule_requests: { status: string }[] | null;
};

export default async function AccountPage({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const { tab = "upcoming" } = await searchParams;
  const { supabase, user } = await requireUser();
  await supabase.rpc("link_my_client");

  const [s, { data: client }, { data: rows }, { data: isAdmin }] = await Promise.all([
    getSettings(),
    supabase.from("clients").select("full_name, phone, created_at").maybeSingle(),
    supabase
      .from("bookings")
      .select("id, reference, status, payment_status, party_size, price_cents, sessions(starts_at, ends_at, services(name)), reschedule_requests(status)")
      .limit(200),
    supabase.rpc("is_admin"),
  ]);

  const now = Date.now();
  const bookings: AccountBooking[] = ((rows ?? []) as unknown as Row[])
    .filter((r) => r.sessions)
    .map((r) => ({
      id: r.id,
      reference: r.reference,
      status: r.status,
      payment_status: r.payment_status,
      party_size: r.party_size,
      price_cents: r.price_cents,
      starts_at: r.sessions!.starts_at,
      ends_at: r.sessions!.ends_at,
      service_name: r.sessions!.services?.name ?? "Session",
      has_open_request: (r.reschedule_requests ?? []).some((q) => q.status === "open"),
    }));

  const upcoming = bookings
    .filter((b) => new Date(b.ends_at).getTime() > now && ["pending", "confirmed"].includes(b.status))
    .sort((a, b) => a.starts_at.localeCompare(b.starts_at));
  const past = bookings
    .filter((b) => !upcoming.includes(b))
    .sort((a, b) => b.starts_at.localeCompare(a.starts_at));
  const visits = bookings.filter((b) => b.status === "completed" || (b.status === "confirmed" && new Date(b.ends_at).getTime() <= now)).length;
  const cutoff = s.cancellation_window_hours * 3600_000;

  const list = tab === "past" ? past : tab === "details" ? [] : upcoming;
  const firstName = (client?.full_name ?? "").split(" ")[0];

  return (
    <main className="mx-auto max-w-2xl px-5 py-8 md:py-12">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="font-serif text-4xl md:text-5xl">{firstName ? `Hello, ${firstName}` : "My account"}</h1>
          <p className="mt-1 text-muted">{user.email}</p>
        </div>
        {isAdmin && (
          <Link href="/admin" className="shrink-0 rounded-full bg-clay px-4 py-2.5 text-sm text-ivory">Studio admin</Link>
        )}
      </div>

      <dl className="mt-6 grid grid-cols-3 gap-3">
        <Stat label="Upcoming" value={String(upcoming.length)} />
        <Stat label="Visits" value={String(visits)} />
        <Stat label="Member since" value={client?.created_at ? new Intl.DateTimeFormat("en-GB", { month: "short", year: "numeric", timeZone: s.timezone }).format(new Date(client.created_at)) : "—"} />
      </dl>

      <nav aria-label="Account sections" className="mt-8 flex gap-1 rounded-full bg-cream p-1 text-sm">
        {[["upcoming", `Upcoming (${upcoming.length})`], ["past", "History"], ["details", "My details"]].map(([id, label]) => (
          <Link
            key={id}
            href={`/account?tab=${id}`}
            aria-current={tab === id ? "page" : undefined}
            className={`flex-1 rounded-full px-3 py-2.5 text-center ${tab === id ? "bg-white shadow-sm" : "text-muted"}`}
          >
            {label}
          </Link>
        ))}
      </nav>

      <section className="mt-6">
        {tab === "details" ? (
          <ProfileForm fullName={client?.full_name ?? ""} phone={client?.phone ?? ""} email={user.email ?? ""} />
        ) : list.length === 0 ? (
          <div className="rounded-[var(--radius-card)] bg-cream p-6 text-center">
            <p className="text-muted">{tab === "past" ? "No past bookings yet." : "You have no upcoming sessions."}</p>
            <Link href="/book" className="mt-4 inline-block rounded-full bg-ink px-6 py-3 text-ivory">Book a session</Link>
          </div>
        ) : (
          <ul className="space-y-4">
            {list.map((b) => (
              <BookingCard
                key={b.id}
                b={b}
                timeZone={s.timezone}
                currency={s.currency}
                address={s.address}
                upcoming={tab !== "past"}
                canCancel={new Date(b.starts_at).getTime() - now > cutoff}
              />
            ))}
          </ul>
        )}
      </section>

      {tab !== "details" && s.cancellation_policy && (
        <p className="mt-6 text-xs text-muted">{s.cancellation_policy}</p>
      )}

      <form action={signOut} className="mt-10 border-t border-sand pt-6">
        <button className="rounded-full border border-sand px-5 py-3 text-sm">Sign out</button>
      </form>
    </main>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl bg-white p-4 text-center shadow-[0_8px_24px_-18px_rgba(47,42,36,.3)]">
      <dd className="font-serif text-2xl">{value}</dd>
      <dt className="mt-0.5 text-xs text-muted">{label}</dt>
    </div>
  );
}
