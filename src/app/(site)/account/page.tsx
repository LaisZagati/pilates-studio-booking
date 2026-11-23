import { requireUser } from "@/lib/auth";
import { signOut } from "@/app/auth/actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "My account" };

// Phase 1: proves client auth + RLS. Phase 5 builds the full client area.
export default async function AccountPage() {
  const { supabase, user } = await requireUser();
  const { data: bookings } = await supabase
    .from("bookings")
    .select("reference, status, sessions(starts_at, services(name))")
    .order("created_at", { ascending: false })
    .limit(20);
  return (
    <main className="mx-auto max-w-2xl px-5 py-10">
      <h1 className="font-serif text-4xl">My account</h1>
      <p className="mt-2 text-muted">{user.email}</p>
      <h2 className="mt-8 text-lg font-medium">Your bookings</h2>
      <ul className="mt-3 space-y-2">
        {(bookings ?? []).length === 0 && <li className="text-muted">No bookings yet.</li>}
        {(bookings ?? []).map((b) => (
          <li key={b.reference} className="rounded-xl bg-cream px-4 py-3">
            {b.reference} · {b.status}
          </li>
        ))}
      </ul>
      <form action={signOut} className="mt-8">
        <button className="rounded-full border border-sand px-5 py-3">Sign out</button>
      </form>
    </main>
  );
}
