import Link from "next/link";
import { notFound } from "next/navigation";
import { getService, getSettings } from "@/lib/studio";
import { StudioImage } from "@/components/site/StudioImage";
import { capacityLabel, priceLabel } from "@/components/site/ServiceCard";
import { ChevronLeft, ClockIcon, PeopleIcon } from "@/components/icons";

export const revalidate = 60;

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }) {
  const svc = await getService((await params).slug);
  return { title: svc?.name ?? "Class", description: svc?.short_description ?? undefined };
}

export default async function ServicePage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const [svc, s] = await Promise.all([getService(slug), getSettings()]);
  if (!svc) notFound();

  return (
    <main className="mx-auto max-w-5xl px-5 py-6 md:py-12">
      <Link href="/services" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ChevronLeft className="h-4 w-4" /> All classes
      </Link>
      <div className="mt-4 grid gap-8 md:grid-cols-2 md:gap-12">
        <StudioImage src={svc.image_url} alt={svc.name} ratio="4/5" priority className="rounded-[2rem]" variant={svc.sort_order} />
        <div className="md:pt-6">
          <h1 className="font-serif text-5xl leading-tight">{svc.name}</h1>
          <ul className="mt-5 flex flex-wrap gap-x-5 gap-y-2 text-muted">
            <li className="flex items-center gap-1.5"><ClockIcon className="h-5 w-5" />{svc.duration_minutes} minutes</li>
            <li className="flex items-center gap-1.5"><PeopleIcon className="h-5 w-5" />{capacityLabel(svc)}</li>
          </ul>
          <p className="mt-6 text-lg leading-relaxed">{svc.description ?? svc.short_description}</p>
          <p className="mt-8 text-2xl">{priceLabel(svc, s.currency)}</p>
          <Link href={`/book?service=${svc.slug}`} className="mt-6 block rounded-full bg-ink px-7 py-4 text-center text-ivory transition hover:bg-clay md:inline-block">
            Check availability
          </Link>
          {s.booking_policy && <p className="mt-8 text-sm text-muted">{s.booking_policy}</p>}
        </div>
      </div>
    </main>
  );
}
