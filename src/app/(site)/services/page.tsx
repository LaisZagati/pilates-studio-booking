import { getServices, getSettings } from "@/lib/studio";
import { ServiceCard } from "@/components/site/ServiceCard";

export const revalidate = 60;
export const metadata = { title: "Classes" };

export default async function ServicesPage() {
  const [s, services] = await Promise.all([getSettings(), getServices()]);
  return (
    <main className="mx-auto max-w-6xl px-5 py-10">
      <h1 className="font-serif text-5xl">Classes</h1>
      <p className="mt-3 max-w-xl text-muted">Every session lasts an hour and is taught by a qualified instructor. Choose the format that suits you.</p>
      <div className="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        {services.map((svc, i) => <ServiceCard key={svc.id} service={svc} currency={s.currency} index={i} />)}
      </div>
      {s.cancellation_policy && (
        <section className="mt-12 rounded-[var(--radius-card)] bg-cream p-6 text-sm text-muted">
          <h2 className="mb-2 font-medium text-ink">Cancellation policy</h2>
          <p>{s.cancellation_policy}</p>
        </section>
      )}
    </main>
  );
}
