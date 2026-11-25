import { formatDateLong, formatPrice, formatTime } from "@/lib/format";

export type EmailData = {
  type: string;
  studioName: string;
  appUrl: string;
  timeZone: string;
  currency: string;
  cancellationHours: number;
  address: string | null;
  booking: null | {
    reference: string;
    serviceName: string;
    startsAt: string;
    endsAt: string;
    partySize: number;
    priceCents: number;
    clientName: string;
    clientEmail: string;
    clientPhone: string | null;
    paidWith: string | null;
    holdExpiresAt: string | null;
  };
};

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

function layout(studio: string, title: string, body: string, cta?: { label: string; href: string }) {
  return `<!doctype html><html><body style="margin:0;background:#fbf8f2;font-family:Georgia,'Times New Roman',serif;color:#2f2a24">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#fbf8f2;padding:32px 16px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:20px;padding:32px">
<tr><td style="font-size:22px;letter-spacing:.5px;padding-bottom:20px;border-bottom:1px solid #e7dccb">${esc(studio)}</td></tr>
<tr><td style="padding-top:24px;font-size:28px;line-height:1.2">${esc(title)}</td></tr>
<tr><td style="padding-top:16px;font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#4a443c">${body}</td></tr>
${cta ? `<tr><td style="padding-top:24px"><a href="${esc(cta.href)}" style="display:inline-block;background:#2f2a24;color:#fbf8f2;text-decoration:none;border-radius:999px;padding:14px 28px;font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:15px">${esc(cta.label)}</a></td></tr>` : ""}
</table>
<p style="font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:#8c7f70;margin-top:16px">${esc(studio)}</p>
</td></tr></table></body></html>`;
}

function details(d: EmailData) {
  const b = d.booking!;
  const rows: [string, string][] = [
    ["Session", b.serviceName],
    ["Date", formatDateLong(b.startsAt, d.timeZone)],
    ["Time", `${formatTime(b.startsAt, d.timeZone)} – ${formatTime(b.endsAt, d.timeZone)}`],
    ...(b.partySize > 1 ? [["People", String(b.partySize)] as [string, string]] : []),
    ["Reference", b.reference],
    ...(d.address ? [["Where", d.address] as [string, string]] : []),
  ];
  return `<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;margin-top:8px;border-top:1px solid #efe6d8">${rows
    .map(([k, v]) => `<tr><td style="padding:8px 0;color:#8c7f70;width:110px;border-bottom:1px solid #efe6d8">${esc(k)}</td><td style="padding:8px 0;border-bottom:1px solid #efe6d8">${esc(v)}</td></tr>`)
    .join("")}</table>`;
}

/** Returns subject + html for a queued notification, or null if it should be skipped. */
export function renderEmail(d: EmailData): { subject: string; html: string } | null {
  const b = d.booking;
  const account = `${d.appUrl}/account`;
  switch (d.type) {
    case "booking_confirmed":
      if (!b) return null;
      return {
        subject: `Booking confirmed: ${b.serviceName}, ${formatDateLong(b.startsAt, d.timeZone)}`,
        html: layout(d.studioName, "You're booked", `<p>Hi ${esc(b.clientName.split(" ")[0])}, we can't wait to see you.</p>${details(d)}
<p style="margin-top:16px">Free cancellation up to ${d.cancellationHours} hours before your session.</p>`, { label: "View my bookings", href: account }),
      };
    case "booking_reminder":
      if (!b) return null;
      return {
        subject: `Reminder: ${b.serviceName} ${formatDateLong(b.startsAt, d.timeZone)} at ${formatTime(b.startsAt, d.timeZone)}`,
        html: layout(d.studioName, "See you soon", `<p>A quick reminder of your upcoming session.</p>${details(d)}
<p style="margin-top:16px">Please arrive 5 minutes early. Grip socks are required on the reformer.</p>`, { label: "View my bookings", href: account }),
      };
    case "booking_cancelled":
      if (!b) return null;
      return {
        subject: `Booking cancelled: ${b.serviceName}, ${formatDateLong(b.startsAt, d.timeZone)}`,
        html: layout(d.studioName, "Booking cancelled", `<p>This booking has been cancelled.</p>${details(d)}
<p style="margin-top:16px">${b.paidWith === "credit" ? "Your class credit has been returned to your account." : "If you paid online, any refund due is processed automatically."}</p>`, { label: "Book another session", href: `${d.appUrl}/book` }),
      };
    case "booking_rescheduled":
      if (!b) return null;
      return {
        subject: `New time: ${b.serviceName}, ${formatDateLong(b.startsAt, d.timeZone)}`,
        html: layout(d.studioName, "Your booking has moved", `<p>Your session now takes place at the time below.</p>${details(d)}`, { label: "View my bookings", href: account }),
      };
    case "waitlist_booked":
      if (!b) return null;
      return {
        subject: `A place opened up — you're booked for ${b.serviceName}`,
        html: layout(d.studioName, "Good news — you're in", `<p>A place opened up and we've booked it for you using one of your credits.</p>${details(d)}`, { label: "View my bookings", href: account }),
      };
    case "waitlist_offer":
      if (!b) return null;
      return {
        subject: `A place is free in ${b.serviceName} — confirm it now`,
        html: layout(d.studioName, "A place is waiting for you", `<p>Someone cancelled and the place is held for you${b.holdExpiresAt ? ` until ${formatTime(b.holdExpiresAt, d.timeZone)}` : ""}. Pay to confirm it.</p>${details(d)}`, { label: "Confirm my place", href: `${d.appUrl}/pay/${b.reference}` }),
      };
    case "owner_new_booking":
      if (!b) return null;
      return {
        subject: `New booking: ${b.clientName} — ${b.serviceName} ${formatDateLong(b.startsAt, d.timeZone)} ${formatTime(b.startsAt, d.timeZone)}`,
        html: layout(d.studioName, "New booking", `<p><strong>${esc(b.clientName)}</strong> · ${esc(b.clientEmail)}${b.clientPhone ? ` · ${esc(b.clientPhone)}` : ""}</p>${details(d)}
<p style="margin-top:16px">${formatPrice(b.priceCents, d.currency)} · ${esc(b.paidWith === "credit" ? "paid with a credit" : b.paidWith === "card" ? "paid online" : "pay at the studio")}</p>`, { label: "Open studio admin", href: `${d.appUrl}/admin` }),
      };
    case "credits_added":
      return {
        subject: `Your classes have been added`,
        html: layout(d.studioName, "Your credits are ready", `<p>Thank you! Your new credits are in your account and ready to book.</p>`, { label: "Book a session", href: `${d.appUrl}/book` }),
      };
    default:
      return null;
  }
}
