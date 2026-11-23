import type { Metadata, Viewport } from "next";
import { getSettings } from "@/lib/studio";
import { AppShell } from "@/components/AppShell";
import "./globals.css";


export async function generateMetadata(): Promise<Metadata> {
  const s = await getSettings();
  return {
    title: { default: s.studio_name, template: `%s · ${s.studio_name}` },
    description: s.tagline ?? "Boutique reformer and mat Pilates. Book your session online.",
    applicationName: s.studio_name,
    // manifest.webmanifest, icon.png and apple-icon.png (180×180) are linked automatically by Next.js.
    appleWebApp: { capable: true, title: s.studio_name, statusBarStyle: "default" },
    formatDetection: { telephone: false },
    other: { "apple-mobile-web-app-capable": "yes", "mobile-web-app-capable": "yes" },
  };
}

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#fbf8f2",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        {/* Fonts load in the browser (no build-time download needed). */}
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        {/* eslint-disable-next-line @next/next/no-page-custom-font */}
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@400;500;600&family=Inter:wght@400;500;600&display=swap"
        />
      </head>
      <body className="antialiased">
        {children}
        <AppShell />
      </body>
    </html>
  );
}
