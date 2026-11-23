import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Refreshes the auth session on every request and gates private areas.
 * The admin check here is a fast first line; every admin page and every
 * database call re-checks on the server (requireAdmin + RLS + is_admin()).
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        },
      },
    },
  );

  // getUser() validates the token with Supabase Auth (don't trust getSession() here).
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = request.nextUrl.pathname;
  const isAdminArea = path.startsWith("/admin") && !path.startsWith("/admin/login");
  const isAccountArea = path.startsWith("/account");

  if ((isAdminArea || isAccountArea) && !user) {
    const url = request.nextUrl.clone();
    url.pathname = isAdminArea ? "/admin/login" : "/login";
    url.searchParams.set("next", path);
    return NextResponse.redirect(url);
  }

  if (isAdminArea && user) {
    const { data: isAdmin } = await supabase.rpc("is_admin");
    if (!isAdmin) {
      const url = request.nextUrl.clone();
      url.pathname = "/";
      url.search = "";
      return NextResponse.redirect(url);
    }
  }

  // Private pages must never be stored by the browser or service worker caches.
  if (isAdminArea || isAccountArea || path.startsWith("/manage") || path.startsWith("/book")) {
    response.headers.set("Cache-Control", "private, no-store");
  }
  return response;
}
