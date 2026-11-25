import { createClient } from "@/lib/supabase/server";
import { getServices, getSettings } from "@/lib/studio";
import { formatPrice } from "@/lib/format";
import { BuyPackButton } from "@/components/pay/BuyPackButton";
import type { Pack } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Class packs & memberships" };

export default async function PacksPage() {
  const supabase = await createClient();
  const [s, services, { data }, { data: { user } }] = await Promise.all([
    getSettings(),
    getServices(),
    supabase.from("packages").select("id, name, description, kind, credits, price_cents, validity_days, service_ids, sort_order").eq("active", true).order("sort_order"),
    supabase.auth.getUser(),
  ]);
  const packs = (data ?? []) as Pack[];
  const serviceName = (ids: string[] | null) =>
    !ids || ids.length === 0 ? "Any class" : ids.map((id) => services.find((x) => x.id === id)?.name).filter(Boolean).join(", ");
  const single = (ids: string[] | null) => {
    const svc = ids?.length === 1 ? services.find((x) => x.id === ids[0]) : undefined;
    return svc?.price_cents ?? null;
  };

  return (
    <main className="mx-auto max-w-6xl px-5 py-10">
      <h1 className="font-serif text-5xl">Packs &amp; memberships</h1>
      <p className="mt-3 max-w-xl text-muted">Buy classes in advance, save on each session and book in one tap with your credits.</p>
      <div className="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
        {packs.map((p) => {
          const each = Math.round(p.price_cents / p.credits);
          const normal = single(p.service_ids);
          const saving = normal && normal > each ? Math.round((1 - each / normal) * 100) : 0;
          return (
            <article key={p.id} className="flex flex-col rounded-[var(--radius-card)] bg-white p-6 shadow-[0_8px_24px_-16px_rgba(47,42,36,.25)]">
              <p className="text-xs uppercase tracking-[0.2em] text-clay">{p.kind === "membership" ? "Membership" : "Class pack"}</p>
              <h2 className="mt-2 font-serif text-3xl leading-tight">{p.name}</h2>
              <p className="mt-2 text-sm text-muted">{p.description}</p>
              <ul className="mt-4 space-y-1 text-sm">
                <li>{p.credits} {p.credits === 1 ? "class" : "classes"}{p.kind === "membership" ? " per month" : ""}</li>
                <li className="text-muted">{serviceName(p.service_ids)}</li>
                <li className="text-muted">Valid {p.validity_days} days</li>
              </ul>
              <div className="mt-auto pt-6">
                <p className="font-serif text-3xl">{formatPrice(p.price_cents, s.currency)}</p>
                <p className="mb-4 text-sm text-muted">
                  {formatPrice(each, s.currency)} per class{saving > 0 ? ` · save ${saving}%` : ""}
                </p>
                <BuyPackButton packageId={p.id} priceCents={p.price_cents} currency={s.currency} signedIn={!!user} />
              </div>
            </article>
          );
        })}
      </div>
      {packs.length === 0 && <p className="mt-8 text-muted">No packs are available right now.</p>}
      <p className="mt-10 text-xs text-muted">
        Memberships are shown in demo mode as a one-month purchase. Automatic monthly renewal starts once card payments are connected.
      </p>
    </main>
  );
}
