import Link from "next/link";
import { getSettings } from "@/lib/studio";
import { MobileTabBar, SiteHeader } from "@/components/site/SiteNav";

export default async function SiteLayout({ children }: { children: React.ReactNode }) {
  const s = await getSettings();
  return (
    <>
      <a href="#main" className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-50 focus:rounded-full focus:bg-ink focus:px-4 focus:py-2 focus:text-ivory">
        Skip to content
      </a>
      <SiteHeader studioName={s.studio_name} logoUrl={s.logo_url} />
      <div id="main" className="pb-[calc(4.5rem+env(safe-area-inset-bottom))] md:pb-0">
        {children}
        <footer className="mt-16 border-t border-sand bg-cream">
          <div className="mx-auto grid max-w-6xl gap-6 px-5 py-10 text-sm text-muted md:grid-cols-3">
            <div>
              <p className="font-serif text-2xl text-ink">{s.studio_name}</p>
              {s.tagline && <p className="mt-1">{s.tagline}</p>}
            </div>
            <div className="space-y-1">
              {s.address && <p>{s.address}</p>}
              {s.contact_phone && <p><a href={`tel:${s.contact_phone.replace(/\s/g, "")}`} className="hover:text-ink">{s.contact_phone}</a></p>}
              {s.contact_email && <p><a href={`mailto:${s.contact_email}`} className="hover:text-ink">{s.contact_email}</a></p>}
            </div>
            <div className="space-y-1 md:text-right">
              <p><Link href="/services" className="hover:text-ink">Classes</Link></p>
              <p><Link href="/book" className="hover:text-ink">Book online</Link></p>
              <p><Link href="/packs" className="hover:text-ink">Packs &amp; memberships</Link></p>
              <p><Link href="/manage" className="hover:text-ink">Manage a booking</Link></p>
              {s.instagram_url && <p><a href={s.instagram_url} target="_blank" rel="noopener noreferrer" className="hover:text-ink">Instagram</a></p>}
            </div>
          </div>
          <p className="pb-8 text-center text-xs text-taupe">© {new Date().getFullYear()} {s.studio_name}</p>
        </footer>
      </div>
      <MobileTabBar />
    </>
  );
}
