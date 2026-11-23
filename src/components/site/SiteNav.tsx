"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { CalendarIcon, HomeIcon, SparkIcon, UserIcon } from "@/components/icons";

const TABS = [
  { href: "/", label: "Home", Icon: HomeIcon, match: (p: string) => p === "/" },
  { href: "/services", label: "Classes", Icon: SparkIcon, match: (p: string) => p.startsWith("/services") },
  { href: "/book", label: "Book", Icon: CalendarIcon, match: (p: string) => p.startsWith("/book") },
  { href: "/account", label: "Account", Icon: UserIcon, match: (p: string) => p.startsWith("/account") || p === "/login" || p === "/signup" },
];

/** Compact header (all sizes) with inline links on tablet/desktop. */
export function SiteHeader({ studioName, logoUrl }: { studioName: string; logoUrl: string | null }) {
  const pathname = usePathname();
  return (
    <header className="sticky top-0 z-30 border-b border-sand/70 bg-ivory/90 pt-[env(safe-area-inset-top)] backdrop-blur-md">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-5 md:h-16">
        <Link href="/" className="flex items-center gap-2 font-serif text-2xl tracking-wide">
          {logoUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={logoUrl} alt="" width={32} height={32} className="h-8 w-8 rounded-full object-cover" />
          ) : null}
          <span>{studioName}</span>
        </Link>
        <nav aria-label="Main" className="hidden items-center gap-8 text-sm md:flex">
          {TABS.slice(1, 2).concat(TABS.slice(3)).map((t) => (
            <Link key={t.href} href={t.href} className={t.match(pathname) ? "text-ink" : "text-muted hover:text-ink"}>
              {t.label}
            </Link>
          ))}
          <Link href="/book" className="rounded-full bg-ink px-5 py-2.5 text-ivory transition hover:bg-clay">
            Book a session
          </Link>
        </nav>
        <Link href="/book" className="rounded-full bg-ink px-4 py-2 text-sm text-ivory md:hidden">
          Book
        </Link>
      </div>
    </header>
  );
}

/** Bottom tab bar on phones, respecting the iPhone home indicator. */
export function MobileTabBar() {
  const pathname = usePathname();
  return (
    <nav
      aria-label="Primary"
      className="fixed inset-x-0 bottom-0 z-30 border-t border-sand bg-ivory/95 pb-[env(safe-area-inset-bottom)] backdrop-blur-md md:hidden"
    >
      <ul className="grid grid-cols-4">
        {TABS.map(({ href, label, Icon, match }) => {
          const active = match(pathname);
          return (
            <li key={href}>
              <Link
                href={href}
                aria-current={active ? "page" : undefined}
                className={`flex min-h-14 flex-col items-center justify-center gap-0.5 text-[11px] ${active ? "text-ink" : "text-muted"}`}
              >
                <Icon className={`h-6 w-6 ${active ? "stroke-[2]" : ""}`} />
                {label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
