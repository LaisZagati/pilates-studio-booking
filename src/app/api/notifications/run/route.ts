import { NextResponse, type NextRequest } from "next/server";
import { runNotificationQueue } from "@/lib/email/queue";

export const dynamic = "force-dynamic";

// Sends due emails (confirmations, reminders...). Called after bookings and by
// Vercel Cron. If CRON_SECRET is set, the request must carry it.
export async function GET(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (secret && req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const result = await runNotificationQueue(50);
  return NextResponse.json(result);
}
