"use server";
import { z } from "zod";
import { after } from "next/server";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { toBookingError } from "@/lib/booking-errors";
import { runNotificationQueue } from "@/lib/email/queue";

const ref = z.string().trim().toUpperCase().regex(/^PS-[A-Z0-9]{6}$/);
const token = z.string().regex(/^[a-f0-9]{16,128}$/).optional();

export type PayResult = { status: "confirmed" | "declined" | "error"; message?: string };

/** Demo payment: no card details, no money. Only works while the studio is in demo mode. */
export async function demoPay(reference: string, manageToken: string | undefined, succeed: boolean): Promise<PayResult> {
  const r = ref.safeParse(reference);
  const t = token.safeParse(manageToken || undefined);
  if (!r.success || !t.success) return { status: "error", message: "This payment link is not valid." };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("demo_pay_booking", {
    p_reference: r.data,
    p_token: t.data ?? null,
    p_succeed: succeed,
  });
  if (error) return { status: "error", message: toBookingError(error).message };
  const status = (data as { status: string }).status;
  if (status === "confirmed") {
    after(async () => {
      try {
        await runNotificationQueue();
      } catch {
        /* stays queued */
      }
    });
    revalidatePath("/account");
    return { status: "confirmed" };
  }
  return { status: "declined", message: "Demo card declined — nothing was charged. Try again or use another card." };
}

/** Demo pack purchase for signed-in clients. */
export async function demoBuyPack(packageId: string): Promise<{ ok: boolean; message: string }> {
  if (!z.string().uuid().safeParse(packageId).success) return { ok: false, message: "Pack not found." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("demo_buy_package", { p_package_id: packageId });
  if (error) return { ok: false, message: toBookingError(error).message };
  after(async () => {
    try {
      await runNotificationQueue();
    } catch {
      /* stays queued */
    }
  });
  revalidatePath("/account");
  return { ok: true, message: "Credits added to your account." };
}
