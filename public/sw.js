/* Service worker — deliberately conservative.
 * - Never caches private or live data: /admin, /account, /book, /manage, /auth,
 *   /api, Server Actions, Supabase, or any non-GET request.
 * - Static build assets & icons: cache-first (they are content-hashed).
 * - Public pages: network-first, falling back to the last copy, then /offline.html.
 * Bump VERSION to drop old caches on deploy.
 */
const VERSION = "v1";
const STATIC = `static-${VERSION}`;
const PAGES = `pages-${VERSION}`;
const PRECACHE = ["/offline.html", "/icons/icon-192.png"];
const PRIVATE = [/^\/admin/, /^\/account/, /^\/book/, /^\/manage/, /^\/auth/, /^\/api/, /^\/login/, /^\/signup/];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(STATIC).then((c) => c.addAll(PRECACHE)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => ![STATIC, PAGES].includes(k)).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;                         // bookings, actions, auth: always live
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;          // Supabase, fonts CDN etc.: browser handles
  if (req.headers.get("next-action") || req.headers.get("rsc") || url.searchParams.has("_rsc")) return;
  if (PRIVATE.some((re) => re.test(url.pathname))) {
    if (req.mode === "navigate") event.respondWith(fetch(req).catch(() => caches.match("/offline.html")));
    return;                                                   // never stored
  }

  if (url.pathname.startsWith("/_next/static/") || url.pathname.startsWith("/icons/") || /\.(?:woff2?|png|svg|jpg|webp|avif)$/.test(url.pathname)) {
    event.respondWith(
      caches.match(req).then((hit) => hit || fetch(req).then((res) => {
        if (res.ok) { const copy = res.clone(); caches.open(STATIC).then((c) => c.put(req, copy)); }
        return res;
      })),
    );
    return;
  }

  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const cc = res.headers.get("cache-control") || "";
          if (res.ok && !cc.includes("no-store") && !cc.includes("private")) {
            const copy = res.clone(); caches.open(PAGES).then((c) => c.put(req, copy));
          }
          return res;
        })
        .catch(() => caches.match(req).then((hit) => hit || caches.match("/offline.html"))),
    );
  }
});
