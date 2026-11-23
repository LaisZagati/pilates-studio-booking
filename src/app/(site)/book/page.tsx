import { BookingFlow } from "@/components/booking/BookingFlow";
import { createClient } from "@/lib/supabase/server";
import { getServices, getSettings } from "@/lib/studio";

export const dynamic = "force-dynamic";
export const metadata = { title: "Book a session" };

export default async function BookPage({ searchParams }: { searchParams: Promise<{ service?: string }> }) {
  const [{ service }, s, services] = await Promise.all([searchParams, getSettings(), getServices()]);

  // Prefill for signed-in clients (their own row only — RLS).
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  let prefill = { fullName: "", email: "", phone: "", signedIn: false };
  if (user) {
    const { data: client } = await supabase.from("clients").select("full_name, phone").maybeSingle();
    const { data: profile } = await supabase.from("profiles").select("full_name, phone").maybeSingle();
    prefill = {
      fullName: client?.full_name ?? profile?.full_name ?? "",
      email: user.email ?? "",
      phone: client?.phone ?? profile?.phone ?? "",
      signedIn: true,
    };
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
      />
    </main>
  );
}
