"use server";
import { z } from "zod";
import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { createClient } from "@/lib/supabase/server";

export type AuthState = { error?: string; message?: string };

const safeNext = (v: FormDataEntryValue | null, fallback: string) => {
  const s = typeof v === "string" ? v : "";
  // only allow same-site relative paths (prevents open redirects)
  return s.startsWith("/") && !s.startsWith("//") ? s : fallback;
};

const credentials = z.object({
  email: z.string().trim().toLowerCase().email("Please enter a valid email address.").max(254),
  password: z.string().min(8, "Password must be at least 8 characters.").max(72),
});

export async function signIn(_prev: AuthState, formData: FormData): Promise<AuthState> {
  const parsed = credentials.safeParse({ email: formData.get("email"), password: formData.get("password") });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  if (error) return { error: "Email or password is incorrect." };

  await supabase.rpc("link_my_client");
  redirect(safeNext(formData.get("next"), "/account"));
}

const signUpSchema = credentials.extend({
  fullName: z.string().trim().min(2, "Please enter your full name.").max(120),
  phone: z.string().trim().max(40).regex(/^[0-9+() .-]*$/, "Please enter a valid phone number.").optional(),
});

export async function signUp(_prev: AuthState, formData: FormData): Promise<AuthState> {
  const parsed = signUpSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
    fullName: formData.get("fullName"),
    phone: formData.get("phone") || undefined,
  });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const origin = process.env.NEXT_PUBLIC_APP_URL ?? (await headers()).get("origin") ?? "";
  const supabase = await createClient();
  const { error } = await supabase.auth.signUp({
    email: parsed.data.email,
    password: parsed.data.password,
    options: {
      emailRedirectTo: `${origin}/auth/callback?next=/account`,
      data: { full_name: parsed.data.fullName, phone: parsed.data.phone ?? "" },
    },
  });
  // Same message whether or not the email already exists (no account enumeration).
  if (error && error.status !== 422) return { error: "We couldn't create your account. Please try again." };
  return { message: "Check your inbox to confirm your email, then sign in." };
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}

export async function requestPasswordReset(_prev: AuthState, formData: FormData): Promise<AuthState> {
  const email = z.string().trim().email().safeParse(formData.get("email"));
  if (!email.success) return { error: "Please enter a valid email address." };
  const origin = process.env.NEXT_PUBLIC_APP_URL ?? (await headers()).get("origin") ?? "";
  const supabase = await createClient();
  await supabase.auth.resetPasswordForEmail(email.data, {
    redirectTo: `${origin}/auth/callback?next=/account/password`,
  });
  return { message: "If that email has an account, a reset link is on its way." };
}
