"use server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { toBookingError } from "@/lib/booking-errors";
import { addDaysKey, dateKey } from "@/lib/format";
import { getSettings } from "@/lib/studio";
import type { Slot } from "@/lib/types";

const uuid = z.string().uuid();

/** Live availability for the whole booking window, straight from the engine. */
export async function getSlots(serviceId: string): Promise<{ slots: Slot[]; error?: string }> {
  if (!uuid.safeParse(serviceId).success) return { slots: [], error: "Unknown service." };
  const s = await getSettings();
  const from = dateKey(new Date(), s.timezone);
  const to = addDaysKey(from, Math.min(s.max_advance_days, 60));
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_available_slots", { p_service_id: serviceId, p_from: from, p_to: to });
  if (error) return { slots: [], error: "We couldn't load availability. Please try again." };
  return {
    slots: (data ?? []).map((r: { starts_at: string; ends_at: string; spots_left: number }) => ({
      startsAt: r.starts_at,
      endsAt: r.ends_at,
      spotsLeft: r.spots_left,
    })),
  };
}

const bookingInput = z.object({
  serviceId: uuid,
  startsAt: z.string().datetime({ offset: true }),
  partySize: z.number().int().min(1).max(50),
  fullName: z.string().trim().min(2, "Please enter your full name.").max(120),
  email: z.string().trim().toLowerCase().email("Please enter a valid email address.").max(254),
  phone: z
    .string()
    .trim()
    .max(40)
    .regex(/^[0-9+() .-]*$/, "Please enter a valid phone number.")
    .refine((v) => v === "" || v.replace(/\D/g, "").length >= 6, "Please enter a valid phone number."),
  notes: z.string().trim().max(1000).optional(),
  idempotencyKey: z.string().min(8).max(100),
  acceptPolicy: z.literal(true, { errorMap: () => ({ message: "Please accept the cancellation policy." }) }),
});

export type BookingResult =
  | { ok: true; reference: string; manageToken: string | null; status: string }
  | { ok: false; code: string; message: string };

export async function createBooking(input: z.input<typeof bookingInput>): Promise<BookingResult> {
  const parsed = bookingInput.safeParse(input);
  if (!parsed.success) return { ok: false, code: "INVALID", message: parsed.error.issues[0].message };
  const v = parsed.data;

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("book_session", {
    p_service_id: v.serviceId,
    p_starts_at: v.startsAt,
    p_full_name: v.fullName,
    p_email: v.email,
    p_phone: v.phone || null,
    p_party_size: v.partySize,
    p_idempotency_key: v.idempotencyKey,
    p_client_notes: v.notes || null,
  });
  if (error) {
    const e = toBookingError(error);
    return { ok: false, code: e.code, message: e.message };
  }
  const r = data as { reference: string; manage_token?: string; status: string };
  return { ok: true, reference: r.reference, manageToken: r.manage_token ?? null, status: r.status };
}
