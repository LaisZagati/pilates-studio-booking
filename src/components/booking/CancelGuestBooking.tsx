"use client";
import { useActionState, useState } from "react";
import { cancelGuestBooking } from "@/app/(site)/manage/actions";

export function CancelGuestBooking({ reference, token }: { reference: string; token: string }) {
  const [state, action, pending] = useActionState(cancelGuestBooking, {});
  const [confirming, setConfirming] = useState(false);

  if (state.done) {
    return <p role="status" className="mt-6 rounded-xl bg-success/10 px-4 py-3 text-success">Your booking has been cancelled. A confirmation email is on its way.</p>;
  }
  return (
    <form action={action} className="mt-6">
      <input type="hidden" name="reference" value={reference} />
      <input type="hidden" name="token" value={token} />
      {state.error && <p role="alert" className="mb-3 rounded-xl bg-danger/10 px-4 py-3 text-sm text-danger">{state.error}</p>}
      {!confirming ? (
        <button type="button" onClick={() => setConfirming(true)} className="w-full rounded-full border border-danger/40 px-6 py-4 text-danger">
          Cancel booking
        </button>
      ) : (
        <div className="rounded-[var(--radius-card)] border border-danger/30 p-4">
          <p className="text-sm">Cancel this booking? This can't be undone.</p>
          <div className="mt-3 flex gap-2">
            <button type="button" onClick={() => setConfirming(false)} className="flex-1 rounded-full border border-sand px-4 py-3">Keep it</button>
            <button type="submit" disabled={pending} className="flex-1 rounded-full bg-danger px-4 py-3 text-ivory disabled:opacity-50">
              {pending ? "Cancelling…" : "Yes, cancel"}
            </button>
          </div>
        </div>
      )}
    </form>
  );
}
