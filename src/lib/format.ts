// Formatting helpers shared by server and client. All times are shown in the
// studio's time zone, whatever the visitor's phone is set to.

export function formatPrice(cents: number, currency = "EUR") {
  return new Intl.NumberFormat("en-IE", {
    style: "currency",
    currency,
    minimumFractionDigits: cents % 100 === 0 ? 0 : 2,
  }).format(cents / 100);
}

export function formatTime(iso: string, timeZone: string) {
  return new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", timeZone }).format(new Date(iso));
}

export function formatDateLong(iso: string, timeZone: string) {
  return new Intl.DateTimeFormat("en-GB", { weekday: "long", day: "numeric", month: "long", timeZone }).format(new Date(iso));
}

/** "YYYY-MM-DD" of an instant, in the studio time zone. */
export function dateKey(iso: string | Date, timeZone: string) {
  const d = typeof iso === "string" ? new Date(iso) : iso;
  return new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit", day: "2-digit", timeZone }).format(d);
}

/** Parts for a date key, interpreted as a calendar date (no time zone drift). */
export function keyParts(key: string) {
  const [y, m, d] = key.split("-").map(Number);
  const utc = new Date(Date.UTC(y, m - 1, d, 12));
  return {
    weekdayShort: new Intl.DateTimeFormat("en-GB", { weekday: "short", timeZone: "UTC" }).format(utc),
    day: d,
    monthShort: new Intl.DateTimeFormat("en-GB", { month: "short", timeZone: "UTC" }).format(utc),
    long: new Intl.DateTimeFormat("en-GB", { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" }).format(utc),
  };
}

export function addDaysKey(key: string, days: number) {
  const [y, m, d] = key.split("-").map(Number);
  const utc = new Date(Date.UTC(y, m - 1, d + days, 12));
  return utc.toISOString().slice(0, 10);
}

export const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

export function hhmm(t: string) {
  return t.slice(0, 5);
}
