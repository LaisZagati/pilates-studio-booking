"use client";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { hideSplash, isNativeApp, nativePlatform, onDeepLink, openExternal } from "@/lib/native";

/**
 * Runs once per app load on every platform:
 * - Web / PWA / Android TWA: registers the safe service worker.
 * - iOS app: deep links -> in-app routes, external links -> Safari sheet,
 *   tel:/mailto: -> system apps, hides the native splash screen.
 */
export function AppShell() {
  const router = useRouter();

  useEffect(() => {
    const native = isNativeApp();
    document.documentElement.dataset.platform = native ? nativePlatform() : "web";

    if (!native && "serviceWorker" in navigator && process.env.NODE_ENV === "production") {
      navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch(() => {});
    }
    if (!native) return;

    hideSplash();
    const stopDeepLinks = onDeepLink((path) => router.push(path));

    const onClick = (e: MouseEvent) => {
      const a = (e.target as HTMLElement | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!a || e.defaultPrevented || a.hasAttribute("download")) return;
      const href = a.getAttribute("href") ?? "";
      if (/^(tel|mailto|sms):/i.test(href)) return; // WKWebView hands these to the system
      try {
        const url = new URL(href, location.href);
        if (url.origin !== location.origin && /^https?:$/.test(url.protocol)) {
          e.preventDefault();
          openExternal(url.toString());
        }
      } catch {
        /* ignore */
      }
    };
    document.addEventListener("click", onClick);
    return () => {
      stopDeepLinks();
      document.removeEventListener("click", onClick);
    };
  }, [router]);

  return null;
}
