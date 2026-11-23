import type { MetadataRoute } from "next";
import { getSettings } from "@/lib/studio";

// Served at /manifest.webmanifest
export default async function manifest(): Promise<MetadataRoute.Manifest> {
  const s = await getSettings();
  const short = s.studio_name.length > 12 ? s.studio_name.split(" ")[0] : s.studio_name;
  return {
    id: "/",
    name: s.studio_name,
    short_name: short,
    description: s.tagline ?? "Book Pilates sessions and manage your bookings.",
    start_url: "/?source=pwa",
    scope: "/",
    display: "standalone",
    display_override: ["standalone", "minimal-ui"],
    orientation: "portrait",
    background_color: "#fbf8f2",
    theme_color: "#fbf8f2",
    lang: "en",
    dir: "ltr",
    categories: ["health", "fitness", "lifestyle"],
    icons: [
      { src: "/icons/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icons/maskable-192.png", sizes: "192x192", type: "image/png", purpose: "maskable" },
      { src: "/icons/maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
    shortcuts: [
      { name: "Book a session", short_name: "Book", url: "/book", icons: [{ src: "/icons/icon-192.png", sizes: "192x192" }] },
      { name: "My bookings", short_name: "Bookings", url: "/account", icons: [{ src: "/icons/icon-192.png", sizes: "192x192" }] },
    ],
  };
}
