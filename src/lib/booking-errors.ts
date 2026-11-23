/**
 * The database raises short error codes (e.g. SLOT_UNAVAILABLE) with a
 * human message in the HINT. This turns a Supabase error into something
 * safe to show a visitor — internal details are never exposed.
 */
export type BookingErrorCode =
  | "SLOT_UNAVAILABLE" | "NO_EQUIPMENT" | "SESSION_FULL" | "ALREADY_BOOKED" | "PARTY_SIZE_INVALID"
  | "SERVICE_UNAVAILABLE" | "INVALID_NAME" | "INVALID_EMAIL" | "INVALID_PHONE" | "LATE_CANCELLATION"
  | "NOT_CANCELLABLE" | "NOT_RESCHEDULABLE" | "NOT_FOUND" | "FORBIDDEN" | "OVERRIDE_REASON_REQUIRED"
  | "CAPACITY_BELOW_BOOKED" | "REQUEST_EXISTS" | "REFUND_TOO_LARGE" | "INVALID_AMOUNT"
  | "ONLINE_NOT_ENABLED" | "CLIENT_NOT_FOUND" | "UNKNOWN";

const KNOWN = new Set<string>([
  "SLOT_UNAVAILABLE", "NO_EQUIPMENT", "SESSION_FULL", "ALREADY_BOOKED", "PARTY_SIZE_INVALID",
  "SERVICE_UNAVAILABLE", "INVALID_NAME", "INVALID_EMAIL", "INVALID_PHONE", "LATE_CANCELLATION",
  "NOT_CANCELLABLE", "NOT_RESCHEDULABLE", "NOT_FOUND", "FORBIDDEN", "OVERRIDE_REASON_REQUIRED",
  "CAPACITY_BELOW_BOOKED", "REQUEST_EXISTS", "REFUND_TOO_LARGE", "INVALID_AMOUNT",
  "ONLINE_NOT_ENABLED", "CLIENT_NOT_FOUND",
]);

export function toBookingError(err: { message?: string; hint?: string | null; code?: string } | null) {
  const code = (err?.message ?? "").trim();
  if (KNOWN.has(code)) {
    return { code: code as BookingErrorCode, message: err?.hint || "Something went wrong." };
  }
  // Unique/exclusion violations mean someone else just took the spot.
  if (err?.code === "23505" || err?.code === "23P01") {
    return { code: "SLOT_UNAVAILABLE" as const, message: "Sorry, that time was just taken. Please choose another." };
  }
  return { code: "UNKNOWN" as const, message: "Something went wrong. Please try again." };
}
