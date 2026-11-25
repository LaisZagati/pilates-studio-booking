import { BookingFlow } from "@/components/booking/BookingFlow";
import { createClient } from "@/lib/supabase/server";
import { getServices, getSettings } from "@/lib/studio";
import type { Credit } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Book a session" };

export default async function BookPage({ searchParams }: { searchParams: Promise<{ service?: string }> }) {
  const [{ service }, s, services] = await Promise.all([searchParams, getSettings(), getServices()]);

  // Prefill for signed-in clients (their own row only — RLS).
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  let prefill = { fullName: "", email: "", phone: "", signedIn: false };
  let credits: Credit[] = [];
  if (user) {
    const { data: client } = await supabase.from("clients").select("full_name, phone").maybeSingle();
    const { data: profile } = await supabase.from("profiles").select("full_name, phone").maybeSingle();
    prefill = {
      fullName: client?.full_name ?? profile?.full_name ?? "",
      email: user.email ?? "",
      phone: client?.phone ?? profile?.phone ?? "",
      signedIn: true,
    };
    const { data: cr } = await supabase
      .from("client_credits")
      .select("id, label, credits_total, credits_used, service_ids, expires_at")
      .gt("expires_at", new Date().toISOString());
    credits = ((cr ?? []) as Credit[]).filter((c) => c.credits_total > c.credits_used);
  }

  return (
    <main className="mx-auto max-w-xl px-5 py-6 md:py-12">
      <BookingFlow
        services={services}
        initialServiceSlug={service}
        timeZone={s.timezone}
        currency={s.currency}
        cancellationPolicy={s.cancellation_policy}
        cancellationHours={s.cancellation_window_hours}
        prefill={prefill}
        credits={credits}
      />
    </main>
  );
}
