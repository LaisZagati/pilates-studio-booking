import "server-only";
import { createServiceClient } from "@/lib/supabase/service";
import { renderEmail, type EmailData } from "@/lib/email/templates";

/**
 * Sends due emails from the `notifications` outbox through Resend.
 * Needs SUPABASE_SERVICE_ROLE_KEY and RESEND_API_KEY on the server; without
 * them it does nothing (the emails simply wait in the outbox).
 */
export async function runNotificationQueue(limit = 20) {
  const resendKey = process.env.RESEND_API_KEY;
  if (!resendKey || !process.env.SUPABASE_SERVICE_ROLE_KEY) return { sent: 0, failed: 0, skipped: 0, configured: false };

  const db = createServiceClient();
  const [{ data: st }, { data: due }] = await Promise.all([
    db.from("business_settings").select("studio_name, timezone, currency, cancellation_window_hours, address").maybeSingle(),
    db.from("notifications")
      .select("id, type, recipient_email, attempts, bookings(reference, status, party_size, price_cents, paid_with, hold_expires_at, sessions(starts_at, ends_at, services(name)), clients(full_name, email, phone))")
      .eq("status", "pending")
      .lte("scheduled_for", new Date().toISOString())
      .lt("attempts", 5)
      .order("scheduled_for")
      .limit(limit),
  ]);
  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "";
  const from = process.env.EMAIL_FROM ?? "Pilates Studio <onboarding@resend.dev>";
  let sent = 0, failed = 0, skipped = 0;

  for (const n of (due ?? []) as any[]) {
    const bk = n.bookings;
    // a reminder or offer for a booking that is no longer active is not sent
    if (bk && ["booking_reminder", "waitlist_offer"].includes(n.type) && !["confirmed", "pending"].includes(bk.status)) {
      await db.from("notifications").update({ status: "skipped" }).eq("id", n.id);
      skipped++;
      continue;
    }
    const data: EmailData = {
      type: n.type,
      studioName: st?.studio_name ?? "Pilates Studio",
      appUrl,
      timeZone: st?.timezone ?? "Europe/Madrid",
      currency: st?.currency ?? "EUR",
      cancellationHours: st?.cancellation_window_hours ?? 24,
      address: st?.address ?? null,
      booking: bk
        ? {
            reference: bk.reference,
            serviceName: bk.sessions?.services?.name ?? "Session",
            startsAt: bk.sessions?.starts_at,
            endsAt: bk.sessions?.ends_at,
            partySize: bk.party_size,
            priceCents: bk.price_cents,
            clientName: bk.clients?.full_name ?? "",
            clientEmail: bk.clients?.email ?? "",
            clientPhone: bk.clients?.phone ?? null,
            paidWith: bk.paid_with,
            holdExpiresAt: bk.hold_expires_at,
          }
        : null,
    };
    const email = renderEmail(data);
    if (!email) {
      await db.from("notifications").update({ status: "skipped" }).eq("id", n.id);
      skipped++;
      continue;
    }
    try {
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from, to: [n.recipient_email], subject: email.subject, html: email.html }),
      });
      if (res.ok) {
        await db.from("notifications").update({ status: "sent", sent_at: new Date().toISOString(), attempts: n.attempts + 1 }).eq("id", n.id);
        sent++;
      } else {
        const err = (await res.text()).slice(0, 500);
        // 4xx (e.g. sender domain not verified yet) won't fix itself on retry
        await db.from("notifications").update({ status: res.status < 500 ? "failed" : "pending", attempts: n.attempts + 1, last_error: err }).eq("id", n.id);
        failed++;
      }
    } catch (e) {
      await db.from("notifications").update({ attempts: n.attempts + 1, last_error: String(e).slice(0, 500) }).eq("id", n.id);
      failed++;
    }
  }
  return { sent, failed, skipped, configured: true };
}
