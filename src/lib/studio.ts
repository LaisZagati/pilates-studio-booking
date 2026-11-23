import "server-only";
import { cache } from "react";
import { createPublicClient } from "@/lib/supabase/public";
import type { OpeningRule, Service, Settings } from "@/lib/types";

const FALLBACK: Settings = {
  studio_name: "Pilates Studio",
  tagline: null,
  logo_url: null,
  hero_image_url: null,
  about_text: null,
  address: null,
  maps_url: null,
  contact_email: null,
  contact_phone: null,
  instagram_url: null,
  timezone: "Europe/Madrid",
  currency: "EUR",
  min_advance_minutes: 120,
  max_advance_days: 60,
  cancellation_window_hours: 24,
  booking_policy: null,
  cancellation_policy: null,
};

export const getSettings = cache(async (): Promise<Settings> => {
  const supabase = createPublicClient();
  const { data } = await supabase.from("business_settings").select("*").maybeSingle();
  return { ...FALLBACK, ...(data ?? {}) } as Settings;
});

export const getServices = cache(async (): Promise<Service[]> => {
  const supabase = createPublicClient();
  const { data } = await supabase
    .from("services")
    .select("*")
    .eq("active", true)
    .order("sort_order", { ascending: true });
  return (data ?? []) as Service[];
});

export const getService = cache(async (slug: string): Promise<Service | null> => {
  const services = await getServices();
  return services.find((s) => s.slug === slug) ?? null;
});

/** Studio-wide opening hours, grouped Monday-first for display. */
export const getOpeningHours = cache(async () => {
  const supabase = createPublicClient();
  const { data } = await supabase
    .from("availability_rules")
    .select("weekday, start_time, end_time, service_id")
    .is("service_id", null)
    .order("start_time");
  const rules = (data ?? []) as OpeningRule[];
  return [1, 2, 3, 4, 5, 6, 0].map((wd) => ({
    weekday: wd,
    ranges: rules.filter((r) => r.weekday === wd).map((r) => [r.start_time.slice(0, 5), r.end_time.slice(0, 5)] as const),
  }));
});
