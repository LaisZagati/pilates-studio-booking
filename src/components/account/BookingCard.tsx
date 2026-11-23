"use client";
import { useActionState, useState } from "react";
import { cancelMyBooking, requestChange } from "@/app/(site)/account/actions";
import { formatDateLong, formatPrice, formatTime } from "@/lib/format";
import { icsHref } from "@/lib/ics";
import { ClockIcon, PeopleIcon } from "@/components/icons";

export type AccountBooking = {
  id: string;
  reference: string;
  status: string;
  payment_status: string;
  party_size: number;
  price_cents: number;
  starts_at: string;
  ends_at: string;
  service_name: string;
  has_open_request: boolean;
};

const STATUS_STYLE: Record<string, string> = {
  confirmed: "bg-success/15 text-success",
  pending: "bg-warning/15 text-warning",
  cancelled: "bg-danger/10 text-danger",
  completed: "bg-sand text-muted",
  no_show: "bg-sand text-muted",
};
const PAY_LABEL: Record<string, string> = {
  paid: "Paid",
  partial: "Partly paid",
  unpaid: "Pay at the studio",
  refunded: "Refunded",
};

export function BookingCard({
  b,
  timeZone,
  currency,
  address,
  canCancel,
  upcoming,
}: {
  b: AccountBooking;
  timeZone: string;
  currency: string;
  address: string | null;
  canCancel: boolean;
  upcoming: boolean;
}) {
  const [panel, setPanel] = useState<"none" | "cancel" | "change">("none");
  const [cancelState, cancelAction, cancelling] = useActionState(cancelMyBooking, {});
  const [changeState, changeAction, sending] = useActionState(requestChange, {});

  return (
    <li className="rounded-[var(--radius-card)] bg-white p-5 shadow-[0_8px_24px_-16px_rgba(47,42,36,.25)]">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="font-serif text-2xl leading-tight">{b.service_name}</h3>
          <p className="mt-1 text-sm">{formatDateLong(b.starts_at, timeZone)}</p>
        </div>
        <span className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium capitalize ${STATUS_STYLE[b.status] ?? "bg-sand"}`}>
          {b.status.replace("_", " ")}
        </span>
      </div>

      <ul className="mt-3 flex flex-wrap gap-x-5 gap-y-1 text-sm text-muted">
        <li className="flex items-center gap-1.5"><ClockIcon className="h-4 w-4" />{formatTime(b.starts_at, timeZone)} – {formatTime(b.ends_at, timeZone)}</li>
        <li className="flex items-center gap-1.5"><PeopleIcon className="h-4 w-4" />{b.party_size} {b.party_size === 1 ? "person" : "people"}</li>
      </ul>

      <dl className="mt-4 grid grid-cols-3 gap-3 border-t border-sand pt-4 text-sm">
        <div><dt className="text-xs text-muted">Reference</dt><dd className="font-mono">{b.reference}</dd></div>
        <div><dt className="text-xs text-muted">Price</dt><dd>{formatPrice(b.price_cents, currency)}</dd></div>
        <div><dt className="text-xs text-muted">Payment</dt><dd>{PAY_LABEL[b.payment_status] ?? b.payment_status}</dd></div>
      </dl>

      {b.has_open_request && upcoming && (
        <p className="mt-3 rounded-xl bg-cream px-3 py-2 text-sm text-muted">Change requested — the studio will get back to you.</p>
      )}
      {cancelState.message && <p role="status" className="mt-3 text-sm text-success">{cancelState.message}</p>}
      {changeState.message && <p role="status" className="mt-3 text-sm text-success">{changeState.message}</p>}

      {upcoming && ["pending", "confirmed"].includes(b.status) && !cancelState.message && (
        <>
          <div className="mt-4 flex flex-wrap gap-2">
            <a
              href={icsHref(b.service_name, b.starts_at, b.ends_at, address)}
              download={`booking-${b.reference}.ics`}
              className="rounded-full border border-sand px-4 py-2.5 text-sm"
            >
              Add to calendar
            </a>
            {!b.has_open_request && !changeState.message && (
              <button type="button" onClick={() => setPanel(panel === "change" ? "none" : "change")} className="rounded-full border border-sand px-4 py-2.5 text-sm">
                Request a change
              </button>
            )}
            {canCancel && (
              <button type="button" onClick={() => setPanel(panel === "cancel" ? "none" : "cancel")} className="rounded-full border border-danger/30 px-4 py-2.5 text-sm text-danger">
                Cancel
              </button>
            )}
          </div>

          {panel === "cancel" && (
            <form action={cancelAction} className="mt-4 rounded-xl border border-danger/30 p-4">
              <input type="hidden" name="bookingId" value={b.id} />
              <p className="text-sm">Cancel this booking? This can&apos;t be undone.</p>
              {cancelState.error && <p role="alert" className="mt-2 text-sm text-danger">{cancelState.error}</p>}
              <div className="mt-3 flex gap-2">
                <button type="button" onClick={() => setPanel("none")} className="flex-1 rounded-full border border-sand px-4 py-3">Keep it</button>
                <button type="submit" disabled={cancelling} className="flex-1 rounded-full bg-danger px-4 py-3 text-ivory disabled:opacity-50">
                  {cancelling ? "Cancelling…" : "Yes, cancel"}
                </button>
              </div>
            </form>
          )}

          {panel === "change" && !changeState.message && (
            <form action={changeAction} className="mt-4 rounded-xl border border-sand p-4">
              <input type="hidden" name="bookingId" value={b.id} />
              <label className="block text-sm">
                <span className="mb-1.5 block text-muted">Which day or time would suit you?</span>
                <textarea name="message" rows={3} maxLength={1000} required className="w-full rounded-xl border border-sand bg-white px-4 py-3 focus:border-clay focus:outline-none" />
              </label>
              {changeState.error && <p role="alert" className="mt-2 text-sm text-danger">{changeState.error}</p>}
              <button type="submit" disabled={sending} className="mt-3 w-full rounded-full bg-ink px-4 py-3 text-ivory disabled:opacity-50">
                {sending ? "Sending…" : "Send request"}
              </button>
            </form>
          )}

          {!canCancel && (
            <p className="mt-3 text-xs text-muted">Online cancellation has closed for this session. Please contact the studio.</p>
          )}
        </>
      )}
    </li>
  );
}
