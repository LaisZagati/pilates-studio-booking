"use server";
import { z } from "zod";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { toBookingError } from "@/lib/booking-errors";

const input = z.object({
  reference: z.string().trim().toUpperCase().regex(/^PS-[A-Z0-9]{6}$/),
  token: z.string().regex(/^[a-f0-9]{16,128}$/),
});

export async function cancelGuestBooking(
  _prev: { error?: string; done?: boolean },
  formData: FormData,
): Promise<{ error?: string; done?: boolean }> {
  const parsed = input.safeParse({ reference: formData.get("reference"), token: formData.get("token") });
  if (!parsed.success) return { error: "This link is not valid." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_booking", {
    p_reference: parsed.data.reference,
    p_manage_token: parsed.data.token,
    p_reason: "Cancelled by client online",
  });
  if (error) return { error: toBookingError(error).message };
  revalidatePath("/manage");
  return { done: true };
}
