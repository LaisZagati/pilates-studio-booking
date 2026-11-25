"use client";
import { useState, useTransition } from "react";
import Link from "next/link";
import { demoBuyPack } from "@/app/(site)/pay/actions";
import { formatPrice } from "@/lib/format";

export function BuyPackButton({ packageId, priceCents, currency, signedIn }: { packageId: string; priceCents: number; currency: string; signedIn: boolean }) {
  const [pending, start] = useTransition();
  const [confirming, setConfirming] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; message: string } | null>(null);

  if (!signedIn) {
    return (
      <Link href="/login?next=/packs" className="block rounded-full bg-ink px-5 py-3 text-center text-ivory">
        Sign in to buy
      </Link>
    );
  }
  if (result?.ok) {
    return (
      <div className="space-y-2">
        <p role="status" className="text-sm text-success">{result.message}</p>
        <Link href="/book" className="block rounded-full bg-ink px-5 py-3 text-center text-ivory">Book a class</Link>
      </div>
    );
  }
  return (
    <div>
      {result && !result.ok && <p role="alert" className="mb-2 text-sm text-danger">{result.message}</p>}
      {!confirming ? (
        <button type="button" onClick={() => setConfirming(true)} className="w-full rounded-full bg-ink px-5 py-3 text-ivory">
          Buy · {formatPrice(priceCents, currency)}
        </button>
      ) : (
        <div className="rounded-xl border border-warning/40 bg-warning/10 p-3 text-sm">
          <p className="text-warning"><strong>Demo payment</strong> — no money is taken.</p>
          <div className="mt-3 flex gap-2">
            <button type="button" onClick={() => setConfirming(false)} className="flex-1 rounded-full border border-sand bg-white px-4 py-2.5">Cancel</button>
            <button
              type="button"
              disabled={pending}
              onClick={() => start(async () => setResult(await demoBuyPack(packageId)))}
              className="flex-1 rounded-full bg-ink px-4 py-2.5 text-ivory disabled:opacity-50"
            >
              {pending ? "Processing…" : `Pay ${formatPrice(priceCents, currency)}`}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
