"use client";
import { createBrowserClient } from "@supabase/ssr";

/** Browser client (anon key only; RLS applies). Used for realtime updates. */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
