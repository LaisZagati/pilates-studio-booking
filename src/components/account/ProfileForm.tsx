"use client";
import { useActionState } from "react";
import { updateProfile } from "@/app/(site)/account/actions";

export function ProfileForm({ fullName, phone, email }: { fullName: string; phone: string; email: string }) {
  const [state, action, pending] = useActionState(updateProfile, {});
  const field = "w-full rounded-xl border border-sand bg-white px-4 py-3.5 focus:border-clay focus:outline-none";
  return (
    <form action={action} className="space-y-4">
      <label className="block">
        <span className="mb-1.5 block text-sm text-muted">Full name</span>
        <input name="fullName" defaultValue={fullName} required minLength={2} maxLength={120} autoComplete="name" className={field} />
      </label>
      <label className="block">
        <span className="mb-1.5 block text-sm text-muted">Phone</span>
        <input name="phone" type="tel" inputMode="tel" defaultValue={phone} maxLength={40} autoComplete="tel" className={field} />
      </label>
      <label className="block">
        <span className="mb-1.5 block text-sm text-muted">Email</span>
        <input value={email} readOnly className={`${field} bg-cream text-muted`} />
      </label>
      <div aria-live="polite" className="min-h-5 text-sm">
        {state.error && <p className="text-danger">{state.error}</p>}
        {state.message && <p className="text-success">{state.message}</p>}
      </div>
      <button type="submit" disabled={pending} className="w-full rounded-full bg-ink px-6 py-3.5 text-ivory disabled:opacity-50 sm:w-auto">
        {pending ? "Saving…" : "Save details"}
      </button>
    </form>
  );
}
