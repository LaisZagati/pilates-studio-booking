"use client";
/**
 * One bridge for web, PWA, Android (TWA) and iOS (Capacitor).
 * The same pages run everywhere; when the iOS app shell is present, native
 * plugins are reached through window.Capacitor (registered by the native
 * project in /mobile), so the web bundle needs no extra packages.
 * Every function falls back gracefully on the web.
 */

type ListenerHandle = { remove: () => Promise<void> };
type CapacitorGlobal = {
  isNativePlatform?: () => boolean;
  getPlatform?: () => "ios" | "android" | "web";
  Plugins?: {
    Share?: { share: (o: { title?: string; text?: string; url?: string; dialogTitle?: string }) => Promise<unknown> };
    Browser?: { open: (o: { url: string; presentationStyle?: "popover" | "fullscreen" }) => Promise<void> };
    App?: { addListener: (e: "appUrlOpen", cb: (d: { url: string }) => void) => Promise<ListenerHandle> };
    SplashScreen?: { hide: () => Promise<void> };
    Haptics?: { impact: (o: { style: "LIGHT" | "MEDIUM" | "HEAVY" }) => Promise<void> };
  };
};

function cap(): CapacitorGlobal | undefined {
  if (typeof window === "undefined") return undefined;
  return (window as unknown as { Capacitor?: CapacitorGlobal }).Capacitor;
}

export function isNativeApp() {
  return !!cap()?.isNativePlatform?.();
}

export function nativePlatform(): "ios" | "android" | "web" {
  return cap()?.getPlatform?.() ?? "web";
}

/** Installed as a Home Screen app (PWA or Android TWA) rather than a browser tab. */
export function isStandalone() {
  if (typeof window === "undefined") return false;
  return window.matchMedia?.("(display-mode: standalone)").matches || (navigator as { standalone?: boolean }).standalone === true;
}

export type ShareData = { title: string; text: string; url?: string };

/** Native share sheet on iOS/Android/modern browsers; copies to clipboard otherwise. Returns what happened. */
export async function share(data: ShareData): Promise<"shared" | "copied" | "cancelled" | "unsupported"> {
  try {
    const plugin = cap()?.Plugins?.Share;
    if (isNativeApp() && plugin) {
      await plugin.share({ ...data, dialogTitle: data.title });
      return "shared";
    }
    if (typeof navigator !== "undefined" && navigator.share) {
      await navigator.share(data);
      return "shared";
    }
    if (typeof navigator !== "undefined" && navigator.clipboard) {
      await navigator.clipboard.writeText([data.text, data.url].filter(Boolean).join(" "));
      return "copied";
    }
    return "unsupported";
  } catch (e) {
    return (e as Error)?.name === "AbortError" ? "cancelled" : "cancelled";
  }
}

/** Opens a link outside the app (system browser / in-app Safari sheet on iOS). */
export async function openExternal(url: string) {
  const browser = cap()?.Plugins?.Browser;
  if (isNativeApp() && browser) return browser.open({ url, presentationStyle: "popover" });
  window.open(url, "_blank", "noopener,noreferrer");
}

export async function tapFeedback() {
  try {
    if (isNativeApp()) await cap()?.Plugins?.Haptics?.impact({ style: "LIGHT" });
  } catch {
    /* optional */
  }
}

export function onDeepLink(cb: (path: string) => void): () => void {
  const app = cap()?.Plugins?.App;
  if (!isNativeApp() || !app) return () => {};
  let handle: ListenerHandle | undefined;
  app
    .addListener("appUrlOpen", ({ url }) => {
      try {
        const u = new URL(url);
        // Universal links (https://studio-domain/...) and the custom scheme both map to an in-app path.
        cb(`${u.pathname}${u.search}${u.hash}` || "/");
      } catch {
        /* ignore malformed */
      }
    })
    .then((h) => (handle = h));
  return () => void handle?.remove();
}

export async function hideSplash() {
  try {
    await cap()?.Plugins?.SplashScreen?.hide();
  } catch {
    /* optional */
  }
}
