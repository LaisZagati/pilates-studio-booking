import Link from "next/link";
import { getOpeningHours, getServices, getSettings } from "@/lib/studio";
import { ServiceCard } from "@/components/site/ServiceCard";
import { StudioImage } from "@/components/site/StudioImage";
import { PinIcon } from "@/components/icons";
import { WEEKDAYS } from "@/lib/format";

export const revalidate = 60;

export default async function HomePage() {
  const [s, services, hours] = await Promise.all([getSettings(), getServices(), getOpeningHours()]);

  return (
    <main>
      {/* Hero */}
      <section className="mx-auto grid max-w-6xl items-center gap-8 px-5 pt-6 md:grid-cols-2 md:gap-12 md:pt-14">
        <div className="order-2 md:order-1">
          <p className="text-xs uppercase tracking-[0.25em] text-clay">Boutique Pilates studio</p>
          <h1 className="mt-3 font-serif text-[2.75rem] leading-[1.05] sm:text-6xl">
            Move with intention.<br />Feel the difference.
          </h1>
          <p className="mt-5 max-w-md text-lg text-muted">
            {s.tagline ?? "Private, duet and small-group Pilates in a calm, light-filled space."}
          </p>
          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            <Link href="/book" className="rounded-full bg-ink px-7 py-4 text-center text-ivory transition hover:bg-clay active:scale-[0.99]">
              Book a session
            </Link>
            <Link href="/services" className="rounded-full border border-taupe px-7 py-4 text-center transition hover:border-ink">
              Explore classes
            </Link>
          </div>
        </div>
        <StudioImage
          src={s.hero_image_url}
          alt={`${s.studio_name} studio`}
          ratio="4/5"
          priority
          className="order-1 -mx-5 rounded-none sm:mx-0 sm:rounded-[2rem] md:order-2"
        />
      </section>

      {/* About */}
      <section className="mx-auto mt-20 max-w-3xl px-5 text-center">
        <h2 className="font-serif text-4xl">A studio made for focus</h2>
        <p className="mt-5 text-lg leading-relaxed text-muted">
          {s.about_text ??
            "Two reformers, one mat room and plenty of personal attention. Sessions are one-to-one, in pairs or in small groups of up to four."}
        </p>
      </section>

      {/* Services */}
      <section className="mx-auto mt-20 max-w-6xl px-5" aria-labelledby="classes">
        <div className="flex items-end justify-between gap-4">
          <h2 id="classes" className="font-serif text-4xl">Our sessions</h2>
          <Link href="/services" className="shrink-0 text-sm text-clay underline-offset-4 hover:underline">View all</Link>
        </div>
        <div className="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {services.map((svc, i) => (
            <ServiceCard key={svc.id} service={svc} currency={s.currency} index={i} />
          ))}
        </div>
      </section>

      {/* CTA */}
      <section className="mx-auto mt-20 max-w-6xl px-5">
        <div className="rounded-[2rem] bg-ink px-6 py-12 text-center text-ivory sm:px-12">
          <h2 className="font-serif text-4xl">Ready when you are</h2>
          <p className="mx-auto mt-3 max-w-md text-ivory/75">See live availability and book in under a minute — no account needed.</p>
          <Link href="/book" className="mt-8 inline-block rounded-full bg-ivory px-8 py-4 text-ink transition hover:bg-cream">
            Find a time
          </Link>
        </div>
      </section>

      {/* Visit */}
      <section className="mx-auto mt-20 grid max-w-6xl gap-10 px-5 md:grid-cols-2" aria-labelledby="visit">
        <div>
          <h2 id="visit" className="font-serif text-4xl">Visit us</h2>
          {s.address && (
            <p className="mt-5 flex gap-2 text-lg">
              <PinIcon className="mt-1 h-5 w-5 shrink-0 text-clay" />
              {s.maps_url ? (
                <a href={s.maps_url} target="_blank" rel="noopener noreferrer" className="underline-offset-4 hover:underline">{s.address}</a>
              ) : (
                s.address
              )}
            </p>
          )}
          <div className="mt-5 space-y-2 text-muted">
            {s.contact_phone && <p>Phone: <a className="text-ink" href={`tel:${s.contact_phone.replace(/\s/g, "")}`}>{s.contact_phone}</a></p>}
            {s.contact_email && <p>Email: <a className="text-ink" href={`mailto:${s.contact_email}`}>{s.contact_email}</a></p>}
          </div>
        </div>
        <div className="rounded-[var(--radius-card)] bg-cream p-6">
          <h3 className="font-medium">Opening hours</h3>
          <dl className="mt-4 divide-y divide-sand text-sm">
            {hours.map((h) => (
              <div key={h.weekday} className="flex justify-between py-2.5">
                <dt>{WEEKDAYS[h.weekday]}</dt>
                <dd className="text-muted">{h.ranges.length ? h.ranges.map((r) => `${r[0]}–${r[1]}`).join(", ") : "Closed"}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>
    </main>
  );
}
