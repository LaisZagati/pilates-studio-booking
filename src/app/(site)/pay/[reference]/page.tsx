import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getSettings } from "@/lib/studio";
import { formatDateLong, formatTime } from "@/lib/format";
import { DemoPayment } from "@/components/pay/DemoPayment";

export const dynamic = "force-dynamic";
export const metadata = { title: "Payment", robots: { index: false, follow: false } };

type Row = {
  reference: string; status: string; payment_status: string; service_name: string; starts_at: string; ends_at: string;
  party_size: number; price_cents: number; hold_expires_at: string | null; paid_with: string | null; payment_mode: string;
};

export default async function PayPage({
  params,
  searchParams,
}: {
  params: Promise<{ reference: string }>;
  searchParams: Promise<{ t?: string }>;
}) {
  const [{ reference }, { t }, s] = await Promise.all([params, searchParams, getSettings()]);
  const supabase = await createClient();
  const [{ data }, { data: { user } }] = await Promise.all([
    supabase.rpc("get_payment_details", { p_reference: reference, p_token: t ?? null }),
    supabase.auth.getUser(),
  ]);
  const b = ((data ?? []) as Row[])[0];

  return (
    <main className="mx-auto max-w-xl px-5 py-8 md:py-12">
      <h1 className="font-serif text-4xl">Complete your booking</h1>
      {!b ? (
        <div className="mt-6 space-y-4">
          <p role="alert" className="rounded-xl bg-danger/10 px-4 py-3 text-danger">We couldn&apos;t find this booking. Use the link from your email, or sign in.</p>
          <Link href="/login?next=/account" className="inline-block rounded-full border border-sand px-5 py-3">Sign in</Link>
        </div>
      ) : (
        <>
          <dl className="mt-6 divide-y divide-sand rounded-[var(--radius-card)] bg-white px-5 text-sm">
            <div className="flex justify-between py-3"><dt className="text-muted">Session</dt><dd>{b.service_name}</dd></div>
            <div className="flex justify-between py-3"><dt className="text-muted">Date</dt><dd>{formatDateLong(b.starts_at, s.timezone)}</dd></div>
            <div className="flex justify-between py-3"><dt className="text-muted">Time</dt><dd>{formatTime(b.starts_at, s.timezone)} – {formatTime(b.ends_at, s.timezone)}</dd></div>
            {b.party_size > 1 && <div className="flex justify-between py-3"><dt className="text-muted">People</dt><dd>{b.party_size}</dd></div>}
            <div className="flex justify-between py-3"><dt className="text-muted">Reference</dt><dd className="font-mono">{b.reference}</dd></div>
          </dl>

          <div className="mt-6">
            {b.status === "confirmed" && b.payment_status === "paid" ? (
              <div className="rounded-xl bg-success/10 px-4 py-3 text-success">This booking is paid and confirmed.</div>
            ) : b.status !== "pending" ? (
              <div className="space-y-4">
                <p className="rounded-xl bg-danger/10 px-4 py-3 text-danger">This booking is no longer waiting for payment (status: {b.status}).</p>
                <Link href="/book" className="inline-block rounded-full bg-ink px-6 py-3 text-ivory">Book again</Link>
              </div>
            ) : b.payment_mode === "demo" ? (
              <DemoPayment
                reference={b.reference}
                token={t}
                amountCents={b.price_cents}
                currency={s.currency}
                holdExpiresAt={b.hold_expires_at}
                signedIn={!!user}
              />
            ) : (
              <p className="rounded-xl bg-cream px-4 py-3 text-muted">Online payment is being set up. Please contact the studio to pay.</p>
            )}
          </div>
        </>
      )}
    </main>
  );
}
