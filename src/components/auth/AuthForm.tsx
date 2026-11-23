"use client";
import { useActionState } from "react";
import Link from "next/link";
import type { AuthState } from "@/app/auth/actions";

type Mode = "signin" | "signup";

export function AuthForm({
  mode,
  action,
  next,
  title,
  showSignupLink = true,
}: {
  mode: Mode;
  action: (prev: AuthState, fd: FormData) => Promise<AuthState>;
  next?: string;
  title: string;
  showSignupLink?: boolean;
}) {
  const [state, formAction, pending] = useActionState(action, {});
  const field =
    "w-full rounded-xl border border-sand bg-white px-4 py-3.5 text-ink placeholder:text-taupe focus:border-clay focus:outline-none";

  return (
    <main className="mx-auto flex min-h-[70dvh] w-full max-w-md flex-col justify-center px-5 py-10">
      <h1 className="mb-8 text-center font-serif text-4xl">{title}</h1>
      <form action={formAction} className="space-y-4" noValidate>
        {next && <input type="hidden" name="next" value={next} />}
        {mode === "signup" && (
          <>
            <label className="block">
              <span className="mb-1.5 block text-sm text-muted">Full name</span>
              <input name="fullName" autoComplete="name" required className={field} />
            </label>
            <label className="block">
              <span className="mb-1.5 block text-sm text-muted">Phone (optional)</span>
              <input name="phone" type="tel" autoComplete="tel" inputMode="tel" className={field} />
            </label>
          </>
        )}
        <label className="block">
          <span className="mb-1.5 block text-sm text-muted">Email</span>
          <input name="email" type="email" autoComplete="email" inputMode="email" required className={field} />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm text-muted">Password</span>
          <input
            name="password"
            type="password"
            autoComplete={mode === "signup" ? "new-password" : "current-password"}
            required
            minLength={8}
            className={field}
          />
        </label>

        <div aria-live="polite" className="min-h-6 text-sm">
          {state.error && <p className="text-danger">{state.error}</p>}
          {state.message && <p className="text-success">{state.message}</p>}
        </div>

        <button
          type="submit"
          disabled={pending}
          className="w-full rounded-full bg-ink px-6 py-4 font-medium text-ivory transition active:scale-[0.99] disabled:opacity-60"
        >
          {pending ? "Please wait…" : mode === "signup" ? "Create account" : "Sign in"}
        </button>
      </form>

      {showSignupLink && (
        <p className="mt-8 text-center text-sm text-muted">
          {mode === "signin" ? (
            <>New here? <Link href="/signup" className="text-clay underline">Create an account</Link></>
          ) : (
            <>Already have an account? <Link href="/login" className="text-clay underline">Sign in</Link></>
          )}
        </p>
      )}
    </main>
  );
}
