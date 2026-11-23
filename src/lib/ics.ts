/** Builds an "Add to calendar" (.ics) data link for a session. */
export function icsHref(title: string, startsAt: string, endsAt: string, location?: string | null) {
  const f = (iso: string) => new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const lines = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Pilates Studio//Booking//EN", "BEGIN:VEVENT",
    `UID:${f(startsAt)}-${Math.random().toString(36).slice(2)}@pilates`, `DTSTAMP:${f(new Date().toISOString())}`,
    `DTSTART:${f(startsAt)}`, `DTEND:${f(endsAt)}`, `SUMMARY:${title}`,
    ...(location ? [`LOCATION:${location.replace(/[,;]/g, " ")}`] : []),
    "END:VEVENT", "END:VCALENDAR",
  ];
  return `data:text/calendar;charset=utf-8,${encodeURIComponent(lines.join("\r\n"))}`;
}
