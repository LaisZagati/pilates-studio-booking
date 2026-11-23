"use server";
import { z } from "zod";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { toBookingError } from "@/lib/booking-errors";

export type ActionState = { error?: string; message?: string };

const uuid = z.string().uuid();

export async function cancelMyBooking(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("bookingId"));
  if (!id.success) return { error: "Booking not found." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_booking", { p_booking_id: id.data, p_reason: "Cancelled by client online" });
  if (error) return { error: toBookingError(error).message };
  revalidatePath("/account");
  return { message: "Booking cancelled." };
}

export async function requestChange(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("bookingId"));
  const msg = z.string().trim().min(3, "Tell us which day or time suits you.").max(1000).safeParse(formData.get("message"));
  if (!id.success) return { error: "Booking not found." };
  if (!msg.success) return { error: msg.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("request_reschedule", { p_booking_id: id.data, p_message: msg.data });
  if (error) return { error: toBookingError(error).message };
  revalidatePath("/account");
  return { message: "Request sent — the studio will confirm your new time." };
}

const profile = z.object({
  fullName: z.string().trim().min(2, "Please enter your full name.").max(120),
  phone: z.string().trim().max(40).regex(/^[0-9+() .-]*$/, "Please enter a valid phone number."),
});

export async function updateProfile(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = profile.safeParse({ fullName: formData.get("fullName"), phone: formData.get("phone") ?? "" });
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Please sign in again." };
  await supabase.rpc("link_my_client");
  const values = { full_name: parsed.data.fullName, phone: parsed.data.phone || null };
  const [a, b] = await Promise.all([
    supabase.from("clients").update(values).eq("user_id", user.id),
    supabase.from("profiles").update(values).eq("id", user.id),
  ]);
  if (a.error || b.error) return { error: "We couldn't save your details. Please try again." };
  revalidatePath("/account");
  return { message: "Details saved." };
}
