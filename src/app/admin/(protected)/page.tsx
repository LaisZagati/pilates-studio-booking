import { requireAdmin } from "@/lib/auth";
import { signOut } from "@/app/auth/actions";

export const metadata = { title: "Dashboard" };

// Phase 1: proves admin auth end-to-end. Phase 4 replaces this with the full dashboard.
export default async function AdminHome() {
  const { supabase, user } = await requireAdmin();
  const { count } = await supabase.from("bookings").select("id", { count: "exact", head: true });
  return (
    <main className="mx-auto max-w-2xl px-5 py-10">
      <h1 className="font-serif text-4xl">Studio admin</h1>
      <p className="mt-2 text-muted">Signed in as {user.email}</p>
      <p className="mt-6 rounded-[var(--radius-card)] bg-cream p-5">Bookings in the system: <strong>{count ?? 0}</strong></p>
      <form action={signOut} className="mt-8">
        <button className="rounded-full border border-sand px-5 py-3">Sign out</button>
      </form>
    </main>
  );
}
