import "server-only";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

/** Returns the signed-in user or redirects to /login. */
export async function requireUser(next = "/account") {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect(`/login?next=${encodeURIComponent(next)}`);
  return { supabase, user };
}

/** Returns the signed-in administrator or redirects away. Call in every admin layout/action. */
export async function requireAdmin(next = "/admin") {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect(`/admin/login?next=${encodeURIComponent(next)}`);
  const { data: isAdmin, error } = await supabase.rpc("is_admin");
  if (error || !isAdmin) redirect("/");
  return { supabase, user };
}
