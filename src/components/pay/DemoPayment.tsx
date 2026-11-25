"use client";
import { useEffect, useState, useTransition } from "react";
import Link from "next/link";
import { demoPay } from "@/app/(site)/pay/actions";
import { formatPrice } from "@/lib/format";
import { CheckIcon } from "@/components/icons";

/**
 * DEMO checkout. It never asks for card details and never moves money.
 * When Stripe is connected this screen is replaced by Stripe's own secure page.
 */
export function DemoPayment({
  reference,
  token,
  amountCents,
  currency,
  holdExpiresAt,
  signedIn,
}: {
  reference: string;
  token?: string;
  amountCents: number;
  currency: string;
  holdExpiresAt: string | null;
  signedIn: boolean;
}) {
  const [pending, start] = useTransition();
  const [state, setState] = useState<"idle" | "confirmed" | "declined" | "error">("idle");
  const [message, setMessage] = useState<string | null>(null);
  const [left, setLeft] = useState<number | null>(null);

  useEffect(() => {
    if (!holdExpiresAt) return;
    const tick = () => setLeft(Math.max(0, Math.floor((new Date(holdExpiresAt).getTime() - Date.now()) / 1000)));
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [holdExpiresAt]);

  const pay = (succeed: boolean) =>
    start(async () => {
      const r = await demoPay(reference, token, succeed);
      setState(r.status);
      setMessage(r.message ?? null);
    });

  if (state === "confirmed") {
    return (
      <div className="text-center">
        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-success/15 text-success">
          <CheckIcon className="h-8 w-8" />
        </div>
        <h2 className="mt-5 font-serif text-4xl">You&apos;re booked!</h2>
        <p className="mt-2 text-muted">Payment received (demo). A confirmation email is on its way.</p>
        <p className="mt-6 text-sm text-muted">Booking reference</p>
        <p className="font-mono text-3xl tracking-widest">{reference}</p>
        <div className="mt-8 flex flex-col gap-3">
          {signedIn ? (
            <Link href="/account" className="rounded-full bg-ink px-6 py-4 text-ivory">View my bookings</Link>
          ) : (
            token && <Link href={`/manage?ref=${reference}&token=${token}`} className="rounded-full bg-ink px-6 py-4 text-ivory">Manage this booking</Link>
          )}
          <Link href="/book" className="rounded-full border border-taupe px-6 py-4">Book another session</Link>
        </div>
      </div>
    );
  }

  const expired = left === 0;
  const mins = left !== null ? Math.floor(left / 60) : null;
  const secs = left !== null ? String(left % 60).padStart(2, "0") : null;

  return (
    <div>
      <div role="note" className="rounded-xl border border-warning/40 bg-warning/10 px-4 py-3 text-sm text-warning">
        <strong>Demo payment.</strong> No card details are needed and no money is taken. Real card payments will run through Stripe once it&apos;s connected.
      </div>

      {left !== null && (
        <p className={`mt-4 text-sm ${expired ? "text-danger" : "text-muted"}`}>
          {expired ? "Your hold has ended — if the place is still free you can still pay." : `Your place is held for ${mins}:${secs}.`}
        </p>
      )}

      <div className="mt-6 rounded-[var(--radius-card)] border border-sand bg-white p-5">
        <div className="flex items-center justify-between">
          <span className="text-muted">Total</span>
          <span className="font-serif text-3xl">{formatPrice(amountCents, currency)}</span>
        </div>
        <div className="mt-4 flex items-center gap-3 rounded-xl bg-cream px-4 py-3 text-sm">
          <span className="rounded bg-ink px-2 py-0.5 font-mono text-[11px] text-ivory">DEMO</span>
          <span>Demo card •••• 4242</span>
        </div>
      </div>

      {(state === "declined" || state === "error") && message && (
        <p role="alert" className="mt-4 rounded-xl bg-danger/10 px-4 py-3 text-sm text-danger">{message}</p>
      )}

      <button
        type="button"
        disabled={pending}
        onClick={() => pay(true)}
        className="mt-6 w-full rounded-full bg-ink px-6 py-4 font-medium text-ivory transition active:scale-[0.99] disabled:opacity-50"
      >
        {pending ? "Processing…" : `Pay ${formatPrice(amountCents, currency)} (demo)`}
      </button>
      <button
        type="button"
        disabled={pending}
        onClick={() => pay(false)}
        className="mt-3 w-full rounded-full border border-sand px-6 py-3 text-sm text-muted disabled:opacity-50"
      >
        Simulate a declined card
      </button>
    </div>
  );
}
