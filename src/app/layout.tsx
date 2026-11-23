import type { Metadata, Viewport } from "next";
import { Cormorant_Garamond, Inter } from "next/font/google";
import { getSettings } from "@/lib/studio";
import { AppShell } from "@/components/AppShell";
import "./globals.css";

const serif = Cormorant_Garamond({ subsets: ["latin"], weight: ["400", "500", "600"], variable: "--font-serif-loaded", display: "swap" });
const sans = Inter({ subsets: ["latin"], variable: "--font-sans-loaded", display: "swap" });

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
    <html lang="en" className={`${serif.variable} ${sans.variable}`}>
      <body className="antialiased">
        {children}
        <AppShell />
      </body>
    </html>
  );
}
