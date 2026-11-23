"use client";
import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import Link from "next/link";
import { createBooking, getSlots, type BookingResult } from "@/app/(site)/book/actions";
import { formatDateLong, formatPrice, formatTime, dateKey, keyParts } from "@/lib/format";
import type { Service, Slot } from "@/lib/types";
import { CheckIcon, ChevronLeft, ClockIcon, PeopleIcon } from "@/components/icons";
import { ShareButton } from "@/components/ShareButton";

type Prefill = { fullName: string; email: string; phone: string; signedIn: boolean };
type Step = "service" | "time" | "details" | "review" | "done";

const STEPS: { id: Step; label: string }[] = [
  { id: "service", label: "Class" },
  { id: "time", label: "Time" },
  { id: "details", label: "Details" },
  { id: "review", label: "Confirm" },
];

function newKey() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

export function BookingFlow({
  services,
  initialServiceSlug,
  timeZone,
  currency,
  cancellationPolicy,
  cancellationHours,
  prefill,
}: {
  services: Service[];
  initialServiceSlug?: string;
  timeZone: string;
  currency: string;
  cancellationPolicy: string | null;
  cancellationHours: number;
  prefill: Prefill;
}) {
  const initial = services.find((s) => s.slug === initialServiceSlug) ?? null;
  const [step, setStep] = useState<Step>(initial ? "time" : "service");
  const [service, setService] = useState<Service | null>(initial);
  const [slots, setSlots] = useState<Slot[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [day, setDay] = useState<string | null>(null);
  const [slot, setSlot] = useState<Slot | null>(null);
  const [partySize, setPartySize] = useState(1);
  const [form, setForm] = useState({ fullName: prefill.fullName, email: prefill.email, phone: prefill.phone, notes: "" });
  const [accept, setAccept] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<Extract<BookingResult, { ok: true }> | null>(null);
  const [pending, startTransition] = useTransition();
  const idemKey = useRef(newKey());
  const topRef = useRef<HTMLDivElement>(null);

  // Load live availability whenever the service changes.
  useEffect(() => {
    if (!service) return;
    let alive = true;
    setSlots(null);
    setLoadError(null);
    setDay(null);
    setSlot(null);
    setPartySize(service.capacity === 2 && !service.is_group ? 2 : 1);
    getSlots(service.id).then((r) => {
      if (!alive) return;
      setSlots(r.slots);
      setLoadError(r.error ?? null);
      const first = r.slots[0];
      if (first) setDay(dateKey(first.startsAt, timeZone));
    });
    return () => {
      alive = false;
    };
  }, [service, timeZone]);

  useEffect(() => {
    topRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [step]);

  const byDay = useMemo(() => {
    const map = new Map<string, Slot[]>();
    for (const s of slots ?? []) {
      const k = dateKey(s.startsAt, timeZone);
      map.set(k, [...(map.get(k) ?? []), s]);
    }
    return map;
  }, [slots, timeZone]);
  const days = useMemo(() => [...byDay.keys()], [byDay]);

  const maxParty = service ? (service.is_group ? Math.min(service.capacity, slot?.spotsLeft ?? service.capacity) : service.capacity) : 1;
  const total = service ? (service.is_group ? service.price_cents * partySize : service.price_cents) : 0;

  function refreshSlots() {
    if (!service) return;
    getSlots(service.id).then((r) => {
      setSlots(r.slots);
      setLoadError(r.error ?? null);
    });
  }

  function submit() {
    if (!service || !slot) return;
    setError(null);
    startTransition(async () => {
      const r = await createBooking({
        serviceId: service.id,
        startsAt: slot.startsAt,
        partySize,
        fullName: form.fullName,
        email: form.email,
        phone: form.phone,
        notes: form.notes,
        idempotencyKey: idemKey.current,
        acceptPolicy: accept as true,
      });
      if (r.ok) {
        setResult(r);
        setStep("done");
      } else {
        setError(r.message);
        if (["SLOT_UNAVAILABLE", "NO_EQUIPMENT", "SESSION_FULL"].includes(r.code)) {
          setSlot(null);
          refreshSlots();
          setStep("time");
        }
      }
    });
  }

  function bookAnother() {
    idemKey.current = newKey();
    setResult(null);
    setSlot(null);
    setAccept(false);
    setError(null);
    setService(null);
    setStep("service");
  }

  const stepIndex = STEPS.findIndex((s) => s.id === step);

  return (
    <div ref={topRef} className="scroll-mt-20">
      {step !== "done" && (
        <ol className="mb-6 flex gap-2" aria-label="Booking progress">
          {STEPS.map((s, i) => (
            <li key={s.id} className="flex-1">
              <div className={`h-1 rounded-full ${i <= stepIndex ? "bg-ink" : "bg-sand"}`} />
              <span className={`mt-1.5 block text-xs ${i === stepIndex ? "text-ink" : "text-muted"}`}>{s.label}</span>
            </li>
          ))}
        </ol>
      )}

      {/* STEP 1 — service */}
      {step === "service" && (
        <section aria-labelledby="h-service">
          <h1 id="h-service" className="font-serif text-4xl">Choose your session</h1>
          <ul className="mt-6 space-y-3">
            {services.map((s) => (
              <li key={s.id}>
                <button
                  type="button"
                  onClick={() => {
                    setService(s);
                    setStep("time");
                  }}
                  className="flex w-full items-center justify-between gap-4 rounded-[var(--radius-card)] border border-sand bg-white p-5 text-left transition hover:border-taupe active:scale-[0.99]"
                >
                  <span>
                    <span className="block font-serif text-2xl">{s.name}</span>
                    <span className="mt-1 flex flex-wrap gap-x-4 text-sm text-muted">
                      <span className="flex items-center gap-1"><ClockIcon className="h-4 w-4" />{s.duration_minutes} min</span>
                      <span className="flex items-center gap-1"><PeopleIcon className="h-4 w-4" />{s.is_group ? `Up to ${s.capacity}` : s.capacity === 1 ? "1 client" : `${s.capacity} clients`}</span>
                    </span>
                  </span>
                  <span className="shrink-0 text-right">
                    <span className="block font-medium">{formatPrice(s.price_cents, currency)}</span>
                    <span className="text-xs text-muted">{s.is_group ? "per person" : "per session"}</span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* STEP 2 — date & time */}
      {step === "time" && service && (
        <section aria-labelledby="h-time">
          <BackButton onClick={() => setStep("service")} label="Change class" />
          <h1 id="h-time" className="font-serif text-4xl">{service.name}</h1>
          <p className="mt-1 text-muted">Pick a day, then a time. Times are shown in studio time.</p>
          {error && <p role="alert" className="mt-4 rounded-xl bg-danger/10 px-4 py-3 text-sm text-danger">{error}</p>}

          {slots === null && !loadError && <SlotSkeleton />}
          {loadError && (
            <p role="alert" className="mt-6 text-danger">
              {loadError} <button className="underline" onClick={refreshSlots}>Retry</button>
            </p>
          )}
          {slots && slots.length === 0 && !loadError && (
            <p className="mt-8 rounded-[var(--radius-card)] bg-cream p-6 text-muted">
              There are no free times in the booking window right now. Please check back soon or contact the studio.
            </p>
          )}

          {days.length > 0 && (
            <>
              <div className="-mx-5 mt-6 overflow-x-auto px-5 pb-2 [scrollbar-width:none]" role="listbox" aria-label="Available days">
                <div className="flex gap-2">
                  {days.map((k) => {
                    const p = keyParts(k);
                    const active = k === day;
                    return (
                      <button
                        key={k}
                        role="option"
                        aria-selected={active}
                        type="button"
                        onClick={() => {
                          setDay(k);
                          setSlot(null);
                        }}
                        className={`flex min-w-[4.25rem] flex-col items-center rounded-2xl border px-3 py-3 transition ${
                          active ? "border-ink bg-ink text-ivory" : "border-sand bg-white hover:border-taupe"
                        }`}
                      >
                        <span className="text-xs uppercase tracking-wide opacity-80">{p.weekdayShort}</span>
                        <span className="font-serif text-2xl leading-tight">{p.day}</span>
                        <span className="text-xs opacity-80">{p.monthShort}</span>
                      </button>
                    );
                  })}
                </div>
              </div>

              {day && (
                <div className="mt-6">
                  <h2 className="text-sm font-medium text-muted">{keyParts(day).long}</h2>
                  <div className="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-4">
                    {(byDay.get(day) ?? []).map((s) => {
                      const active = slot?.startsAt === s.startsAt;
                      return (
                        <button
                          key={s.startsAt}
                          type="button"
                          aria-pressed={active}
                          onClick={() => {
                            setSlot(s);
                            setError(null);
                            if (service.is_group) setPartySize((n) => Math.min(n, s.spotsLeft));
                          }}
                          className={`rounded-xl border px-2 py-3 text-center transition ${
                            active ? "border-ink bg-ink text-ivory" : "border-sand bg-white hover:border-taupe"
                          }`}
                        >
                          <span className="block font-medium">{formatTime(s.startsAt, timeZone)}</span>
                          {service.is_group && (
                            <span className="block text-[11px] opacity-75">{s.spotsLeft} {s.spotsLeft === 1 ? "spot" : "spots"} left</span>
                          )}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              <PrimaryButton disabled={!slot} onClick={() => setStep("details")}>
                Continue
              </PrimaryButton>
            </>
          )}
        </section>
      )}

      {/* STEP 3 — details */}
      {step === "details" && service && slot && (
        <section aria-labelledby="h-details">
          <BackButton onClick={() => setStep("time")} label="Change time" />
          <h1 id="h-details" className="font-serif text-4xl">Your details</h1>
          <form
            className="mt-6 space-y-4"
            onSubmit={(e) => {
              e.preventDefault();
              setStep("review");
            }}
          >
            {maxParty > 1 && (
              <fieldset>
                <legend className="mb-1.5 text-sm text-muted">Number of people</legend>
                <div className="flex gap-2">
                  {Array.from({ length: maxParty }, (_, i) => i + 1).map((n) => (
                    <button
                      key={n}
                      type="button"
                      aria-pressed={partySize === n}
                      onClick={() => setPartySize(n)}
                      className={`h-12 w-12 rounded-full border text-lg ${partySize === n ? "border-ink bg-ink text-ivory" : "border-sand bg-white"}`}
                    >
                      {n}
                    </button>
                  ))}
                </div>
              </fieldset>
            )}
            <Field label="Full name">
              <input required minLength={2} maxLength={120} autoComplete="name" value={form.fullName}
                onChange={(e) => setForm({ ...form, fullName: e.target.value })} className={inputCls} />
            </Field>
            <Field label="Email" hint={prefill.signedIn ? "Your account email" : "We'll send your confirmation here"}>
              <input required type="email" inputMode="email" autoComplete="email" value={form.email} readOnly={prefill.signedIn}
                onChange={(e) => setForm({ ...form, email: e.target.value })} className={`${inputCls} ${prefill.signedIn ? "bg-cream" : ""}`} />
            </Field>
            <Field label="Phone">
              <input type="tel" inputMode="tel" autoComplete="tel" maxLength={40} value={form.phone}
                onChange={(e) => setForm({ ...form, phone: e.target.value })} className={inputCls} />
            </Field>
            <Field label="Anything we should know? (optional)">
              <textarea rows={3} maxLength={1000} value={form.notes} placeholder="Injuries, pregnancy, first time on a reformer…"
                onChange={(e) => setForm({ ...form, notes: e.target.value })} className={inputCls} />
            </Field>
            {!prefill.signedIn && (
              <p className="text-sm text-muted">
                Booking as a guest. <Link href="/login?next=/book" className="text-clay underline">Sign in</Link> to see all your bookings in one place.
              </p>
            )}
            <PrimaryButton type="submit">Review booking</PrimaryButton>
          </form>
        </section>
      )}

      {/* STEP 4 — review */}
      {step === "review" && service && slot && (
        <section aria-labelledby="h-review">
          <BackButton onClick={() => setStep("details")} label="Edit details" />
          <h1 id="h-review" className="font-serif text-4xl">Confirm your booking</h1>
          <Summary service={service} slot={slot} timeZone={timeZone} partySize={partySize} total={total} currency={currency} name={form.fullName} email={form.email} />
          <label className="mt-6 flex items-start gap-3 text-sm">
            <input type="checkbox" checked={accept} onChange={(e) => setAccept(e.target.checked)} className="mt-0.5 h-5 w-5 accent-[var(--color-ink)]" />
            <span>
              I accept the cancellation policy
              {cancellationPolicy ? `: ${cancellationPolicy}` : ` (free cancellation up to ${cancellationHours} hours before).`}
            </span>
          </label>
          <p className="mt-3 text-sm text-muted">Payment is taken at the studio.</p>
          {error && <p role="alert" className="mt-4 rounded-xl bg-danger/10 px-4 py-3 text-sm text-danger">{error}</p>}
          <PrimaryButton disabled={!accept || pending} onClick={submit}>
            {pending ? "Booking…" : "Confirm booking"}
          </PrimaryButton>
        </section>
      )}

      {/* STEP 5 — done */}
      {step === "done" && service && slot && result && (
        <section aria-labelledby="h-done" className="text-center">
          <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-success/15 text-success">
            <CheckIcon className="h-8 w-8" />
          </div>
          <h1 id="h-done" className="mt-5 font-serif text-4xl">{result.status === "pending" ? "Request received" : "You're booked!"}</h1>
          <p className="mt-2 text-muted">A confirmation email is on its way to {form.email}.</p>
          <p className="mt-6 text-sm text-muted">Booking reference</p>
          <p className="font-mono text-3xl tracking-widest">{result.reference}</p>
          <div className="text-left">
            <Summary service={service} slot={slot} timeZone={timeZone} partySize={partySize} total={total} currency={currency} name={form.fullName} email={form.email} />
          </div>
          <div className="mt-6 flex flex-col gap-3">
            <a
              href={icsHref(service.name, slot)}
              download={`booking-${result.reference}.ics`}
              className="rounded-full border border-taupe px-6 py-4"
            >
              Add to calendar
            </a>
            <ShareButton
              data={{
                title: service.name,
                text: `I'm booked for ${service.name} on ${formatDateLong(slot.startsAt, timeZone)} at ${formatTime(slot.startsAt, timeZone)}.`,
                url: typeof window !== "undefined" ? `${window.location.origin}/services/${service.slug}` : undefined,
              }}
            />
            {result.manageToken && !prefill.signedIn && (
              <Link href={`/manage?ref=${result.reference}&token=${result.manageToken}`} className="rounded-full border border-taupe px-6 py-4">
                Manage this booking
              </Link>
            )}
            {prefill.signedIn && (
              <Link href="/account" className="rounded-full border border-taupe px-6 py-4">View my bookings</Link>
            )}
            <button type="button" onClick={bookAnother} className="rounded-full bg-ink px-6 py-4 text-ivory">
              Book another session
            </button>
          </div>
        </section>
      )}
    </div>
  );
}

const inputCls =
  "w-full rounded-xl border border-sand bg-white px-4 py-3.5 text-ink placeholder:text-taupe focus:border-clay focus:outline-none";

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm text-muted">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-xs text-taupe">{hint}</span>}
    </label>
  );
}

function PrimaryButton(props: React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      {...props}
      className="mt-8 w-full rounded-full bg-ink px-6 py-4 font-medium text-ivory transition active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-40"
    />
  );
}

function BackButton({ onClick, label }: { onClick: () => void; label: string }) {
  return (
    <button type="button" onClick={onClick} className="mb-3 -ml-1 inline-flex min-h-11 items-center gap-1 text-sm text-muted hover:text-ink">
      <ChevronLeft className="h-4 w-4" /> {label}
    </button>
  );
}

function Summary(p: { service: Service; slot: Slot; timeZone: string; partySize: number; total: number; currency: string; name: string; email: string }) {
  return (
    <dl className="mt-6 divide-y divide-sand rounded-[var(--radius-card)] bg-white px-5 text-sm shadow-[0_8px_24px_-16px_rgba(47,42,36,.25)]">
      <Row k="Session" v={p.service.name} />
      <Row k="Date" v={formatDateLong(p.slot.startsAt, p.timeZone)} />
      <Row k="Time" v={`${formatTime(p.slot.startsAt, p.timeZone)} – ${formatTime(p.slot.endsAt, p.timeZone)}`} />
      {p.partySize > 1 && <Row k="People" v={String(p.partySize)} />}
      <Row k="Name" v={p.name} />
      <Row k="Email" v={p.email} />
      <Row k="Total" v={formatPrice(p.total, p.currency)} strong />
    </dl>
  );
}

function Row({ k, v, strong }: { k: string; v: string; strong?: boolean }) {
  return (
    <div className="flex justify-between gap-4 py-3">
      <dt className="text-muted">{k}</dt>
      <dd className={`text-right ${strong ? "font-medium" : ""}`}>{v}</dd>
    </div>
  );
}

function SlotSkeleton() {
  return (
    <div className="mt-6 animate-pulse" aria-label="Loading availability">
      <div className="flex gap-2">{Array.from({ length: 5 }, (_, i) => <div key={i} className="h-20 w-[4.25rem] rounded-2xl bg-sand/60" />)}</div>
      <div className="mt-6 grid grid-cols-3 gap-2">{Array.from({ length: 6 }, (_, i) => <div key={i} className="h-12 rounded-xl bg-sand/60" />)}</div>
    </div>
  );
}

function icsHref(title: string, slot: Slot) {
  const f = (iso: string) => new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const ics = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Pilates Studio//Booking//EN", "BEGIN:VEVENT",
    `UID:${f(slot.startsAt)}-${Math.random().toString(36).slice(2)}@pilates`, `DTSTAMP:${f(new Date().toISOString())}`,
    `DTSTART:${f(slot.startsAt)}`, `DTEND:${f(slot.endsAt)}`, `SUMMARY:${title}`, "END:VEVENT", "END:VCALENDAR",
  ].join("\r\n");
  return `data:text/calendar;charset=utf-8,${encodeURIComponent(ics)}`;
}
