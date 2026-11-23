import Link from "next/link";
import { ClockIcon, PeopleIcon } from "@/components/icons";
import { StudioImage } from "@/components/site/StudioImage";
import { formatPrice } from "@/lib/format";
import type { Service } from "@/lib/types";

export function capacityLabel(s: Service) {
  if (s.capacity === 1) return "1 client";
  return s.is_group ? `Up to ${s.capacity} clients` : `${s.capacity} clients`;
}

export function priceLabel(s: Service, currency: string) {
  return `${formatPrice(s.price_cents, currency)}${s.is_group ? " per person" : s.capacity > 1 ? " per session" : ""}`;
}

export function ServiceCard({ service, currency, index = 0 }: { service: Service; currency: string; index?: number }) {
  return (
    <article className="group flex flex-col overflow-hidden rounded-[var(--radius-card)] bg-white shadow-[0_1px_0_rgba(47,42,36,.04),0_8px_24px_-12px_rgba(47,42,36,.18)]">
      <Link href={`/services/${service.slug}`} className="block" tabIndex={-1} aria-hidden>
        <StudioImage src={service.image_url} alt="" ratio="4/3" variant={index} className="transition duration-500 group-hover:scale-[1.02]" />
      </Link>
      <div className="flex flex-1 flex-col p-5">
        <h3 className="font-serif text-2xl leading-tight">
          <Link href={`/services/${service.slug}`} className="hover:text-clay">{service.name}</Link>
        </h3>
        {service.short_description && <p className="mt-2 text-sm text-muted">{service.short_description}</p>}
        <ul className="mt-4 flex flex-wrap gap-x-4 gap-y-1 text-sm text-muted">
          <li className="flex items-center gap-1.5"><ClockIcon className="h-4 w-4" />{service.duration_minutes} min</li>
          <li className="flex items-center gap-1.5"><PeopleIcon className="h-4 w-4" />{capacityLabel(service)}</li>
        </ul>
        <div className="mt-auto flex items-center justify-between gap-3 pt-5">
          <p className="font-medium">{priceLabel(service, currency)}</p>
          <Link href={`/book?service=${service.slug}`} className="rounded-full bg-ink px-5 py-3 text-sm text-ivory transition hover:bg-clay active:scale-[0.98]">
            Book
          </Link>
        </div>
      </div>
    </article>
  );
}
