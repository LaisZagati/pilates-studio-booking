import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getSettings } from "@/lib/studio";
import { formatDateLong, formatPrice, formatTime } from "@/lib/format";
import { CancelGuestBooking } from "@/components/booking/CancelGuestBooking";

export const dynamic = "force-dynamic";
export const metadata = { title: "Manage booking", robots: { index: false, follow: false } };

type Row = {
  reference: string; status: string; service_name: string; starts_at: string; ends_at: string;
  party_size: number; price_cents: number; client_name: string; can_cancel: boolean;
};

export default async function ManagePage({ searchParams }: { searchParams: Promise<{ ref?: string; token?: string }> }) {
  const { ref, token } = await searchParams;
  const s = await getSettings();

  let booking: Row | null = null;
  if (ref && token) {
    const supabase = await createClient();
    const { data } = await supabase.rpc("get_booking_by_token", { p_reference: ref, p_token: token });
    booking = ((data ?? []) as Row[])[0] ?? null;
  }

  return (
    <main className="mx-auto max-w-xl px-5 py-10">
      <h1 className="font-serif text-4xl">Manage your booking</h1>

      {!ref || !token ? (
        <div className="mt-6 space-y-4 text-muted">
          <p>Open the <strong className="text-ink">Manage booking</strong> link in your confirmation email to view or cancel a guest booking.</p>
          <p>Have an account? <Link href="/login?next=/account" className="text-clay underline">Sign in</Link> to see all your bookings.</p>
        </div>
      ) : !booking ? (
        <p role="alert" className="mt-6 rounded-xl bg-danger/10 px-4 py-3 text-danger">
          We couldn't find that booking. Please use the link from your confirmation email, or contact the studio.
        </p>
      ) : (
        <>
          <dl className="mt-6 divide-y divide-sand rounded-[var(--radius-card)] bg-white px-5 text-sm">
            <div className="flex justify-between py-3"><dt className="text-muted">Reference</dt><dd className="font-mono">{booking.reference}</dd></div>
            <div className="flex justify-between py-3"><dt className="text-muted">Session</dt><dd>{booking.service_name}</dd></div>
            <div className="flex justify-between py-3"><dt className="text-muted">Date</dt><dd>{formatDateLong(booking.starts_at, s.timezone)}</dd></div>
            <div className="flex justify-between py-3"><dt className="text-muted">Time</dt><dd>{formatTime(booking.starts_at, s.timezone)} – {formatTime(booking.ends_at, s.timezone)}</dd></div>
            {booking.party_size > 1 && <div className="flex justify-between py-3"><dt className="text-muted">People</dt><dd>{booking.party_size}</dd></div>}
            <div className="flex justify-between py-3"><dt className="text-muted">Price</dt><dd>{formatPrice(booking.price_cents, s.currency)}</dd></div>
            <div className="flex justify-between py-3"><dt className="text-muted">Status</dt><dd className="capitalize">{booking.status}</dd></div>
          </dl>
          {booking.status === "pending" && (
            <Link href={`/pay/${booking.reference}?t=${token}`} className="mt-6 block rounded-full bg-ink px-6 py-4 text-center text-ivory">
              Awaiting payment · Pay now
            </Link>
          )}
          {booking.can_cancel ? (
            <CancelGuestBooking reference={booking.reference} token={token} />
          ) : (
            ["pending", "confirmed"].includes(booking.status) && (
              <p className="mt-6 text-sm text-muted">
                Online cancellation closes {s.cancellation_window_hours} hours before the session. Please contact the studio
                {s.contact_phone ? ` on ${s.contact_phone}` : ""}.
              </p>
            )
          )}
        </>
      )}
    </main>
  );
}
