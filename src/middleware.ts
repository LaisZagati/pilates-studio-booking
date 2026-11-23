import type { NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  // Skip static assets, images, the manifest and the service worker.
  matcher: ["/((?!_next/static|_next/image|favicon.ico|icons/|images/|manifest.webmanifest|sw.js|offline.html|\\.well-known/|apple-app-site-association|.*\\.(?:png|jpg|jpeg|svg|webp|avif)$).*)"],
};
